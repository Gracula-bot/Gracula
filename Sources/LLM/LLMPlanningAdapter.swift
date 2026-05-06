import Application
import Domain

public struct LLMPlanningAdapter: Planning {
    private let client: any LLMClient
    private let promptCompiler: PromptCompiler
    private let parser: AgentPlanParser
    private let metricsStore: LLMRequestMetricsStore?

    public init(
        client: any LLMClient,
        promptCompiler: PromptCompiler,
        parser: AgentPlanParser,
        metricsStore: LLMRequestMetricsStore? = nil
    ) {
        self.client = client
        self.promptCompiler = promptCompiler
        self.parser = parser
        self.metricsStore = metricsStore
    }

    public func makePlan(
        userText: String,
        context: ConversationContext
    ) async throws -> AgentPlan {
        let request = promptCompiler.compile(userText: userText, context: context)
        let response = try await client.complete(request)
        if let metrics = response.metrics {
            await metricsStore?.record(metrics)
        }
        return try parser.parse(userText: userText, text: response.text)
    }
}
