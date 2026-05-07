import Application
import Domain
import Shared

public struct LLMPlanningAdapter: Planning {
    private let client: any LLMClient
    private let promptCompiler: PromptCompiler
    private let parser: AgentPlanParser
    private let metricsStore: LLMRequestMetricsStore?
    private let traceLogger: TraceLogger?

    public init(
        client: any LLMClient,
        promptCompiler: PromptCompiler,
        parser: AgentPlanParser,
        metricsStore: LLMRequestMetricsStore? = nil,
        traceLogger: TraceLogger? = nil
    ) {
        self.client = client
        self.promptCompiler = promptCompiler
        self.parser = parser
        self.metricsStore = metricsStore
        self.traceLogger = traceLogger
    }

    public func makePlan(
        userText: String,
        context: ConversationContext
    ) async throws -> AgentPlan {
        let request = promptCompiler.compile(userText: userText, context: context)
        await traceLogger?.record(
            level: .debug,
            event: "llm.prompt_compiled",
            component: "LLMPlanningAdapter",
            payload: promptPayload(for: request, context: context)
        )

        let response = try await client.complete(request)
        if let requestLog = response.requestLog {
            await metricsStore?.recordRequest(requestLog)
        }
        if let responseLog = response.responseLog {
            await metricsStore?.recordResponse(responseLog)
        }
        if let metrics = response.metrics {
            await metricsStore?.record(metrics)
        }
        let plan = try parser.parse(userText: userText, text: response.text)
        await traceLogger?.record(
            level: .info,
            event: "llm.plan_parsed",
            component: "LLMPlanningAdapter",
            payload: [
                "summary": .string(plan.summary),
                "tool_call_count": .integer(plan.toolCalls.count)
            ]
        )
        return plan
    }
}

private extension LLMPlanningAdapter {
    func promptPayload(for request: LLMRequest, context: ConversationContext) -> [String: TraceLogValue] {
        var payload: [String: TraceLogValue] = [
            "purpose": .string(request.purpose),
            "model": .string(request.model ?? ""),
            "temperature": .number(request.temperature),
            "top_p": request.topP.map(TraceLogValue.number) ?? .null,
            "max_tokens": request.maxTokens.map(TraceLogValue.integer) ?? .null,
            "conversation_message_count": .integer(context.messages.count)
        ]

        guard traceLogger?.configuration.includeFullContext == true else {
            return payload
        }

        payload["system_prompt"] = .string(request.systemPrompt)
        payload["user_prompt"] = .string(request.userPrompt)
        return payload
    }
}
