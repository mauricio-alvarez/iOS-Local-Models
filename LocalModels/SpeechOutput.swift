import Foundation
import Observation
import AVFoundation

@MainActor @Observable final class SpeechOutput: NSObject, AVSpeechSynthesizerDelegate {
    var text = ""
    var speaking = false
    var error: String?
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var voiceIdentifier: String
    let voices: [AVSpeechSynthesisVoice]
    private let synthesizer = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?

    override init() {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        voices = AVSpeechSynthesisVoice.speechVoices().sorted {
            let lhs = $0.language.hasPrefix(language), rhs = $1.language.hasPrefix(language)
            if lhs != rhs { return lhs }
            return ($0.language, $0.name, $0.identifier) < ($1.language, $1.name, $1.identifier)
        }
        voiceIdentifier = AVSpeechSynthesisVoice(language: Locale.current.identifier)?.identifier ?? voices.first?.identifier ?? ""
        super.init()
        synthesizer.delegate = self
    }
    var voiceName: String { voices.first(where: { $0.identifier == voiceIdentifier })?.name ?? "System default" }

    func read() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !speaking else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let utterance = AVSpeechUtterance(string: content)
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
            utterance.rate = rate
            current = utterance
            speaking = true
            synthesizer.speak(utterance)
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        current = nil
        speaking = false
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func finished(_ utterance: AVSpeechUtterance) {
        guard current === utterance else { return }
        current = nil
        speaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finished(utterance) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finished(utterance) }
    }
}
