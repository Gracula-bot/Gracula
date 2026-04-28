public protocol SpeechSynthesizing: Sendable {
    func speak(_ text: String) async throws
    func stop() async
}

