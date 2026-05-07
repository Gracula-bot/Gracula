import Application
import Domain

public struct PromptCompiler: Sendable {
    private let availableTools: [ToolDescriptor]
    private let model: String?
    private let temperature: Double
    private let topP: Double?
    private let maxTokens: Int?

    public init(
        availableTools: [ToolDescriptor],
        model: String? = nil,
        temperature: Double = 0.0,
        topP: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.availableTools = availableTools.sorted { $0.name < $1.name }
        self.model = model
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
    }

    public func compile(userText: String, context: ConversationContext) -> LLMRequest {
        LLMRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt(userText: userText, context: context),
            purpose: "tool_planning",
            model: model,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens
        )
    }

    private var systemPrompt: String {
        """
        You are a local planning component for a macOS voice agent.
        Return only valid JSON.
        Do not execute actions.
        Do not claim that an action was completed.
        Choose only tools from the provided tool list.
        Use the lowest risk level that matches the tool.
        For messages/emails/payments, prepare drafts or intents first.
        Never send external communication without confirmation.
        Only use publish_onlyfans_post when the user explicitly asks to publish, post, send, or upload a post to OnlyFans.
        If the user asks only to write or draft a post, do not use publish_onlyfans_post.
        Never perform payments or purchases directly.
        """
    }

    private func userPrompt(userText: String, context: ConversationContext) -> String {
        """
        User command:
        \(userText)

        Recent conversation:
        \(conversationText(context))

        Available tools:
        \(toolText)

        Safety rules:
        - safe: can be allowed automatically
        - reversible: requires allowlisted tool and target, otherwise confirmation
        - externalCommunication: always requires confirmation
        - financialOrCritical: always requires strong confirmation phrase

        JSON output schema:
        {
          "summary": "Short action summary",
          "toolCalls": [
            {
              "name": "tool_name",
              "riskLevel": "safe | reversible | externalCommunication | financialOrCritical",
              "arguments": {
                "argumentName": { "string": "value" }
              }
            }
          ]
        }
        """
    }

    private var toolText: String {
        availableTools.map { tool in
            "- \(tool.name): \(tool.description). riskLevel=\(tool.riskLevel.rawValue)"
        }
        .joined(separator: "\n")
    }

    private func conversationText(_ context: ConversationContext) -> String {
        guard !context.messages.isEmpty else {
            return "No prior conversation."
        }

        return context.messages.map { message in
            "\(message.role.rawValue): \(message.text)"
        }
        .joined(separator: "\n")
    }
}
