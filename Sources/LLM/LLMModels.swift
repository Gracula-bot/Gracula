import Foundation

public struct LLMRequest: Codable, Sendable, Equatable {
    public let systemPrompt: String
    public let userPrompt: String
    public let purpose: String
    public let model: String?
    public let temperature: Double
    public let topP: Double?
    public let maxTokens: Int?

    public init(
        systemPrompt: String,
        userPrompt: String,
        purpose: String = "tool_planning",
        model: String? = nil,
        temperature: Double = 0.0,
        topP: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.purpose = purpose
        self.model = model
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
    }
}

public struct LLMResponse: Codable, Sendable, Equatable {
    public let text: String
    public let metrics: LLMRequestMetrics?
    public let requestLog: LoggedLLMRequest?
    public let responseLog: LoggedLLMResponse?

    public init(
        text: String,
        metrics: LLMRequestMetrics? = nil,
        requestLog: LoggedLLMRequest? = nil,
        responseLog: LoggedLLMResponse? = nil
    ) {
        self.text = text
        self.metrics = metrics
        self.requestLog = requestLog
        self.responseLog = responseLog
    }
}

public struct LLMToken: Codable, Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}
