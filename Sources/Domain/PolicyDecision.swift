public enum PolicyDecision: Sendable, Equatable {
    case allow
    case requiresConfirmation(ConfirmationChallenge)
    case deny(String)
}

