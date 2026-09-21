import AppKit
import Carbon
import Darwin

enum PanelPlacement {
    static func canAnchor(_ button: NSRect, on screen: NSRect, left: NSRect?, right: NSRect?) -> Bool {
        guard !button.isEmpty, screen.contains(button) else { return false }
        guard let left, let right else { return true }
        return left.contains(button) || right.contains(button)
    }

    static func floatingFrame(size: NSSize, visible: NSRect) -> NSRect {
        let margin: CGFloat = 16
        let width = min(size.width, max(1, visible.width - margin * 2))
        let height = min(size.height, max(1, visible.height - margin * 2))
        return NSRect(x: visible.maxX - width - margin, y: visible.maxY - height - margin,
                      width: width, height: height)
    }
}

final class SingleInstance {
    private var descriptor: Int32 = -1
    private let identifier: String
    private let directory: URL
    let showNotification: Notification.Name

    init(identifier: String, directory: URL? = nil) {
        self.identifier = identifier
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("North Star", isDirectory: true)
        showNotification = Notification.Name(identifier + ".show")
    }

    func acquire() throws -> Bool {
        // Also recognize older builds that do not hold a lock yet.
        if activateExisting() { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        descriptor = Darwin.open(directory.appendingPathComponent(identifier + ".lock").path,
                                 O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
        let failure = errno
        Darwin.close(descriptor)
        descriptor = -1
        guard failure == EWOULDBLOCK else { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EACCES) }
        _ = activateExisting()
        return false
    }

    private func activateExisting() -> Bool {
        let current = ProcessInfo.processInfo.processIdentifier
        // A deterministic order prevents simultaneous launches from both yielding.
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { !$0.isTerminated && $0.processIdentifier != current }
        guard let existing = candidates.filter({ $0.isFinishedLaunching || $0.processIdentifier < current })
            .sorted(by: { $0.processIdentifier < $1.processIdentifier }).first else { return false }
        DistributedNotificationCenter.default().postNotificationName(showNotification, object: nil,
                                                                      userInfo: nil, deliverImmediately: true)
        existing.activate(options: [.activateAllWindows])
        if let url = existing.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            // Let Launch Services deliver reopen before this duplicate exits.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }
        return true
    }

    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}

final class GlobalShortcut {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    func register() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let pointer, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x4E535452, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { shortcut.action() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        let registration = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x4E535452, id: 1), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &key)
        if registration != noErr { RemoveEventHandler(handler); handler = nil }
        return registration == noErr
    }

    deinit {
        if let key { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}
