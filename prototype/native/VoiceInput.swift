import AVFoundation
import Speech
import SwiftUI

@MainActor final class VoiceInput: ObservableObject {
    @Published var recording = false
    @Published var authorizing = false
    @Published var transcript = ""
    @Published var error: String?
    @Published var language = "en-US"
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var installedTap = false
    private var timeout: Timer?
    private var generation = UUID()

    func start() {
        guard !recording && !authorizing else { return }
        error = nil
        authorizing = true
        let current = UUID()
        generation = current
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard self.generation == current else { return }
                guard status == .authorized else {
                    self.authorizing = false
                    self.error = "Allow Speech Recognition for North Star in System Settings, or type your thought."
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    Task { @MainActor in
                        guard self.generation == current else { return }
                        self.authorizing = false
                        guard allowed else {
                            self.error = "Allow microphone access in System Settings, or type your thought."
                            return
                        }
                        self.begin(current)
                    }
                }
            }
        }
    }

    private func begin(_ current: UUID) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
            error = "Speech recognition is unavailable for this language. You can still type your thought."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            error = "On-device dictation is not available for this language on this Mac. Try English, or type your thought."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request
        transcript = ""
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "No microphone is available. You can still type your thought."
            self.request = nil
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        installedTap = true
        task = recognizer.recognitionTask(with: request) { result, failure in
            Task { @MainActor in
                guard self.generation == current else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if result?.isFinal == true { self.stop() }
                else if let failure, self.recording { self.error = failure.localizedDescription; self.stop() }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            recording = true
            timeout = Timer.scheduledTimer(withTimeInterval: 55, repeats: false) { [weak self] _ in
                guard let recorder = self else { return }
                Task { @MainActor in recorder.stop() }
            }
        } catch { self.error = "The microphone could not start. You can still type your thought."; stop() }
    }

    func stop() {
        generation = UUID()
        authorizing = false
        recording = false
        timeout?.invalidate()
        engine.stop()
        if installedTap { engine.inputNode.removeTap(onBus: 0); installedTap = false }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }
}
