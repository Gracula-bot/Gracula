import Domain

public protocol PolicyChecking: Sendable {
    func evaluate(_ plan: AgentPlan) async throws -> PolicyDecision
}

