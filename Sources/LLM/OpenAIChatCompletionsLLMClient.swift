import Foundation
import Shared

public struct OpenAIChatCompletionsLLMClient: LLMClient {
    private let apiKey: String
    private let endpoint: URL
    private let defaultModel: String
    private let urlSession: URLSession
    private let requestStore: LLMRequestMetricsStore?
    private let traceLogger: TraceLogger?

    public init(
        apiKey: String,
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        defaultModel: String,
        requestStore: LLMRequestMetricsStore? = nil,
        traceLogger: TraceLogger? = nil,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.defaultModel = defaultModel
        self.requestStore = requestStore
        self.traceLogger = traceLogger
        self.urlSession = urlSession
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard !apiKey.isEmpty else {
            throw LLMError.invalidEndpoint("OPENAI_API_KEY is empty.")
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let payload = OpenAIChatCompletionRequest(
            request: request,
            defaultModel: defaultModel
        )
        let body = try JSONEncoder().encode(payload)
        urlRequest.httpBody = body
        let traceID = RequestTrace.current?.traceID
        let redactedRequestBody = TraceRedaction.redact(string: prettyPrintedJSONString(from: body))

        let requestLog = LoggedLLMRequest(
            traceID: traceID,
            provider: "OpenAI Chat Completions",
            endpoint: endpoint.absoluteString,
            model: payload.model,
            purpose: request.purpose,
            parameters: [
                "temperature": .number(request.temperature),
                "top_p": request.topP.map(TraceLogValue.number) ?? .null,
                "max_tokens": request.maxTokens.map(TraceLogValue.integer) ?? .null
            ],
            body: redactedRequestBody
        )
        await requestStore?.recordRequest(requestLog)
        await traceLogger?.record(
            level: .info,
            event: "llm.request",
            component: "OpenAIChatCompletionsLLMClient",
            payload: [
                "provider": .string(requestLog.provider),
                "model": .string(payload.model),
                "purpose": .string(request.purpose),
                "endpoint": .string(endpoint.absoluteString),
                "temperature": .number(request.temperature),
                "top_p": request.topP.map(TraceLogValue.number) ?? .null,
                "max_tokens": request.maxTokens.map(TraceLogValue.integer) ?? .null
            ]
        )
        if traceLogger?.configuration.includeFullContext == true {
            await traceLogger?.record(
                level: .debug,
                event: "llm.request.body",
                component: "OpenAIChatCompletionsLLMClient",
                payload: ["body": .string(requestLog.body)]
            )
        }

        let startedAt = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
            await traceLogger?.record(
                level: .error,
                event: "llm.error",
                component: "OpenAIChatCompletionsLLMClient",
                payload: [
                    "provider": .string(requestLog.provider),
                    "model": .string(payload.model),
                    "purpose": .string(request.purpose),
                    "endpoint": .string(endpoint.absoluteString),
                    "latency_ms": .integer(latency),
                    "retry_count": .integer(0),
                    "error": .string(String(describing: error))
                ]
            )
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidPlannerOutput("OpenAI returned a non-HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data.prefix(1_024), as: UTF8.self)
            let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
            await traceLogger?.record(
                level: .error,
                event: "llm.error",
                component: "OpenAIChatCompletionsLLMClient",
                payload: [
                    "provider": .string(requestLog.provider),
                    "model": .string(payload.model),
                    "purpose": .string(request.purpose),
                    "endpoint": .string(endpoint.absoluteString),
                    "latency_ms": .integer(latency),
                    "retry_count": .integer(0),
                    "status_code": .integer(httpResponse.statusCode),
                    "error": .string(body)
                ]
            )
            throw LLMError.invalidPlannerOutput(
                "OpenAI request failed with HTTP \(httpResponse.statusCode): \(body)"
            )
        }

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let cost = LLMPricingCatalog.cost(
            for: decoded.model,
            promptTokens: decoded.usage?.promptTokens,
            cachedPromptTokens: decoded.usage?.promptTokensDetails?.cachedTokens,
            completionTokens: decoded.usage?.completionTokens
        )
        let responseBody = TraceRedaction.redact(string: prettyPrintedJSONString(from: data))
        let responseLog = LoggedLLMResponse(
            traceID: traceID,
            provider: requestLog.provider,
            model: decoded.model,
            finishReason: decoded.finishReason,
            latencyMilliseconds: latency,
            statusCode: httpResponse.statusCode,
            body: responseBody
        )
        await requestStore?.recordResponse(responseLog)
        await traceLogger?.record(
            level: .info,
            event: "llm.response",
            component: "OpenAIChatCompletionsLLMClient",
            payload: [
                "provider": .string(requestLog.provider),
                "model": .string(decoded.model),
                "purpose": .string(request.purpose),
                "finish_reason": decoded.finishReason.map(TraceLogValue.string) ?? .null,
                "latency_ms": .integer(latency),
                "retry_count": .integer(0),
                "input_tokens": decoded.usage?.promptTokens.map(TraceLogValue.integer) ?? .null,
                "cached_input_tokens": decoded.usage?.promptTokensDetails?.cachedTokens.map(TraceLogValue.integer) ?? .null,
                "output_tokens": decoded.usage?.completionTokens.map(TraceLogValue.integer) ?? .null,
                "total_tokens": decoded.usage?.totalTokens.map(TraceLogValue.integer) ?? .null,
                "cost_usd": cost.map { .number($0.value) } ?? .null,
                "currency": .string(cost?.pricing.currency ?? "USD"),
                "pricing_source": .string(cost?.pricing.source ?? "unpriced"),
                "pricing_version": .string(cost?.pricing.version ?? "none")
            ]
        )
        if traceLogger?.configuration.includeResponseBodies == true {
            await traceLogger?.record(
                level: .debug,
                event: "llm.response.body",
                component: "OpenAIChatCompletionsLLMClient",
                payload: ["body": .string(responseBody)]
            )
        }
        return LLMResponse(
            text: decoded.text,
            metrics: LLMRequestMetrics(
                provider: "OpenAI Chat Completions",
                model: decoded.model,
                purpose: request.purpose,
                temperature: request.temperature,
                topP: request.topP,
                maxTokens: request.maxTokens,
                promptTokens: decoded.usage?.promptTokens,
                cachedPromptTokens: decoded.usage?.promptTokensDetails?.cachedTokens,
                completionTokens: decoded.usage?.completionTokens,
                totalTokens: decoded.usage?.totalTokens,
                latencyMilliseconds: latency,
                finishReason: decoded.finishReason,
                retryCount: 0,
                costUSD: cost?.value,
                currency: cost?.pricing.currency ?? "USD",
                pricingSource: cost?.pricing.source ?? "unpriced",
                pricingVersion: cost?.pricing.version ?? "none"
            ),
            requestLog: requestLog,
            responseLog: responseLog
        )
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMToken, any Error> {
        throw LLMError.unsupportedStreaming
    }
}

private struct OpenAIChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let topP: Double?
    let maxTokens: Int?

    init(request: LLMRequest, defaultModel: String) {
        let trimmedModel = request.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmedModel?.isEmpty == false ? trimmedModel! : defaultModel
        self.messages = [
            Message(role: "system", content: request.systemPrompt),
            Message(role: "user", content: request.userPrompt)
        ]
        self.temperature = request.temperature
        self.topP = request.topP
        self.maxTokens = request.maxTokens
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OpenAIChatCompletionResponse: Decodable {
    let text: String
    let model: String
    let finishReason: String?
    fileprivate let usage: Usage?

    private enum CodingKeys: String, CodingKey {
        case choices
        case model
        case usage
    }

    private struct Choice: Decodable {
        let message: Message
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    private struct Message: Decodable {
        let content: String
    }

    fileprivate struct Usage: Decodable {
        let promptTokens: Int?
        let promptTokensDetails: PromptTokensDetails?
        let completionTokens: Int?
        let totalTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case promptTokensDetails = "prompt_tokens_details"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }

        fileprivate struct PromptTokensDetails: Decodable {
            let cachedTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
        let choices = try container.decode([Choice].self, forKey: .choices)
        self.finishReason = choices.first?.finishReason
        guard let content = choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidPlannerOutput("OpenAI returned an empty chat completion.")
        }
        self.text = content
    }
}
