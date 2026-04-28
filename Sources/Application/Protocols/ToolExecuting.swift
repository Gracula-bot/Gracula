import Domain

public protocol ToolExecuting: Sendable {
    func execute(_ plan: AgentPlan) async throws -> [ToolResult]
}

