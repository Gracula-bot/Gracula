import Application
import Domain
import Foundation
import Voice

@MainActor
public final class AgentViewModel: ObservableObject {
    @Published public var inputText: String
    @Published public var confirmationText: String
    @Published public private(set) var statusText: String
    @Published public private(set) var resultText: String
    @Published public private(set) var pendingChallenge: ConfirmationChallenge?
    @Published public private(set) var auditEntries: [String]
    @Published public private(set) var botSettings: BotSettingsSnapshot?

    private let orchestrator: AgentOrchestrator?
    private let toolExecutor: (any ToolExecuting)?
    private let auditLog: InMemoryAuditLog?
    private let speechSynthesizer: (any SpeechSynthesizing)?
    private var pendingPlan: AgentPlan?

    public init(
        orchestrator: AgentOrchestrator? = nil,
        toolExecutor: (any ToolExecuting)? = nil,
        auditLog: InMemoryAuditLog? = nil,
        speechSynthesizer: (any SpeechSynthesizing)? = nil,
        botSettings: BotSettingsSnapshot? = nil,
        statusText: String = "Ready"
    ) {
        self.orchestrator = orchestrator
        self.toolExecutor = toolExecutor
        self.auditLog = auditLog
        self.speechSynthesizer = speechSynthesizer
        self.inputText = ""
        self.confirmationText = ""
        self.statusText = statusText
        self.resultText = "No command has run yet."
        self.pendingChallenge = nil
        self.auditEntries = []
        self.botSettings = botSettings
    }

    public var canRun: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func run() async {
        guard let orchestrator else {
            resultText = "Agent core is not configured."
            statusText = "Error"
            return
        }

        let command = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return
        }

        statusText = "Thinking"
        pendingPlan = nil
        pendingChallenge = nil
        confirmationText = ""

        do {
            let outcome = try await orchestrator.handleFinalUserText(command)
            apply(outcome)
            await speakCurrentResultIfNeeded()
        } catch {
            statusText = "Error"
            resultText = String(describing: error)
        }

        await refreshAuditEntries()
    }

    public func approvePendingPlan() async {
        guard let pendingPlan, let toolExecutor, let auditLog else {
            return
        }

        if let requiredPhrase = pendingChallenge?.requiredPhrase,
           confirmationText != requiredPhrase {
            statusText = "Confirmation phrase mismatch"
            return
        }

        statusText = "Executing"

        do {
            try await auditLog.record(
                AuditEvent(
                    kind: .confirmationApproved,
                    planID: pendingPlan.id,
                    summary: pendingChallenge?.summary ?? pendingPlan.summary
                )
            )
            let results = try await toolExecutor.execute(pendingPlan)
            resultText = summarize(results)
            statusText = "Executed"
            self.pendingPlan = nil
            pendingChallenge = nil
            confirmationText = ""
            await speakCurrentResultIfNeeded()
        } catch {
            statusText = "Error"
            resultText = String(describing: error)
        }

        await refreshAuditEntries()
    }

    public func stopSpeaking() async {
        await speechSynthesizer?.stop()
    }

    public func rejectPendingPlan() async {
        guard let pendingPlan else {
            return
        }

        do {
            try await auditLog?.record(
                AuditEvent(
                    kind: .confirmationRejected,
                    planID: pendingPlan.id,
                    summary: pendingChallenge?.summary ?? pendingPlan.summary
                )
            )
        } catch {
            resultText = String(describing: error)
        }

        self.pendingPlan = nil
        pendingChallenge = nil
        confirmationText = ""
        statusText = "Rejected"
        resultText = "Action rejected. Nothing was executed."
        await refreshAuditEntries()
    }

    private func apply(_ outcome: AgentOrchestratorOutcome) {
        switch outcome {
        case .executed(_, let results):
            statusText = "Executed"
            resultText = summarize(results)

        case .requiresConfirmation(let plan, let challenge):
            pendingPlan = plan
            pendingChallenge = challenge
            statusText = "Needs confirmation"
            resultText = challenge.summary

        case .denied(_, let reason):
            statusText = "Denied"
            resultText = reason
        }
    }

    private func refreshAuditEntries() async {
        guard let auditLog else {
            auditEntries = []
            return
        }
        auditEntries = await auditLog.events.map { event in
            "\(event.kind.rawValue): \(event.summary)"
        }
    }

    private func speakCurrentResultIfNeeded() async {
        guard let speechSynthesizer else {
            return
        }

        do {
            try await speechSynthesizer.speak(resultText)
        } catch {
            statusText = "TTS error"
        }
    }

    private func summarize(_ results: [ToolResult]) -> String {
        if results.isEmpty {
            return "No tool results."
        }

        return results.map { result in
            switch result {
            case .success(let message):
                message
            case .requiresUserInput(let message):
                message
            case .failed(let message):
                message
            }
        }
        .joined(separator: "\n")
    }
}
