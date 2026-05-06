import Foundation

public struct LocalHTTPLLMClient: LLMClient {
    private let endpoint: URL
    private let urlSession: URLSession
    private let requestStore: LLMRequestMetricsStore?

    public init(
        endpoint: URL,
        requestStore: LLMRequestMetricsStore? = nil,
        urlSession: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.requestStore = requestStore
        self.urlSession = urlSession
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = LocalHTTPRequest(from: request)
        let body = try JSONEncoder().encode(payload)
        urlRequest.httpBody = body

        let requestLog = LoggedLLMRequest(
            provider: "Local HTTP planner",
            endpoint: endpoint.absoluteString,
            body: prettyPrintedJSONString(from: body)
        )
        await requestStore?.recordRequest(requestLog)

        let (data, _) = try await urlSession.data(for: urlRequest)
        let response = try JSONDecoder().decode(LocalHTTPResponse.self, from: data)
        return LLMResponse(
            text: response.text,
            metrics: LLMRequestMetrics(
                provider: "Local HTTP planner",
                model: request.model ?? "Not set",
                temperature: request.temperature
            ),
            requestLog: requestLog
        )
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMToken, any Error> {
        throw LLMError.unsupportedStreaming
    }
}

private struct LocalHTTPRequest: Encodable {
    let model: String?
    let temperature: Double
    let messages: [Message]

    init(from request: LLMRequest) {
        self.model = request.model
        self.temperature = request.temperature
        self.messages = [
            Message(role: "system", content: request.systemPrompt),
            Message(role: "user", content: request.userPrompt)
        ]
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
