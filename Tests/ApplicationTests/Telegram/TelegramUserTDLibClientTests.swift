import Application
import Foundation
import Testing

@Test
func telegramUserClientRestartsAfterClosedAuthorizationState() async {
    let settings = TelegramUserSettings(
        enabled: true,
        apiId: 1,
        apiHash: "hash",
        phoneNumber: "+10000000000",
        databaseDirectory: "/tmp/gracula-tdlib/database",
        filesDirectory: "/tmp/gracula-tdlib/files"
    )
    let closedBridge = MockTDLibJSONBridge(
        responses: [
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateClosed"]
            ]
        ]
    )
    let readyBridge = MockTDLibJSONBridge(
        responses: [
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateReady"]
            ]
        ]
    )
    let state = BridgeFactoryState()
    let client = TelegramUserTDLibClient(settings: settings) { _ in
        state.factoryInvocations += 1
        return state.factoryInvocations == 1 ? closedBridge : readyBridge
    }

    let firstState = await client.start()
    let secondState = await client.start()

    #expect(firstState == .closed)
    #expect(secondState == .ready)
    #expect(state.factoryInvocations == 2)
}

@Test
func telegramBusinessProbeConnectionUsesGetMe() async throws {
    let recorder = TelegramBusinessRequestRecorder()
    let session = makeTelegramBusinessURLSession(recorder: recorder, statusCode: 200, body: """
    {
      "ok": true,
      "result": {
        "id": 123456789,
        "is_bot": true,
        "first_name": "Gracula",
        "username": "gracula_bot"
      }
    }
    """)
    let service = TelegramBusinessBotService(botToken: "123456:secret", urlSession: session)

    try await service.probeConnection()

    #expect(recorder.method == "getMe")
    #expect(recorder.httpMethod == "POST")
    #expect(recorder.jsonBody?.isEmpty == true)
}

@Test
func telegramUserClientEmitsClosedSessionDiagnostics() async {
    let settings = TelegramUserSettings(
        enabled: true,
        apiId: 1,
        apiHash: "hash",
        phoneNumber: "+10000000000",
        databaseDirectory: "/tmp/gracula-tdlib/database",
        filesDirectory: "/tmp/gracula-tdlib/files"
    )
    let diagnostics = DiagnosticBuffer()
    let bridge = MockTDLibJSONBridge(
        responses: [
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateWaitTdlibParameters"]
            ],
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateClosing"]
            ]
        ]
    )
    let client = TelegramUserTDLibClient(
        settings: settings,
        bridgeFactory: { _ in bridge },
        diagnosticSink: { message in
            diagnostics.append(message)
        }
    )

    let state = await client.start()

    #expect(state == .closed)
    let lines = diagnostics.lines()
    #expect(lines.contains { $0.contains("authorization state -> authorizationStateWaitTdlibParameters") })
    #expect(lines.contains { $0.contains("bootstrapping TDLib parameters immediately after client creation") })
    #expect(lines.contains { $0.contains("TDLib session closed") })
}

@Test
func telegramUserClientIgnoresForeignClientUpdates() async {
    let settings = TelegramUserSettings(
        enabled: true,
        apiId: 1,
        apiHash: "hash",
        phoneNumber: "+10000000000",
        databaseDirectory: "/tmp/gracula-tdlib/database",
        filesDirectory: "/tmp/gracula-tdlib/files"
    )
    let diagnostics = DiagnosticBuffer()
    let bridge = MockTDLibJSONBridge(
        clientId: 2,
        responses: [
            [
                "@client_id": 1,
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateClosed"]
            ],
            [
                "@client_id": 2,
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateReady"]
            ]
        ]
    )
    let client = TelegramUserTDLibClient(
        settings: settings,
        bridgeFactory: { _ in bridge },
        diagnosticSink: { message in
            diagnostics.append(message)
        }
    )

    let state = await client.start()

    #expect(state == .ready)
    let lines = diagnostics.lines()
    #expect(lines.contains { $0.contains("ignoring TDLib update for foreign client_id=1; current_client_id=2") })
}

@Test
func telegramUserClientBootstrapsTDLibParametersOnStart() async {
    let settings = TelegramUserSettings(
        enabled: true,
        apiId: 1,
        apiHash: "hash",
        phoneNumber: "+10000000000",
        databaseDirectory: "/tmp/gracula-tdlib/database",
        filesDirectory: "/tmp/gracula-tdlib/files"
    )
    let bridge = MockTDLibJSONBridge(
        responses: [
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateWaitTdlibParameters"]
            ],
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateReady"]
            ]
        ]
    )
    let client = TelegramUserTDLibClient(settings: settings, bridgeFactory: { _ in bridge })

    let state = await client.start()

    #expect(state == .ready)
    #expect(
        !bridge.sentRequests.contains { request in
            (request["@type"] as? String) == "getAuthorizationState"
        }
    )
    #expect(
        bridge.sentRequests.contains { request in
            (request["@type"] as? String) == "setTdlibParameters"
        }
    )
}

@Test
func telegramUserClientSubmitsTDLibParametersOnlyOncePerSession() async {
    let settings = TelegramUserSettings(
        enabled: true,
        apiId: 1,
        apiHash: "hash",
        phoneNumber: "+10000000000",
        databaseDirectory: "/tmp/gracula-tdlib/database",
        filesDirectory: "/tmp/gracula-tdlib/files"
    )
    let bridge = MockTDLibJSONBridge(
        responses: [
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateWaitTdlibParameters"]
            ],
            [
                "@type": "authorizationStateWaitTdlibParameters"
            ],
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateReady"]
            ]
        ]
    )
    let client = TelegramUserTDLibClient(settings: settings, bridgeFactory: { _ in bridge })

    let state = await client.start()

    #expect(state == .ready)
    let parameterRequests = bridge.sentRequests.filter { request in
        (request["@type"] as? String) == "setTdlibParameters"
    }
    #expect(parameterRequests.count == 1)
}

@Test
func telegramUserClientSendsTDLibParametersAtTopLevel() async {
    let settings = TelegramUserSettings(
        enabled: true,
        apiId: 1,
        apiHash: "hash",
        phoneNumber: "+10000000000",
        databaseDirectory: "/tmp/gracula-tdlib/database",
        filesDirectory: "/tmp/gracula-tdlib/files"
    )
    let bridge = MockTDLibJSONBridge(
        responses: [
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateWaitTdlibParameters"]
            ],
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateReady"]
            ]
        ]
    )
    let client = TelegramUserTDLibClient(settings: settings, bridgeFactory: { _ in bridge })

    let state = await client.start()

    #expect(state == .ready)
    let parameterRequest = bridge.sentRequests.first { request in
        (request["@type"] as? String) == "setTdlibParameters"
    }
    #expect(parameterRequest?["parameters"] == nil)
    #expect((parameterRequest?["api_id"] as? Int) == 1)
    #expect((parameterRequest?["api_hash"] as? String) == "hash")
}

@Test
func telegramUserClientRejectsLoginCodeWhileWaitingForPassword() async {
    let settings = TelegramUserSettings(
        enabled: true,
        apiId: 1,
        apiHash: "hash",
        phoneNumber: "+10000000000",
        databaseDirectory: "/tmp/gracula-tdlib/database",
        filesDirectory: "/tmp/gracula-tdlib/files"
    )
    let bridge = MockTDLibJSONBridge(
        responses: [
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateWaitPassword"]
            ]
        ]
    )
    let client = TelegramUserTDLibClient(settings: settings, bridgeFactory: { _ in bridge })

    let startState = await client.start()
    let submissionState = await client.submitCode("12345")

    #expect(startState == .waitingForPassword)
    #expect(
        submissionState
            == .failed("Telegram is waiting for the 2FA password, not a login code.")
    )
    #expect(
        !bridge.sentRequests.contains { request in
            (request["@type"] as? String) == "checkAuthenticationCode"
        }
    )
}

@Test
func telegramUserClientMapsInvalidPasswordToReadableFailure() async {
    let settings = TelegramUserSettings(
        enabled: true,
        apiId: 1,
        apiHash: "hash",
        phoneNumber: "+10000000000",
        databaseDirectory: "/tmp/gracula-tdlib/database",
        filesDirectory: "/tmp/gracula-tdlib/files"
    )
    let bridge = MockTDLibJSONBridge(
        responses: [
            [
                "@type": "updateAuthorizationState",
                "authorization_state": ["@type": "authorizationStateWaitPassword"]
            ],
            [
                "@type": "error",
                "code": 400,
                "message": "PASSWORD_HASH_INVALID"
            ]
        ]
    )
    let client = TelegramUserTDLibClient(settings: settings, bridgeFactory: { _ in bridge })

    let startState = await client.start()
    let submissionState = await client.submitPassword("wrongpass")

    #expect(startState == .waitingForPassword)
    #expect(
        submissionState
            == .failed("Telegram rejected the 2FA password. Enter the correct Telegram password.")
    )
}

private final class MockTDLibJSONBridge: TDLibJSONBridge, @unchecked Sendable {
    private let clientId: Int32
    private var responses: [[String: Any]]
    private(set) var sentRequests: [[String: Any]] = []

    init(clientId: Int32 = 1, responses: [[String: Any]]) {
        self.clientId = clientId
        self.responses = responses
    }

    func createClientId() -> Int32 {
        clientId
    }

    func send(clientId: Int32, request: [String: Any]) throws {
        sentRequests.append(request)
    }

    func receive(timeout: Double) -> [String: Any]? {
        guard !responses.isEmpty else {
            return nil
        }
        return responses.removeFirst()
    }

    func execute(_ request: [String: Any]) throws -> [String: Any]? {
        nil
    }
}

private final class BridgeFactoryState: @unchecked Sendable {
    var factoryInvocations = 0
}

private final class DiagnosticBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(message)
    }

    func lines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class TelegramBusinessRequestRecorder: @unchecked Sendable {
    var method: String?
    var httpMethod: String?
    var jsonBody: [String: Any]?
}

private func makeTelegramBusinessURLSession(
    recorder: TelegramBusinessRequestRecorder,
    statusCode: Int,
    body: String
) -> URLSession {
    TelegramBusinessMockURLProtocol.handler = { request in
        recorder.method = request.url?.lastPathComponent
        recorder.httpMethod = request.httpMethod
        if let bodyData = request.httpBody ?? requestBodyData(from: request),
           let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            recorder.jsonBody = json
        } else {
            recorder.jsonBody = nil
        }
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TelegramBusinessMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class TelegramBusinessMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) = { _ in
        fatalError("TelegramBusinessMockURLProtocol.handler is not configured")
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

private func requestBodyData(from request: URLRequest) -> Data? {
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount < 0 {
            return nil
        }
        if readCount == 0 {
            break
        }
        data.append(buffer, count: readCount)
    }
    return data
}
