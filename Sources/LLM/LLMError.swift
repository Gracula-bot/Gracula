public enum LLMError: Error, Sendable, Equatable {
    case invalidEndpoint(String)
    case invalidPlannerOutput(String)
    case unknownTool(String)
    case invalidRiskLevel(String)
    case unsupportedStreaming
}

