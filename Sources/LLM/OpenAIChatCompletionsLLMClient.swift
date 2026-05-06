import Foundation

public struct OpenAIChatCompletionsLLMClient: LLMClient {
    private let apiKey: String
    private let endpoint: URL
    private let defaultModel: String
    private let urlSession: URLSession
    private let requestStore: LLMRequestMetricsStore?

    public init(
        apiKey: String,
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        defaultModel: String,
        requestStore: LLMRequestMetricsStore? = nil,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.defaultModel = defaultModel
        self.requestStore = requestStore
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

        let requestLog = LoggedLLMRequest(
            provider: "OpenAI Chat Completions",
            endpoint: endpoint.absoluteString,
            body: prettyPrintedJSONString(from: body)
        )
        await requestStore?.recordRequest(requestLog)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidPlannerOutput("OpenAI returned a non-HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data.prefix(1_024), as: UTF8.self)
            throw LLMError.invalidPlannerOutput(
                "OpenAI request failed with HTTP \(httpResponse.statusCode): \(body)"
            )
        }

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        return LLMResponse(
            text: decoded.text,
            metrics: LLMRequestMetrics(
                provider: "OpenAI Chat Completions",
                model: decoded.model,
                temperature: request.temperature,
                promptTokens: decoded.usage?.promptTokens,
                completionTokens: decoded.usage?.completionTokens,
                totalTokens: decoded.usage?.totalTokens
            ),
            requestLog: requestLog
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

    init(request: LLMRequest, defaultModel: String) {
        let trimmedModel = request.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmedModel?.isEmpty == false ? trimmedModel! : defaultModel
        self.messages = [
            Message(role: "system", content: request.systemPrompt),
            Message(role: "user", content: request.userPrompt)
        ]
        self.temperature = request.temperature
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OpenAIChatCompletionResponse: Decodable {
    let text: String
    let model: String
    fileprivate let usage: Usage?

    private enum CodingKeys: String, CodingKey {
        case choices
        case model
        case usage
    }

    private struct Choice: Decodable {
        let message: Message
    }

    private struct Message: Decodable {
        let content: String
    }

    fileprivate struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
        let choices = try container.decode([Choice].self, forKey: .choices)
        guard let content = choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidPlannerOutput("OpenAI returned an empty chat completion.")
        }
        self.text = content
    }
}
