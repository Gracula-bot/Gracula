public enum TranscriptKind: String, Codable, Sendable, Equatable {
    case partial
    case final
}

public struct TranscriptEvent: Codable, Sendable, Equatable {
    public let text: String
    public let kind: TranscriptKind
    public let confidence: Double?

    public init(text: String, kind: TranscriptKind, confidence: Double? = nil) {
        self.text = text
        self.kind = kind
        self.confidence = confidence
    }
}

public protocol SpeechRecognizing: Sendable {
    func transcribe(
        _ audio: AsyncThrowingStream<AudioFrame, any Error>
    ) async throws -> AsyncThrowingStream<TranscriptEvent, any Error>
}

