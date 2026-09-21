import AppKit
import SwiftUI

struct PanelContent: View {
    @ObservedObject var model: AppModel
    let size: NSSize
    var body: some View { PanelView(model: model).frame(width: size.width, height: size.height) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var item: NSStatusItem!
    private var popover: NSPopover!
    private var panel: NSPanel!
    private var content: NSHostingController<PanelContent>!
    private var model: AppModel!
    private var keyboardMonitor: Any?
    private var shortcut: GlobalShortcut?
    private var transferring = false
    let instance: SingleInstance

    init(instance: SingleInstance) { self.instance = instance }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        model = AppModel()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "NorthStar"
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "North Star")
            button.image?.isTemplate = true
            button.toolTip = "North Star · Control–Option–N to open"
            button.target = self
            button.action = #selector(toggle)
        }
        content = NSHostingController(rootView: PanelContent(model: model, size: contentSize(on: targetScreen)))
        popover = NSPopover()
        popover.appearance = NSAppearance(named: .aqua)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "North Star"
        panel.appearance = NSAppearance(named: .aqua)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        shortcut = GlobalShortcut { [weak self] in self?.showFloatingPanel() }
        model.globalShortcutAvailable = shortcut?.register() ?? false
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopen),
                                                             name: instance.showNotification, object: nil)
        // AppKit popovers do not reliably route SwiftUI key equivalents.
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown || self.panel.isVisible else { return event }
            if event.keyCode == 53 { self.hide(); return nil }
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "1": self.model.showRoot("projects")
            case "2": self.model.showRoot("inbox")
            case "k": self.model.capture()
            case "n": self.model.navigate(to: "new")
            case ",": self.model.navigate(to: "settings")
            case "w": self.hide()
            case "[": if self.model.page != "projects" { self.model.back() }
            case "\r", "\u{3}": NotificationCenter.default.post(name: Notification.Name("NorthStarSubmit"), object: nil)
            default: return event
            }
            return nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.show() }
    }

    private var targetScreen: NSScreen {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func contentSize(on screen: NSScreen) -> NSSize {
        NSSize(width: min(470, screen.visibleFrame.width - 32),
               height: min(740, max(1, screen.visibleFrame.height - 80)))
    }

    func show() {
        guard let button = item.button, let window = button.window, let screen = window.screen else {
            showFloatingPanel(); return
        }
        let bounds = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard item.isVisible, PanelPlacement.canAnchor(bounds, on: screen.frame,
            left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea) else {
            showFloatingPanel(); return
        }
        transferring = true
        panel.orderOut(nil)
        panel.contentViewController = nil
        transferring = false
        let size = contentSize(on: screen)
        content.rootView = PanelContent(model: model, size: size)
        popover.contentViewController = content
        popover.contentSize = size
        prepareToShow()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func prepareToShow() {
        model.visible = true
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func reopen() { showFloatingPanel() }

    func showFloatingPanel() {
        guard model != nil else { return }
        let screen = targetScreen
        transferring = true
        if popover.isShown { popover.performClose(nil) }
        popover.contentViewController = nil
        transferring = false
        let size = contentSize(on: screen)
        content.rootView = PanelContent(model: model, size: size)
        panel.contentViewController = content
        panel.setContentSize(size)
        panel.setFrame(PanelPlacement.floatingFrame(size: panel.frame.size, visible: screen.visibleFrame), display: false)
        prepareToShow()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func toggle() {
        if popover.isShown || panel.isVisible { hide() }
        else { show() }
    }

    private func hide() {
        if popover.isShown { popover.performClose(nil) }
        if panel.isVisible { panel.orderOut(nil); didClose() }
    }

    private func didClose() {
        guard !transferring else { return }
        NotificationCenter.default.post(name: Notification.Name("NorthStarPanelClosed"), object: nil)
        model.closed()
    }

    func popoverDidClose(_ notification: Notification) { didClose() }
    func windowWillClose(_ notification: Notification) { didClose() }
    func windowDidResignKey(_ notification: Notification) {
        guard !transferring, panel.isVisible else { return }
        panel.orderOut(nil)
        didClose()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showFloatingPanel()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        shortcut = nil
        DistributedNotificationCenter.default().removeObserver(self)
        model.remember()
        model.shutdown()
    }
}

let app = NSApplication.shared
let instance = SingleInstance(identifier: Bundle.main.bundleIdentifier ?? "local.northstar.prototype")
do {
    guard try instance.acquire() else { exit(0) }
} catch {
    let alert = NSAlert()
    alert.messageText = "North Star could not start"
    alert.informativeText = "The app could not access its local startup file. Try reopening it.\n\n" + error.localizedDescription
    alert.runModal()
    exit(1)
}
let delegate = AppDelegate(instance: instance)
app.delegate = delegate
app.run()
