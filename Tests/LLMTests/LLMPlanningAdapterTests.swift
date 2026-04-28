import Application
import Domain
import LLM
import Testing

@Test
func llmPlanningAdapterCompilesPromptAndParsesResponse() async throws {
    let tools = [
        ToolDescriptor(name: "open_url", description: "Open URL", riskLevel: .safe)
    ]
    let client = FakeLLMClient(
        response: LLMResponse(
            text: """
            {
              "summary": "Open website",
              "toolCalls": [
                {
                  "name": "open_url",
                  "riskLevel": "safe",
                  "arguments": { "url": { "string": "https://apple.com" } }
                }
              ]
            }
            """
        )
    )
    let adapter = LLMPlanningAdapter(
        client: client,
        promptCompiler: PromptCompiler(availableTools: tools),
        parser: AgentPlanParser(availableTools: tools)
    )

    let plan = try await adapter.makePlan(
        userText: "Open apple.com",
        context: ConversationContext(messages: [
            ConversationMessage(role: .user, text: "Previous")
        ])
    )

    #expect(plan.summary == "Open website")
    #expect(plan.toolCalls.first?.name == "open_url")
    #expect(await client.requests.count == 1)
    #expect(await client.requests[0].userPrompt.contains("Previous"))
    #expect(await client.requests[0].userPrompt.contains("open_url"))
}

private actor FakeLLMClient: LLMClient {
    private let response: LLMResponse
    private(set) var requests: [LLMRequest] = []

    init(response: LLMResponse) {
        self.response = response
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        requests.append(request)
        return response
    }

    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMToken, any Error> {
        throw LLMError.unsupportedStreaming
    }
}

