import Domain

public actor ToolRegistry {
    private var tools: [String: any AgentTool]

    public init(tools: [any AgentTool] = []) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    public func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }

    public func resolve(name: String) throws -> any AgentTool {
        guard let tool = tools[name] else {
            throw DomainError.unknownTool(name)
        }
        return tool
    }

    public func descriptors() -> [ToolDescriptor] {
        tools.values
            .map {
                ToolDescriptor(
                    name: $0.name,
                    description: $0.description,
                    riskLevel: $0.riskLevel
                )
            }
            .sorted { $0.name < $1.name }
    }
}

