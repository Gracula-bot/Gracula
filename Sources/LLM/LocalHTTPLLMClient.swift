import Foundation
import Shared

public struct LocalHTTPLLMClient: LLMClient {
    private let endpoint: URL
    private let urlSession: URLSession
    private let requestStore: LLMRequestMetricsStore?
    private let traceLogger: TraceLogger?

    public init(
        endpoint: URL,
        requestStore: LLMRequestMetricsStore? = nil,
        traceLogger: TraceLogger? = nil,
        urlSession: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.requestStore = requestStore
        self.traceLogger = traceLogger
        self.urlSession = urlSession
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = LocalHTTPRequest(from: request)
        let body = try JSONEncoder().encode(payload)
        urlRequest.httpBody = body
        let traceID = RequestTrace.current?.traceID
        let redactedRequestBody = TraceRedaction.redact(string: prettyPrintedJSONString(from: body))

        let requestLog = LoggedLLMRequest(
            traceID: traceID,
            provider: "Local HTTP planner",
            endpoint: endpoint.absoluteString,
            model: request.model ?? "Not set",
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
            component: "LocalHTTPLLMClient",
            payload: [
                "provider": .string(requestLog.provider),
                "model": .string(request.model ?? "Not set"),
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
                component: "LocalHTTPLLMClient",
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
                component: "LocalHTTPLLMClient",
                payload: [
                    "provider": .string(requestLog.provider),
                    "model": .string(request.model ?? "Not set"),
                    "purpose": .string(request.purpose),
                    "endpoint": .string(endpoint.absoluteString),
                    "latency_ms": .integer(latency),
                    "retry_count": .integer(0),
                    "error": .string(String(describing: error))
                ]
            )
            throw error
        }
        let decodedResponse = try JSONDecoder().decode(LocalHTTPResponse.self, from: data)
        let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        let responseBody = TraceRedaction.redact(string: prettyPrintedJSONString(from: data))
        let responseLog = LoggedLLMResponse(
            traceID: traceID,
            provider: requestLog.provider,
            model: request.model ?? "Not set",
            finishReason: nil,
            latencyMilliseconds: latency,
            statusCode: statusCode,
            body: responseBody
        )
        await requestStore?.recordResponse(responseLog)
        await traceLogger?.record(
            level: .info,
            event: "llm.response",
            component: "LocalHTTPLLMClient",
            payload: [
                "provider": .string(requestLog.provider),
                "model": .string(request.model ?? "Not set"),
                "purpose": .string(request.purpose),
                "finish_reason": .null,
                "latency_ms": .integer(latency),
                "retry_count": .integer(0),
                "input_tokens": .null,
                "cached_input_tokens": .null,
                "output_tokens": .null,
                "total_tokens": .null,
                "cost_usd": .number(0),
                "currency": .string("USD"),
                "pricing_source": .string("local-runtime"),
                "pricing_version": .string("local-runtime")
            ]
        )
        if traceLogger?.configuration.includeResponseBodies == true {
            await traceLogger?.record(
                level: .debug,
                event: "llm.response.body",
                component: "LocalHTTPLLMClient",
                payload: ["body": .string(responseBody)]
            )
        }
        return LLMResponse(
            text: decodedResponse.text,
            metrics: LLMRequestMetrics(
                provider: "Local HTTP planner",
                model: request.model ?? "Not set",
                purpose: request.purpose,
                temperature: request.temperature,
                topP: request.topP,
                maxTokens: request.maxTokens,
                latencyMilliseconds: latency,
                finishReason: nil,
                retryCount: 0,
                costUSD: 0,
                currency: "USD",
                pricingSource: "local-runtime",
                pricingVersion: "local-runtime"
            ),
            requestLog: requestLog,
            responseLog: responseLog
        )
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMToken, any Error> {
        throw LLMError.unsupportedStreaming
    }
}

private struct LocalHTTPRequest: Encodable {
    let model: String?
    let temperature: Double
    let topP: Double?
    let maxTokens: Int?
    let messages: [Message]

    init(from request: LLMRequest) {
        self.model = request.model
        self.temperature = request.temperature
        self.topP = request.topP
        self.maxTokens = request.maxTokens
        self.messages = [
            Message(role: "system", content: request.systemPrompt),
            Message(role: "user", content: request.userPrompt)
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case messages
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct LocalHTTPResponse: Decodable {
    let text: String

    private enum CodingKeys: String, CodingKey {
        case text
        case response
        case choices
    }

    private struct Choice: Decodable {
        let message: Message?
        let text: String?
    }

    private struct Message: Decodable {
        let content: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self.text = text
            return
        }

        if let response = try container.decodeIfPresent(String.self, forKey: .response) {
            self.text = response
            return
        }

        if let choices = try container.decodeIfPresent([Choice].self, forKey: .choices),
           let firstChoice = choices.first,
           let content = firstChoice.message?.content ?? firstChoice.text {
            self.text = content
            return
        }

        throw LLMError.invalidPlannerOutput("Unsupported local LLM response shape")
    }
}
