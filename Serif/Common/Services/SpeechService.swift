import Foundation
import AVFoundation
import NaturalLanguage
import SwiftUI

/// Reads email content aloud using `AVSpeechSynthesizer`.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    static let shared = SpeechService()

    /// Identifier of the email currently being read (Email.id.uuidString or
    /// the GmailMessage.id). Lets views toggle their own Listen button without
    /// confusing other open emails.
    @Published private(set) var activeEmailID: String?
    @Published private(set) var isPaused: Bool = false

    var isPlaying: Bool { activeEmailID != nil && !isPaused }

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Starts reading `text`. Cancels any previous playback. `emailID` lets the
    /// view know which Listen button should show the playing state.
    func play(text: String, emailID: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        #if os(iOS)
        // Mix with other audio (e.g. background music) and respect silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: detectLanguageCode(in: cleaned))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        activeEmailID = emailID
        isPaused = false
        synthesizer.speak(utterance)
    }

    func pause() {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        activeEmailID = nil
        isPaused = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Returns the BCP-47 code (e.g. "fr-FR") that best matches the email body,
    /// falling back to the current locale so the voice doesn't sound robotic on
    /// long French emails read with an English voice.
    private func detectLanguageCode(in text: String) -> String {
        let sample = String(text.prefix(500))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let lang = recognizer.dominantLanguage,
           let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix(lang.rawValue) }) {
            return voice.language
        }
        return AVSpeechSynthesisVoice.currentLanguageCode()
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.activeEmailID = nil
            self.isPaused = false
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.activeEmailID = nil
            self.isPaused = false
        }
    }
}
