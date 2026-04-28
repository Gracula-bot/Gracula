import Domain

public struct ToolDescriptor: Sendable, Equatable {
    public let name: String
    public let description: String
    public let riskLevel: ToolRiskLevel

    public init(name: String, description: String, riskLevel: ToolRiskLevel) {
        self.name = name
        self.description = description
        self.riskLevel = riskLevel
    }
}

