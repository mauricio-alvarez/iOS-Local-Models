import SwiftUI
import Speech
import AVFoundation
import Vision
import ImageIO

@MainActor @Observable final class NativeTools {
    var transcript = ""
    var recording = false
    var startingRecording = false
    var recordingStartedAt: Date?
    var recordedDuration: TimeInterval = 0
    var error: String?
    var recognizing = false
    var scannedText = ""
    private let audio = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var permissionAttempt: UUID?
    private var recognitionID: UUID?

    func startRecording() async {
        guard !startingRecording, !recording else { return }
        let attempt = UUID()
        permissionAttempt = attempt
        startingRecording = true
        defer { if permissionAttempt == attempt { startingRecording = false; permissionAttempt = nil } }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard permissionAttempt == attempt else { return }
        guard authorization == .authorized else { error = "Enable Speech Recognition for Local Models in Settings."; return }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard permissionAttempt == attempt else { return }
        guard microphone else { error = "Enable Microphone access for Local Models in Settings."; return }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "Offline speech recognition is unavailable for your current language. Try another device language or install its speech resources in Settings."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            let input = audio.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            hasTap = true
            transcript = ""
            recordedDuration = 0
            let sessionID = UUID()
            recognitionID = sessionID
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                Task { @MainActor in
                    guard let self, self.recording, self.recognitionID == sessionID else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if result?.isFinal == true || failure != nil {
                        self.stopRecording()
                        if let failure { self.error = failure.localizedDescription }
                    }
                }
            }
            audio.prepare()
            try audio.start()
            recording = true
            recordingStartedAt = Date()
        } catch { stopRecording(); self.error = error.localizedDescription }
    }
    func stopRecording() {
        permissionAttempt = nil
        startingRecording = false
        recognitionID = nil
        guard recording || hasTap || request != nil else { return }
        if let start = recordingStartedAt { recordedDuration = Date().timeIntervalSince(start) }
        recordingStartedAt = nil
        recording = false
        audio.stop()
        if hasTap { audio.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func recognize(_ data: Data) async {
        guard !recognizing else { return }
        recognizing = true
        scannedText = ""
        defer { recognizing = false }
        do {
            scannedText = try await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2048
                      ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: image).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }.value
            if scannedText.isEmpty { error = "No readable text found in this image." }
        } catch { self.error = error.localizedDescription }
    }
}
