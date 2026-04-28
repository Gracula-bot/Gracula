import Foundation

public struct LocalHTTPLLMClient: LLMClient {
    private let endpoint: URL
    private let urlSession: URLSession

    public init(endpoint: URL, urlSession: URLSession = .shared) {
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(LocalHTTPRequest(from: request))

        let (data, _) = try await urlSession.data(for: urlRequest)
        let response = try JSONDecoder().decode(LocalHTTPResponse.self, from: data)
        return LLMResponse(text: response.text)
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

