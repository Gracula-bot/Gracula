public enum ToolError: Error, Sendable, Equatable {
    case missingArgument(String)
    case invalidArgument(String)
}

