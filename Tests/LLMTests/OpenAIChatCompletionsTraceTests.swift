import Foundation
import LLM
import Shared
import Testing

@Test
func openAIClientLogsRequestResponseCostAndErrorWithTrace() async throws {
    let session = makeURLSession(statusCode: 200, body: """
    {
      "id": "chatcmpl-1",
      "model": "gpt-5.4-mini",
      "choices": [
        {
          "message": { "content": "{\\"summary\\":\\"noop\\",\\"toolCalls\\":[]}" },
          "finish_reason": "stop"
        }
      ],
      "usage": {
        "prompt_tokens": 1000,
        "prompt_tokens_details": { "cached_tokens": 100 },
        "completion_tokens": 200,
        "total_tokens": 1200
      }
    }
    """)
    let logger = TraceLogger(
        configuration: TraceLoggingConfiguration(
            enabled: true,
            includeFullContext: true,
            includeResponseBodies: true,
            redactSensitiveData: true,
            minimumLevel: .debug
        ),
        logFileURL: nil
    )
    let client = OpenAIChatCompletionsLLMClient(
        apiKey: "sk-secret-test",
        defaultModel: "gpt-5.4-mini",
        traceLogger: logger,
        urlSession: session
    )
    let trace = RequestTraceContext(traceID: "trace-openai-success")

    _ = try await RequestTrace.$current.withValue(trace) {
        try await client.complete(
            LLMRequest(
                systemPrompt: "system",
                userPrompt: "user",
                model: "gpt-5.4-mini",
                temperature: 0.2,
                topP: 0.9,
                maxTokens: 256
            )
        )
    }

    let successEvents = await logger.events()
    #expect(successEvents.map(\.event).contains("llm.request"))
    #expect(successEvents.map(\.event).contains("llm.request.body"))
    #expect(successEvents.map(\.event).contains("llm.response"))
    #expect(successEvents.map(\.event).contains("llm.response.body"))
    #expect(Set(successEvents.compactMap(\.traceID)) == ["trace-openai-success"])

    let responseEvent = try #require(successEvents.last { $0.event == "llm.response" })
    #expect(responseEvent.payload["input_tokens"] == .integer(1000))
    #expect(responseEvent.payload["cached_input_tokens"] == .integer(100))
    #expect(responseEvent.payload["output_tokens"] == .integer(200))
    if case .number(let cost)? = responseEvent.payload["cost_usd"] {
        #expect(cost > 0)
    } else {
        Issue.record("Expected cost_usd number in llm.response event")
    }

    let errorSession = makeFailingURLSession(error: URLError(.badServerResponse))
    let errorLogger = TraceLogger(
        configuration: TraceLoggingConfiguration(
            enabled: true,
            includeFullContext: false,
            includeResponseBodies: false,
            redactSensitiveData: true,
            minimumLevel: .info
        ),
        logFileURL: nil
    )
    let failingClient = OpenAIChatCompletionsLLMClient(
        apiKey: "sk-secret-test",
        defaultModel: "gpt-5.4-mini",
        traceLogger: errorLogger,
        urlSession: errorSession
    )
    let errorTrace = RequestTraceContext(traceID: "trace-openai-error")

    await #expect(throws: Error.self) {
        try await RequestTrace.$current.withValue(errorTrace) {
            try await failingClient.complete(
                LLMRequest(systemPrompt: "system", userPrompt: "user", model: "gpt-5.4-mini")
            )
        }
    }

    let errorEvents = await errorLogger.events()
    #expect(errorEvents.map(\.event).contains("llm.request"))
    #expect(errorEvents.map(\.event).contains("llm.error"))
    #expect(!errorEvents.map(\.event).contains("llm.request.body"))
    #expect(!errorEvents.map(\.event).contains("llm.response.body"))
    #expect(Set(errorEvents.compactMap(\.traceID)) == ["trace-openai-error"])
}

private func makeURLSession(statusCode: Int, body: String) -> URLSession {
    MockURLProtocol.handler = { request in
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func makeFailingURLSession(error: Error) -> URLSession {
    MockURLProtocol.handler = { _ in throw error }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) = { _ in
        fatalError("MockURLProtocol.handler is not configured")
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
