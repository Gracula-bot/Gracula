import Domain

public actor ConversationMemory: AgentMemory {
    private let limit: Int
    private var messages: [ConversationMessage]

    public init(limit: Int = 50, messages: [ConversationMessage] = []) {
        self.limit = max(1, limit)
        self.messages = Array(messages.suffix(self.limit))
    }

    public func append(_ message: ConversationMessage) async throws {
        messages.append(message)
        if messages.count > limit {
            messages.removeFirst(messages.count - limit)
        }
    }

    public func currentContext() async throws -> ConversationContext {
        ConversationContext(messages: messages)
    }
}

