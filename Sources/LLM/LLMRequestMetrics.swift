import Foundation

public struct LLMRequestMetrics: Codable, Sendable, Equatable {
    public let provider: String
    public let model: String
    public let temperature: Double
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    public init(
        provider: String,
        model: String,
        temperature: Double,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.provider = provider
        self.model = model
        self.temperature = temperature
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public actor LLMRequestMetricsStore {
    private var latestMetrics: LLMRequestMetrics?

    public init() {}

    public func record(_ metrics: LLMRequestMetrics) {
        latestMetrics = metrics
    }

    public func latest() -> LLMRequestMetrics? {
        latestMetrics
    }
}
