import Application
import Domain
import LLM
import Testing

@Test
func promptCompilerIncludesCommandContextToolsSafetyAndSchema() {
    let compiler = PromptCompiler(
        availableTools: [
            ToolDescriptor(name: "send_message", description: "Send message", riskLevel: .externalCommunication),
            ToolDescriptor(name: "open_url", description: "Open URL", riskLevel: .safe)
        ],
        model: "local-model",
        temperature: 0.35
    )

    let request = compiler.compile(
        userText: "Open apple.com",
        context: ConversationContext(messages: [
            ConversationMessage(role: .user, text: "Remember this")
        ])
    )

    #expect(request.model == "local-model")
    #expect(request.temperature == 0.35)
    #expect(request.systemPrompt.contains("Return only valid JSON"))
    #expect(request.userPrompt.contains("Open apple.com"))
    #expect(request.userPrompt.contains("Remember this"))
    #expect(request.userPrompt.contains("open_url"))
    #expect(request.userPrompt.contains("send_message"))
    #expect(request.userPrompt.contains("externalCommunication"))
    #expect(request.userPrompt.contains("\"toolCalls\""))
}
