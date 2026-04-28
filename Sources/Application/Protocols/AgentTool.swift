import Domain

public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var riskLevel: ToolRiskLevel { get }

    func run(_ call: ToolCall) async throws -> ToolResult
}

