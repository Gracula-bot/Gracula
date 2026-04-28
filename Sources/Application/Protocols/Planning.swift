import Domain

public protocol Planning: Sendable {
    func makePlan(
        userText: String,
        context: ConversationContext
    ) async throws -> AgentPlan
}

