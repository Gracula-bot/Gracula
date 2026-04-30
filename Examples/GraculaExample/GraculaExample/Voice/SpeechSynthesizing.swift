import Foundation

protocol SpeechSynthesizing: Sendable {
    func prewarm() async throws
    func synthesizeSpeech(from text: String) async throws -> URL
}

extension SpeechSynthesizing {
    func prewarm() async throws {}
}

protocol SpeechSpeaking: Sendable {
    @MainActor func speak(
        _ text: String,
        languageCode: String,
        voiceIdentifier: String?,
        rate: Float,
        pitch: Float
    ) throws
    @MainActor func stop()
}

enum VoiceSynthesisError: LocalizedError {
    case disabled
    case invalidConfiguration(String)
    case emptyText
    case requestFailed(String)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Speech synthesis is disabled."
        case .invalidConfiguration(let message):
            return message
        case .emptyText:
            return "Cannot synthesize empty text."
        case .requestFailed(let message):
            return message
        case .unexpectedResponse(let message):
            return message
        }
    }
}
