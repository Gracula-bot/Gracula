import Foundation

public struct TraceLoggingConfiguration: Sendable, Equatable {
    public enum LogLevel: String, Codable, Sendable, Equatable, CaseIterable {
        case debug
        case info
        case warn
        case error

        fileprivate var priority: Int {
            switch self {
            case .debug: 0
            case .info: 1
            case .warn: 2
            case .error: 3
            }
        }
    }

    public let enabled: Bool
    public let includeFullContext: Bool
    public let includeResponseBodies: Bool
    public let redactSensitiveData: Bool
    public let minimumLevel: LogLevel

    public init(
        enabled: Bool,
        includeFullContext: Bool,
        includeResponseBodies: Bool,
        redactSensitiveData: Bool,
        minimumLevel: LogLevel
    ) {
        self.enabled = enabled
        self.includeFullContext = includeFullContext
        self.includeResponseBodies = includeResponseBodies
        self.redactSensitiveData = redactSensitiveData
        self.minimumLevel = minimumLevel
    }
}

public struct RequestTraceContext: Sendable, Equatable {
    public let traceID: String
    public let sessionID: String?
    public let conversationID: String?
    public let userID: String?
    public let startedAt: Date
    public let metadata: [String: String]

    public init(
        traceID: String = UUID().uuidString.lowercased(),
        sessionID: String? = nil,
        conversationID: String? = nil,
        userID: String? = nil,
        startedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.traceID = traceID
        self.sessionID = sessionID
        self.conversationID = conversationID
        self.userID = userID
        self.startedAt = startedAt
        self.metadata = metadata
    }
}

public enum RequestTrace {
    @TaskLocal public static var current: RequestTraceContext?
}

public struct TraceSummary: Sendable, Equatable {
    public let traceID: String
    public var llmCallCount: Int
    public var toolCallCount: Int
    public var cumulativeCostUSD: Double

    public init(traceID: String, llmCallCount: Int = 0, toolCallCount: Int = 0, cumulativeCostUSD: Double = 0) {
        self.traceID = traceID
        self.llmCallCount = llmCallCount
        self.toolCallCount = toolCallCount
        self.cumulativeCostUSD = cumulativeCostUSD
    }
}

public struct TraceEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: TraceLoggingConfiguration.LogLevel
    public let event: String
    public let component: String
    public let traceID: String?
    public let sessionID: String?
    public let conversationID: String?
    public let userID: String?
    public let payload: [String: TraceLogValue]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: TraceLoggingConfiguration.LogLevel,
        event: String,
        component: String,
        traceID: String?,
        sessionID: String?,
        conversationID: String?,
        userID: String?,
        payload: [String: TraceLogValue]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.event = event
        self.component = component
        self.traceID = traceID
        self.sessionID = sessionID
        self.conversationID = conversationID
        self.userID = userID
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case level
        case event
        case component
        case traceID = "trace_id"
        case sessionID = "session_id"
        case conversationID = "conversation_id"
        case userID = "user_id"
        case payload
    }
}

public final class TraceLogger: @unchecked Sendable {
    public let configuration: TraceLoggingConfiguration
    private let store: TraceLogStore

    public init(configuration: TraceLoggingConfiguration, logFileURL: URL?) {
        self.configuration = configuration
        self.store = TraceLogStore(configuration: configuration, logFileURL: logFileURL)
    }

    public func record(
        level: TraceLoggingConfiguration.LogLevel,
        event: String,
        component: String,
        payload: [String: TraceLogValue] = [:],
        trace: RequestTraceContext? = RequestTrace.current
    ) async {
        await store.record(level: level, event: event, component: component, payload: payload, trace: trace)
    }

    public func events() async -> [TraceEvent] {
        await store.events()
    }

    public func summary(for traceID: String) async -> TraceSummary {
        await store.summary(for: traceID)
    }
}

public enum TraceRedaction {
    public static func redact(string: String) -> String {
        SensitiveDataRedactor().redact(string)
    }

    public static func redact(payload: [String: TraceLogValue]) -> [String: TraceLogValue] {
        SensitiveDataRedactor().redact(payload)
    }
}

private actor TraceLogStore {
    private let configuration: TraceLoggingConfiguration
    private let logFileURL: URL?
    private let encoder: JSONEncoder
    private var recordedEvents: [TraceEvent] = []
    private var summaries: [String: TraceSummary] = [:]
    private let redactor = SensitiveDataRedactor()

    init(configuration: TraceLoggingConfiguration, logFileURL: URL?) {
        self.configuration = configuration
        self.logFileURL = logFileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func record(
        level: TraceLoggingConfiguration.LogLevel,
        event: String,
        component: String,
        payload: [String: TraceLogValue],
        trace: RequestTraceContext?
    ) async {
        guard configuration.enabled else {
            return
        }
        guard level.priority >= configuration.minimumLevel.priority else {
            return
        }

        let sanitizedPayload = configuration.redactSensitiveData ? redactor.redact(payload) : payload
        let eventRecord = TraceEvent(
            level: level,
            event: event,
            component: component,
            traceID: trace?.traceID,
            sessionID: trace?.sessionID,
            conversationID: trace?.conversationID,
            userID: trace?.userID,
            payload: sanitizedPayload
        )

        recordedEvents.append(eventRecord)
        updateSummary(for: eventRecord)
        try? appendToFile(eventRecord)
    }

    func events() -> [TraceEvent] {
        recordedEvents
    }

    func summary(for traceID: String) -> TraceSummary {
        summaries[traceID] ?? TraceSummary(traceID: traceID)
    }

    private func updateSummary(for event: TraceEvent) {
        guard let traceID = event.traceID else {
            return
        }

        var summary = summaries[traceID] ?? TraceSummary(traceID: traceID)
        switch event.event {
        case "llm.request":
            summary.llmCallCount += 1
        case "tool.started":
            summary.toolCallCount += 1
        case "llm.response":
            if case .number(let value)? = event.payload["cost_usd"] {
                summary.cumulativeCostUSD += value
            } else if case .integer(let value)? = event.payload["cost_usd"] {
                summary.cumulativeCostUSD += Double(value)
            }
        default:
            break
        }
        summaries[traceID] = summary
    }

    private func appendToFile(_ event: TraceEvent) throws {
        guard let logFileURL else {
            return
        }

        let directory = logFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        let line = try encoder.encode(event) + Data([0x0A])
        let handle = try FileHandle(forWritingTo: logFileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}

private struct SensitiveDataRedactor {
    private let sensitiveKeys = Set([
        "apikey",
        "api_key",
        "authorization",
        "cookie",
        "password",
        "privatekey",
        "private_key",
        "secret",
        "set-cookie",
        "token"
    ])

    private let stringPatterns: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: "(?i)(authorization\\s*[:=]\\s*bearer\\s+)([^\\s\"']+)", options: []), "$1<redacted>"),
        (try! NSRegularExpression(pattern: "(?i)(bearer\\s+)([^\\s\"']+)", options: []), "$1<redacted>"),
        (try! NSRegularExpression(pattern: "(?i)(api[_-]?key\\s*[:=]\\s*[\"']?)([^\\s,\"']+)", options: []), "$1<redacted>"),
        (try! NSRegularExpression(pattern: "(?i)(token\\s*[:=]\\s*[\"']?)([^\\s,\"']+)", options: []), "$1<redacted>"),
        (try! NSRegularExpression(pattern: "(?i)(secret\\s*[:=]\\s*[\"']?)([^\\s,\"']+)", options: []), "$1<redacted>"),
        (try! NSRegularExpression(pattern: "(?i)(password\\s*[:=]\\s*[\"']?)([^\\s,\"']+)", options: []), "$1<redacted>"),
        (try! NSRegularExpression(pattern: "(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", options: []), "<redacted:private-key>"),
        (try! NSRegularExpression(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: [.caseInsensitive]), "<redacted:email>"),
        (try! NSRegularExpression(pattern: "\\+?\\d[\\d\\s()\\-]{7,}\\d", options: []), "<redacted:phone>")
    ]

    func redact(_ payload: [String: TraceLogValue]) -> [String: TraceLogValue] {
        var redactedPayload: [String: TraceLogValue] = [:]
        for (key, value) in payload {
            redactedPayload[key] = redact(value, key: key)
        }
        return redactedPayload
    }

    func redact(_ value: TraceLogValue, key: String? = nil) -> TraceLogValue {
        if let key, sensitiveKeys.contains(normalized(key)) {
            return .string("<redacted>")
        }

        switch value {
        case .string(let string):
            return .string(redact(string))
        case .object(let object):
            var redactedObject: [String: TraceLogValue] = [:]
            for (nestedKey, nestedValue) in object {
                redactedObject[nestedKey] = redact(nestedValue, key: nestedKey)
            }
            return .object(redactedObject)
        case .array(let array):
            return .array(array.map { redact($0) })
        default:
            return value
        }
    }

    func redact(_ string: String) -> String {
        stringPatterns.reduce(string) { partial, item in
            let range = NSRange(location: 0, length: partial.utf16.count)
            return item.0.stringByReplacingMatches(in: partial, options: [], range: range, withTemplate: item.1)
        }
    }

    private func normalized(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "-", with: "_")
    }
}
