import Domain

public protocol AgentMemory: Sendable {
    func append(_ message: ConversationMessage) async throws
    func currentContext() async throws -> ConversationContext
}

