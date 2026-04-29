import AVFoundation
import Foundation

@MainActor
final class AppleSystemSpeechSpeaker: SpeechSpeaking {
    static let shared = AppleSystemSpeechSpeaker()

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, languageCode: String, voiceIdentifier: String? = nil) throws {
        let utterance = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty else {
            throw VoiceSynthesisError.emptyText
        }

        synthesizer.stopSpeaking(at: .immediate)
        let speechUtterance = AVSpeechUtterance(string: utterance)
        if let voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            speechUtterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: languageCode) {
            speechUtterance.voice = voice
        }
        guard !speechUtterance.speechString.isEmpty else {
            throw VoiceSynthesisError.emptyText
        }

        synthesizer.speak(speechUtterance)
    }
}
