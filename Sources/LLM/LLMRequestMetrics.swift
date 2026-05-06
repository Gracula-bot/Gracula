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

public struct LoggedLLMRequest: Codable, Sendable, Equatable {
    public let provider: String
    public let endpoint: String
    public let body: String

    public init(provider: String, endpoint: String, body: String) {
        self.provider = provider
        self.endpoint = endpoint
        self.body = body
    }
}

public actor LLMRequestMetricsStore {
    private var latestMetrics: LLMRequestMetrics?
    private var latestRequestRecord: LoggedLLMRequest?

    public init() {}

    public func record(_ metrics: LLMRequestMetrics) {
        latestMetrics = metrics
    }

    public func recordRequest(_ request: LoggedLLMRequest) {
        latestRequestRecord = request
    }

    public func latest() -> LLMRequestMetrics? {
        latestMetrics
    }

    public func latestRequest() -> LoggedLLMRequest? {
        latestRequestRecord
    }
}

func prettyPrintedJSONString(from data: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data) else {
        return String(decoding: data, as: UTF8.self)
    }

    guard let prettyData = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
    ) else {
        return String(decoding: data, as: UTF8.self)
    }

    return String(decoding: prettyData, as: UTF8.self)
}
