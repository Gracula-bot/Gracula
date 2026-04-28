import Foundation

public struct AgentPlan: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userText: String
    public let summary: String
    public let toolCalls: [ToolCall]

    public init(
        id: UUID = UUID(),
        userText: String,
        summary: String,
        toolCalls: [ToolCall]
    ) {
        self.id = id
        self.userText = userText
        self.summary = summary
        self.toolCalls = toolCalls
    }

    public var highestRiskLevel: ToolRiskLevel {
        toolCalls.map(\.riskLevel).max() ?? .safe
    }
}

