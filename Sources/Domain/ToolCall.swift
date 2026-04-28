import Foundation

public struct ToolCall: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let arguments: [String: ToolArgument]
    public let riskLevel: ToolRiskLevel

    public init(
        id: UUID = UUID(),
        name: String,
        arguments: [String: ToolArgument],
        riskLevel: ToolRiskLevel
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.riskLevel = riskLevel
    }
}

