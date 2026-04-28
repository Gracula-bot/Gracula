public protocol LLMClient: Sendable {
    func complete(_ request: LLMRequest) async throws -> LLMResponse
    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMToken, any Error>
}

