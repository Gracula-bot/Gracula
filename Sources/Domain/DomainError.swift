public enum DomainError: Error, Sendable, Equatable {
    case invalidToolArgument(String)
    case unknownTool(String)
    case policyDenied(String)
    case invalidPlan(String)
}

