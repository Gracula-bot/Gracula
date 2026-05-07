import Application
import Domain
import Foundation
import LLM
import Shared
import Voice

@MainActor
public final class AgentViewModel: ObservableObject {
    @Published public var inputText: String
    @Published public var confirmationText: String
    @Published public private(set) var statusText: String
    @Published public private(set) var resultText: String
    @Published public private(set) var pendingChallenge: ConfirmationChallenge?
    @Published public private(set) var pendingTelegramReply: PendingTelegramReply?
    @Published public private(set) var auditEntries: [String]
    @Published public private(set) var botSettings: BotSettingsSnapshot?
    @Published public private(set) var llmMetrics: LLMRequestMetrics?
    @Published public private(set) var llmRequestLog: LoggedLLMRequest?
    @Published public private(set) var llmResponseLog: LoggedLLMResponse?
    @Published public private(set) var latestTraceID: String?
    @Published public private(set) var traceEvents: [TraceEvent]

    private let orchestrator: AgentOrchestrator?
    private let voiceCommandRouter: OpenClawVoiceCommandRouter?
    private let toolExecutor: (any ToolExecuting)?
    private let auditLog: InMemoryAuditLog?
    private let speechSynthesizer: (any SpeechSynthesizing)?
    private let llmMetricsStore: LLMRequestMetricsStore?
    private let traceLogger: TraceLogger?
    private let sessionID: String
    private var pendingPlan: AgentPlan?

    public init(
        orchestrator: AgentOrchestrator? = nil,
        voiceCommandRouter: OpenClawVoiceCommandRouter? = nil,
        toolExecutor: (any ToolExecuting)? = nil,
        auditLog: InMemoryAuditLog? = nil,
        speechSynthesizer: (any SpeechSynthesizing)? = nil,
        botSettings: BotSettingsSnapshot? = nil,
        llmMetricsStore: LLMRequestMetricsStore? = nil,
        traceLogger: TraceLogger? = nil,
        statusText: String = "Ready"
    ) {
        self.orchestrator = orchestrator
        self.voiceCommandRouter = voiceCommandRouter
        self.toolExecutor = toolExecutor
        self.auditLog = auditLog
        self.speechSynthesizer = speechSynthesizer
        self.llmMetricsStore = llmMetricsStore
        self.traceLogger = traceLogger
        self.sessionID = UUID().uuidString.lowercased()
        self.inputText = ""
        self.confirmationText = ""
        self.statusText = statusText
        self.resultText = "No command has run yet."
        self.pendingChallenge = nil
        self.pendingTelegramReply = nil
        self.auditEntries = []
        self.botSettings = botSettings
        self.llmMetrics = nil
        self.llmRequestLog = nil
        self.llmResponseLog = nil
        self.latestTraceID = nil
        self.traceEvents = []
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

        let trace = RequestTraceContext(
            sessionID: sessionID,
            conversationID: sessionID,
            metadata: [
                "entry_point": "AgentViewModel.run",
                "surface": "AppShell"
            ]
        )
        latestTraceID = trace.traceID

        await RequestTrace.$current.withValue(trace) {
            statusText = "Thinking"
            pendingPlan = nil
            pendingChallenge = nil
            confirmationText = ""

            await traceLogger?.record(
                level: .info,
                event: "user_request.received",
                component: "AgentViewModel",
                payload: [
                    "text": .string(command),
                    "input_length": .integer(command.count),
                    "surface": .string("AppShell"),
                    "parameters": .object([:]),
                    "metadata": .object(trace.metadata.mapValues(TraceLogValue.string))
                ]
            )

            do {
                if let voiceCommandRouter {
                    let routed = await voiceCommandRouter.route(text: command)
                    if applyTelegramResult(routed) {
                        await speakCurrentResultIfNeeded()
                        await emitFinalTrace(status: "telegram_route")
                        await refreshAuditEntries()
                        return
                    }
                }

                let outcome = try await orchestrator.handleFinalUserText(command)
                apply(outcome)
                await speakCurrentResultIfNeeded()
                await emitFinalTrace(status: finalStatus(for: outcome))
            } catch {
                statusText = "Error"
                resultText = String(describing: error)
                await traceLogger?.record(
                    level: .error,
                    event: "user_request.failed",
                    component: "AgentViewModel",
                    payload: ["error": .string(String(describing: error))]
                )
                await emitFinalTrace(status: "error")
            }
        }

        await refreshLLMState()
        await refreshTraceState()
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

        await refreshLLMState()
        await refreshTraceState()
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

    public func sendPendingTelegramReply() async {
        guard let voiceCommandRouter else {
            return
        }
        let result = await voiceCommandRouter.route(text: "отправь")
        _ = applyTelegramResult(result)
        await speakCurrentResultIfNeeded()
        await refreshLLMState()
        await refreshTraceState()
        await refreshAuditEntries()
    }

    public func cancelPendingTelegramReply() async {
        guard let voiceCommandRouter else {
            return
        }
        let result = await voiceCommandRouter.route(text: "отмени")
        _ = applyTelegramResult(result)
        await speakCurrentResultIfNeeded()
        await refreshLLMState()
        await refreshTraceState()
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

    private func applyTelegramResult(_ result: TelegramCommandResult) -> Bool {
        switch result {
        case .handled(let message, let pendingReply):
            statusText = pendingReply == nil ? "Telegram" : "Telegram draft"
            resultText = message
            pendingTelegramReply = pendingReply
            pendingPlan = nil
            pendingChallenge = nil
            confirmationText = ""
            return true
        case .notTelegramCommand:
            return false
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

    private func refreshLLMState() async {
        llmMetrics = await llmMetricsStore?.latest()
        llmRequestLog = await llmMetricsStore?.latestRequest()
        llmResponseLog = await llmMetricsStore?.latestResponse()
    }

    private func refreshTraceState() async {
        guard let traceLogger else {
            traceEvents = []
            return
        }

        let events = await traceLogger.events()
        if let latestTraceID {
            traceEvents = events.filter { $0.traceID == latestTraceID }
        } else {
            traceEvents = events
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

    private func emitFinalTrace(status: String) async {
        guard let trace = RequestTrace.current else {
            return
        }

        let summary = await traceLogger?.summary(for: trace.traceID)
        await traceLogger?.record(
            level: .info,
            event: "user_response.sent",
            component: "AgentViewModel",
            payload: [
                "status": .string(status),
                "response_text": .string(resultText),
                "total_latency_ms": .integer(Int(Date().timeIntervalSince(trace.startedAt) * 1_000)),
                "total_llm_cost_usd": .number(summary?.cumulativeCostUSD ?? 0),
                "llm_call_count": .integer(summary?.llmCallCount ?? 0),
                "tool_call_count": .integer(summary?.toolCallCount ?? 0)
            ]
        )
    }

    private func finalStatus(for outcome: AgentOrchestratorOutcome) -> String {
        switch outcome {
        case .executed:
            return "executed"
        case .requiresConfirmation:
            return "requires_confirmation"
        case .denied:
            return "denied"
        }
    }
}
