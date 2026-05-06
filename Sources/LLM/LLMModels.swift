import Foundation

public struct LLMRequest: Codable, Sendable, Equatable {
    public let systemPrompt: String
    public let userPrompt: String
    public let model: String?
    public let temperature: Double

    public init(
        systemPrompt: String,
        userPrompt: String,
        model: String? = nil,
        temperature: Double = 0.0
    ) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.model = model
        self.temperature = temperature
    }
}

public struct LLMResponse: Codable, Sendable, Equatable {
    public let text: String
    public let metrics: LLMRequestMetrics?
    public let requestLog: LoggedLLMRequest?

    public init(
        text: String,
        metrics: LLMRequestMetrics? = nil,
        requestLog: LoggedLLMRequest? = nil
    ) {
        self.text = text
        self.metrics = metrics
        self.requestLog = requestLog
    }
}

public struct LLMToken: Codable, Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}
