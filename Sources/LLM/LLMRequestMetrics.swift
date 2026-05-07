import Foundation
import Shared

public struct LLMRequestMetrics: Codable, Sendable, Equatable {
    public let provider: String
    public let model: String
    public let purpose: String
    public let temperature: Double
    public let topP: Double?
    public let maxTokens: Int?
    public let promptTokens: Int?
    public let cachedPromptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?
    public let latencyMilliseconds: Int?
    public let finishReason: String?
    public let retryCount: Int
    public let costUSD: Double?
    public let currency: String?
    public let pricingSource: String?
    public let pricingVersion: String?

    public init(
        provider: String,
        model: String,
        purpose: String,
        temperature: Double,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        promptTokens: Int? = nil,
        cachedPromptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        latencyMilliseconds: Int? = nil,
        finishReason: String? = nil,
        retryCount: Int = 0,
        costUSD: Double? = nil,
        currency: String? = nil,
        pricingSource: String? = nil,
        pricingVersion: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.purpose = purpose
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.promptTokens = promptTokens
        self.cachedPromptTokens = cachedPromptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.latencyMilliseconds = latencyMilliseconds
        self.finishReason = finishReason
        self.retryCount = retryCount
        self.costUSD = costUSD
        self.currency = currency
        self.pricingSource = pricingSource
        self.pricingVersion = pricingVersion
    }
}

public struct LoggedLLMRequest: Codable, Sendable, Equatable {
    public let traceID: String?
    public let provider: String
    public let endpoint: String
    public let model: String
    public let purpose: String
    public let parameters: [String: TraceLogValue]
    public let body: String

    public init(
        traceID: String? = nil,
        provider: String,
        endpoint: String,
        model: String,
        purpose: String,
        parameters: [String: TraceLogValue],
        body: String
    ) {
        self.traceID = traceID
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.purpose = purpose
        self.parameters = parameters
        self.body = body
    }
}

public struct LoggedLLMResponse: Codable, Sendable, Equatable {
    public let traceID: String?
    public let provider: String
    public let model: String
    public let finishReason: String?
    public let latencyMilliseconds: Int?
    public let statusCode: Int?
    public let body: String
    public let errorDescription: String?

    public init(
        traceID: String? = nil,
        provider: String,
        model: String,
        finishReason: String? = nil,
        latencyMilliseconds: Int? = nil,
        statusCode: Int? = nil,
        body: String,
        errorDescription: String? = nil
    ) {
        self.traceID = traceID
        self.provider = provider
        self.model = model
        self.finishReason = finishReason
        self.latencyMilliseconds = latencyMilliseconds
        self.statusCode = statusCode
        self.body = body
        self.errorDescription = errorDescription
    }
}

public actor LLMRequestMetricsStore {
    private var latestMetrics: LLMRequestMetrics?
    private var latestRequestRecord: LoggedLLMRequest?
    private var latestResponseRecord: LoggedLLMResponse?

    public init() {}

    public func record(_ metrics: LLMRequestMetrics) {
        latestMetrics = metrics
    }

    public func recordRequest(_ request: LoggedLLMRequest) {
        latestRequestRecord = request
    }

    public func recordResponse(_ response: LoggedLLMResponse) {
        latestResponseRecord = response
    }

    public func latest() -> LLMRequestMetrics? {
        latestMetrics
    }

    public func latestRequest() -> LoggedLLMRequest? {
        latestRequestRecord
    }

    public func latestResponse() -> LoggedLLMResponse? {
        latestResponseRecord
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
