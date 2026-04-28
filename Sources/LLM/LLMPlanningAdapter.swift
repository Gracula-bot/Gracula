import Application
import Domain

public struct LLMPlanningAdapter: Planning {
    private let client: any LLMClient
    private let promptCompiler: PromptCompiler
    private let parser: AgentPlanParser

    public init(
        client: any LLMClient,
        promptCompiler: PromptCompiler,
        parser: AgentPlanParser
    ) {
        self.client = client
        self.promptCompiler = promptCompiler
        self.parser = parser
    }

    public func makePlan(
        userText: String,
        context: ConversationContext
    ) async throws -> AgentPlan {
        let request = promptCompiler.compile(userText: userText, context: context)
        let response = try await client.complete(request)
        return try parser.parse(userText: userText, text: response.text)
    }
}

