import Domain
import Testing

@Test
func policyDecisionSupportsConfirmationChallengeEquality() {
    let challenge = ConfirmationChallenge(
        title: "Confirm message",
        summary: "Send message to Anna",
        requiredPhrase: nil
    )

    #expect(PolicyDecision.requiresConfirmation(challenge) == .requiresConfirmation(challenge))
    #expect(PolicyDecision.deny("Blocked") == .deny("Blocked"))
    #expect(PolicyDecision.allow == .allow)
}

