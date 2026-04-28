public enum ToolResult: Codable, Sendable, Equatable {
    case success(String)
    case requiresUserInput(String)
    case failed(String)
}

