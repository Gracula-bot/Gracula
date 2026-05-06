import AppKit
import Application
import Automation
import Darwin
import Foundation
import Persistence

struct OpenClawLLMProviderConfiguration {
    let name: String
    let modelPrefixes: [String]
    let environmentKeys: [String]
    let baseURL: String
    let api: String
    let auth: String?
    let authHeader: Bool?
    let modelsJSON: String

    var providerPrefix: String {
        "models.providers.\(name)"
    }

    var baseURLPath: String {
        "\(providerPrefix).baseUrl"
    }

    var apiPath: String {
        "\(providerPrefix).api"
    }

    var modelsPath: String {
        "\(providerPrefix).models"
    }

    var authPath: String {
        "\(providerPrefix).auth"
    }

    var authHeaderPath: String {
        "\(providerPrefix).authHeader"
    }
}

struct OpenClawLLMModelConfiguration {
    let id: String
    let name: String
    let api: String?
    let reasoning: Bool
    let input: [String]
    let contextWindow: Int
    let maxTokens: Int
    let contextTokens: Int?
    let params: [String: Any]
    let compat: [String: Any]

    init(
        id: String,
        name: String,
        api: String? = nil,
        reasoning: Bool,
        input: [String] = ["text"],
        contextWindow: Int,
        maxTokens: Int,
        contextTokens: Int? = nil,
        params: [String: Any] = [:],
        compat: [String: Any] = [:]
    ) {
        self.id = id
        self.name = name
        self.api = api
        self.reasoning = reasoning
        self.input = input
        self.contextWindow = contextWindow
        self.maxTokens = maxTokens
        self.contextTokens = contextTokens
        self.params = params
        self.compat = compat
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "id": id,
            "name": name,
            "reasoning": reasoning,
            "input": input,
            "cost": ["input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0],
            "contextWindow": contextWindow,
            "maxTokens": maxTokens
        ]
        if let api {
            object["api"] = api
        }
        if let contextTokens {
            object["contextTokens"] = contextTokens
        }
        if !params.isEmpty {
            object["params"] = params
        }
        if !compat.isEmpty {
            object["compat"] = compat
        }
        return object
    }

    static func jsonArray(_ models: [OpenClawLLMModelConfiguration]) -> String {
        let objects = models.map(\.jsonObject)
        guard JSONSerialization.isValidJSONObject(objects),
              let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]) else {
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

enum OpenClawLLMConfiguration {
    static let openAIModelRef = "openai/gpt-5.4-mini"
    static let defaultModelRef = openAIModelRef

    static let providers: [OpenClawLLMProviderConfiguration] = [
        OpenClawLLMProviderConfiguration(
            name: "openai",
            modelPrefixes: ["openai/"],
            environmentKeys: ["OPENAI_API_KEY"],
            baseURL: "https://api.openai.com/v1",
            api: "openai-completions",
            auth: "api-key",
            authHeader: true,
            modelsJSON: OpenClawLLMModelConfiguration.jsonArray([
                OpenClawLLMModelConfiguration(
                    id: "gpt-5.4-mini",
                    name: "GPT-5.4 Mini",
                    api: "openai-completions",
                    reasoning: true,
                    input: ["text", "image"],
                    contextWindow: 400000,
                    maxTokens: 128000,
                    params: ["temperature": 0.35, "top_p": 0.85],
                    compat: ["supportsTools": true]
                )
            ])
        )
    ]

    static func provider(named name: String) -> OpenClawLLMProviderConfiguration? {
        providers.first { $0.name == name }
    }

    static func provider(forModelRef modelRef: String) -> OpenClawLLMProviderConfiguration? {
        let normalized = migratedModelRef(modelRef).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return providers.first { provider in
            provider.modelPrefixes.contains { normalized.hasPrefix($0) }
        }
    }

    static func migratedModelRef(_ modelRef: String) -> String {
        let trimmed = modelRef.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultModelRef : trimmed
    }

    static func isLegacyLocalDefault(_ modelRef: String) -> Bool {
        let normalized = modelRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && !normalized.hasPrefix("openai/")
    }

    static func entriesWithProviderDefaults(_ entries: [OpenClawEditableSetting]) -> [OpenClawEditableSetting] {
        var normalized = entries
        for provider in providers {
            ensureEntry(key: provider.baseURLPath, value: provider.baseURL, in: &normalized)
            ensureEntry(key: provider.apiPath, value: provider.api, in: &normalized)
            ensureEntry(key: provider.modelsPath, value: provider.modelsJSON, kind: .array, in: &normalized)
            if let auth = provider.auth {
                ensureEntry(key: provider.authPath, value: auth, in: &normalized)
            }
            if let authHeader = provider.authHeader {
                ensureEntry(key: provider.authHeaderPath, value: authHeader ? "true" : "false", kind: .bool, in: &normalized)
            }
        }
        return normalized
    }

    private static func ensureEntry(
        key: String,
        value: String,
        kind: OpenClawEditableSetting.ValueKind = .string,
        in entries: inout [OpenClawEditableSetting]
    ) {
        guard !entries.contains(where: { $0.key == key }) else {
            return
        }
        entries.append(
            OpenClawEditableSetting(
                key: key,
                source: .json,
                kind: kind,
                isSecret: false,
                value: value
            )
        )
    }
}

private struct OpenClawTaskProfile: Equatable {
    let name: String
    let runtimeContextWindow: Int
    let maxOutputTokens: Int
    let reserveTokens: Int
    let includeCorePersona: Bool
    let includeStyleCard: Bool
    let includeHistory: Bool
    let maxHistoryMessages: Int
    let includeMemorySummary: Bool
    let maxMemoryTokens: Int
    let includeWorkspaceFiles: Bool
    let includeTools: Bool
    let includeSkills: Bool
    let includeFullMemory: Bool
    let includeFullPersonaFiles: Bool
    let includeRag: Bool
    let maxRagExcerpts: Int
    let maxRagTokens: Int
    let maxRetrievedSnippets: Int
    let maxRetrievedTokens: Int
    let minRetrievedScore: Double
    let corePersonaTokens: Int
    let styleCardTokens: Int
    let disableThinking: Bool

    func applyingRuntimeOverrides(
        runtimeContextWindow: Int? = nil,
        maxOutputTokens: Int? = nil,
        reserveTokens: Int? = nil,
        disableThinking: Bool? = nil
    ) -> OpenClawTaskProfile {
        OpenClawTaskProfile(
            name: name,
            runtimeContextWindow: runtimeContextWindow ?? self.runtimeContextWindow,
            maxOutputTokens: maxOutputTokens ?? self.maxOutputTokens,
            reserveTokens: reserveTokens ?? self.reserveTokens,
            includeCorePersona: includeCorePersona,
            includeStyleCard: includeStyleCard,
            includeHistory: includeHistory,
            maxHistoryMessages: maxHistoryMessages,
            includeMemorySummary: includeMemorySummary,
            maxMemoryTokens: maxMemoryTokens,
            includeWorkspaceFiles: includeWorkspaceFiles,
            includeTools: includeTools,
            includeSkills: includeSkills,
            includeFullMemory: includeFullMemory,
            includeFullPersonaFiles: includeFullPersonaFiles,
            includeRag: includeRag,
            maxRagExcerpts: maxRagExcerpts,
            maxRagTokens: maxRagTokens,
            maxRetrievedSnippets: maxRetrievedSnippets,
            maxRetrievedTokens: maxRetrievedTokens,
            minRetrievedScore: minRetrievedScore,
            corePersonaTokens: corePersonaTokens,
            styleCardTokens: styleCardTokens,
            disableThinking: disableThinking ?? self.disableThinking
        )
    }

    static let notificationSpeech = OpenClawTaskProfile(
        name: "notification_speech",
        runtimeContextWindow: 4096,
        maxOutputTokens: 128,
        reserveTokens: 512,
        includeCorePersona: true,
        includeStyleCard: true,
        includeHistory: false,
        maxHistoryMessages: 0,
        includeMemorySummary: false,
        maxMemoryTokens: 0,
        includeWorkspaceFiles: false,
        includeTools: false,
        includeSkills: false,
        includeFullMemory: false,
        includeFullPersonaFiles: false,
        includeRag: true,
        maxRagExcerpts: 2,
        maxRagTokens: 600,
        maxRetrievedSnippets: 2,
        maxRetrievedTokens: 600,
        minRetrievedScore: 0.28,
        corePersonaTokens: 340,
        styleCardTokens: 160,
        disableThinking: true
    )

    static let simpleChat = OpenClawTaskProfile(
        name: "simple_chat",
        runtimeContextWindow: 8192,
        maxOutputTokens: 512,
        reserveTokens: 1024,
        includeCorePersona: true,
        includeStyleCard: true,
        includeHistory: true,
        maxHistoryMessages: 6,
        includeMemorySummary: true,
        maxMemoryTokens: 800,
        includeWorkspaceFiles: false,
        includeTools: false,
        includeSkills: false,
        includeFullMemory: false,
        includeFullPersonaFiles: false,
        includeRag: true,
        maxRagExcerpts: 3,
        maxRagTokens: 1000,
        maxRetrievedSnippets: 3,
        maxRetrievedTokens: 1000,
        minRetrievedScore: 0.22,
        corePersonaTokens: 340,
        styleCardTokens: 160,
        disableThinking: true
    )

    static let deepPersona = OpenClawTaskProfile(
        name: "deep_persona",
        runtimeContextWindow: 16384,
        maxOutputTokens: 2048,
        reserveTokens: 4096,
        includeCorePersona: true,
        includeStyleCard: true,
        includeHistory: true,
        maxHistoryMessages: 20,
        includeMemorySummary: true,
        maxMemoryTokens: 2000,
        includeWorkspaceFiles: false,
        includeTools: false,
        includeSkills: false,
        includeFullMemory: true,
        includeFullPersonaFiles: true,
        includeRag: true,
        maxRagExcerpts: 6,
        maxRagTokens: 5000,
        maxRetrievedSnippets: 6,
        maxRetrievedTokens: 5000,
        minRetrievedScore: 0.16,
        corePersonaTokens: 800,
        styleCardTokens: 400,
        disableThinking: false
    )
}

private struct OpenClawPromptSection: Equatable {
    let name: String
    let text: String
}

private struct OpenClawLayeredPrompt: Equatable {
    let text: String
    let breakdown: OpenClawPromptBreakdown
}

private struct OpenClawPromptBreakdown: Equatable {
    struct Section: Equatable {
        let name: String
        let estimatedTokens: Int
        let characters: Int
    }

    let taskProfile: String
    let modelName: String
    let providerName: String
    let qdrantQuery: String
    let qdrantFilters: String
    let retrievedSnippetIDs: [String]
    let retrievedSnippetSources: [String]
    let retrievedSnippetScores: [Double]
    let retrievedTokenCount: Int
    let systemTokens: Int
    let userTokens: Int
    let historyTokens: Int
    let workspaceTokens: Int
    let toolsSkillsTokens: Int
    let memoryTokens: Int
    let ragTokens: Int
    let totalTokens: Int
    let runtimeContextWindow: Int
    let modelContextWindow: Int
    let reserveTokens: Int
    let maxOutputTokens: Int
    let shrinkingApplied: Bool
    let dropped: [String]
    let sections: [Section]
}

private struct OpenClawRetrievalQuery: Equatable {
    enum Mode: String, Equatable {
        case notificationSpeech
        case simpleChat
        case deepPersona
    }

    let mode: Mode
    let text: String
    let language: String
    let app: String?
    let title: String?
    let channel: String?
    let body: String?

    static func notificationSpeech(from prompt: String) -> OpenClawRetrievalQuery {
        let app = labeledValue("App", in: prompt)
        let title = labeledValue("Title", in: prompt)
        let subtitle = labeledValue("Subtitle", in: prompt)
        let body = labeledValue("Body", in: prompt)
        let fallback = prompt.components(separatedBy: "Fallback spoken text:")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let queryText = [
            app,
            title,
            subtitle,
            body,
            fallback
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return OpenClawRetrievalQuery(
            mode: .notificationSpeech,
            text: queryText.isEmpty ? prompt : queryText,
            language: "ru",
            app: app,
            title: title,
            channel: labeledValue("Channel", in: prompt),
            body: body
        )
    }

    static func simpleChat(_ text: String) -> OpenClawRetrievalQuery {
        OpenClawRetrievalQuery(
            mode: .simpleChat,
            text: text,
            language: "ru",
            app: nil,
            title: nil,
            channel: nil,
            body: nil
        )
    }

    static func deepPersona(_ text: String) -> OpenClawRetrievalQuery {
        OpenClawRetrievalQuery(
            mode: .deepPersona,
            text: text,
            language: "ru",
            app: nil,
            title: nil,
            channel: nil,
            body: nil
        )
    }

    static func labeledValue(_ label: String, in text: String) -> String? {
        let prefix = "\(label):"
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(prefix) else {
                continue
            }
            let value = trimmed.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

private struct OpenClawRetrievedSnippet: Equatable {
    let id: String
    let kind: String
    let profile: String
    let source: String
    let language: String
    let channel: String?
    let app: String?
    let priority: Int
    let tokenEstimate: Int
    let text: String
    let score: Double
}

private struct OpenClawSelectiveMemoryResult: Equatable {
    let text: String
    let snippets: [OpenClawRetrievedSnippet]
    let query: OpenClawRetrievalQuery
    let filters: String

    static func empty(query: OpenClawRetrievalQuery, profile: OpenClawTaskProfile) -> OpenClawSelectiveMemoryResult {
        OpenClawSelectiveMemoryResult(
            text: "",
            snippets: [],
            query: query,
            filters: OpenClawQdrantClient.memoryFilterDescription(profile: profile, language: query.language),
        )
    }
}

private struct OpenClawNotificationCacheResult: Equatable {
    enum Action: Equatable {
        case reuseSpokenText
        case reuseSkip
        case useAsExample
    }

    let id: String
    let action: Action
    let spokenText: String
    let score: Double
    let app: String
    let title: String
}

private struct OpenClawQdrantClient {
    let baseURL: URL
    let apiKey: String?

    static let memoryCollection = "gracula_memory"
    static let notificationCacheCollection = "gracula_notification_cache"
    static let telegramBusinessCollection = "gracula_telegram_business_messages"
    private static let placeholderVector = [0.0]

    static func make(environment: [String: String]) -> OpenClawQdrantClient? {
        if boolFlag(environment["GRACULA_QDRANT_DISABLED"]) || boolFlag(environment["OPENCLAW_QDRANT_DISABLED"]) {
            return nil
        }
        let rawBaseURL = [
            environment["GRACULA_QDRANT_URL"],
            environment["OPENCLAW_QDRANT_URL"],
            environment["QDRANT_URL"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "http://127.0.0.1:6333"
        guard let baseURL = URL(string: rawBaseURL) else {
            return nil
        }
        if isClosedLocalTCPPort(baseURL) {
            return nil
        }
        let apiKey = [
            environment["GRACULA_QDRANT_API_KEY"],
            environment["OPENCLAW_QDRANT_API_KEY"],
            environment["QDRANT_API_KEY"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return OpenClawQdrantClient(baseURL: baseURL, apiKey: apiKey)
    }

    private static func isClosedLocalTCPPort(_ url: URL) -> Bool {
        guard let host = url.host,
              ["127.0.0.1", "localhost", "::1"].contains(host),
              let port = url.port else {
            return false
        }

        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFileDescriptor >= 0 else {
            return false
        }
        defer {
            close(socketFileDescriptor)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET, host == "localhost" ? "127.0.0.1" : host, &address.sin_addr) == 1 else {
            return false
        }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(
                    socketFileDescriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) != 0
            }
        }
    }

    private static func boolFlag(_ rawValue: String?) -> Bool {
        guard let rawValue else {
            return false
        }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    func ensurePayloadIndexes() async {
        try? await ensureCollection(Self.memoryCollection)
        try? await ensureCollection(Self.notificationCacheCollection)
        try? await ensureCollection(Self.telegramBusinessCollection)

        let memoryFields: [(String, String)] = [
            ("kind", "keyword"),
            ("profile", "keyword"),
            ("source", "keyword"),
            ("language", "keyword"),
            ("channel", "keyword"),
            ("app", "keyword"),
            ("priority", "integer"),
            ("created_at", "datetime")
        ]
        let cacheFields: [(String, String)] = [
            ("kind", "keyword"),
            ("app", "keyword"),
            ("channel", "keyword"),
            ("language", "keyword"),
            ("created_at", "datetime")
        ]
        let telegramFields: [(String, String)] = [
            ("kind", "keyword"),
            ("business_connection_id", "keyword"),
            ("chat_id", "integer"),
            ("chat_name", "keyword"),
            ("sender_username", "keyword"),
            ("direction", "keyword"),
            ("created_at", "datetime")
        ]

        for field in memoryFields {
            try? await createPayloadIndex(collection: Self.memoryCollection, fieldName: field.0, fieldSchema: field.1)
        }
        for field in cacheFields {
            try? await createPayloadIndex(collection: Self.notificationCacheCollection, fieldName: field.0, fieldSchema: field.1)
        }
        for field in telegramFields {
            try? await createPayloadIndex(collection: Self.telegramBusinessCollection, fieldName: field.0, fieldSchema: field.1)
        }
    }

    private func ensureCollection(_ collection: String) async throws {
        let body: [String: Any] = [
            "vectors": [
                "size": Self.placeholderVector.count,
                "distance": "Cosine"
            ]
        ]
        try await request(
            path: "/collections/\(collection)",
            method: "PUT",
            body: body,
            acceptedStatusCodes: Set(200..<300).union([409])
        )
    }

    func retrieve(query: OpenClawRetrievalQuery, profile: OpenClawTaskProfile) async throws -> [OpenClawRetrievedSnippet] {
        let kinds = allowedKinds(for: profile)
        guard !kinds.isEmpty, profile.maxRetrievedSnippets > 0, profile.maxRetrievedTokens > 0 else {
            return []
        }

        let points = try await scrollMemory(profile: profile.name, language: query.language, kinds: kinds)
        let queryTokens = lexicalTokens(query.text)
        let scored = points.compactMap { point -> OpenClawRetrievedSnippet? in
            guard var snippet = point.snippet else {
                return nil
            }
            guard channelMatches(snippet.channel, queryChannel: query.channel) else {
                return nil
            }
            let score = relevanceScore(
                snippet: snippet,
                query: query,
                queryTokens: queryTokens
            )
            guard score >= profile.minRetrievedScore else {
                return nil
            }
            snippet = OpenClawRetrievedSnippet(
                id: snippet.id,
                kind: snippet.kind,
                profile: snippet.profile,
                source: snippet.source,
                language: snippet.language,
                channel: snippet.channel,
                app: snippet.app,
                priority: snippet.priority,
                tokenEstimate: snippet.tokenEstimate,
                text: snippet.text,
                score: score
            )
            return snippet
        }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.priority > rhs.priority
                }
                return lhs.score > rhs.score
            }

        var selected: [OpenClawRetrievedSnippet] = []
        var tokenTotal = 0
        for snippet in scored {
            guard selected.count < profile.maxRetrievedSnippets else {
                break
            }
            let snippetTokens = min(snippet.tokenEstimate, estimatedTokenCount(snippet.text))
            guard tokenTotal + snippetTokens <= profile.maxRetrievedTokens else {
                continue
            }
            tokenTotal += snippetTokens
            selected.append(snippet)
        }
        return selected
    }

    func storeNotificationCache(inputPrompt: String, spokenText: String, decision: String) async {
        let query = OpenClawRetrievalQuery.notificationSpeech(from: inputPrompt)
        let now = ISO8601DateFormatter().string(from: Date())
        var payload: [String: Any] = [
            "kind": "notification_cache",
            "spoken_text": spokenText,
            "decision": decision,
            "language": query.language,
            "created_at": now,
            "last_used_at": now
        ]
        payload["app"] = query.app ?? ""
        payload["title"] = query.title ?? ""
        payload["channel"] = query.channel ?? ""
        payload["body"] = query.body ?? query.text
        let point: [String: Any] = [
            "id": UUID().uuidString,
            "payload": payload,
            "vector": Self.placeholderVector
        ]
        let body: [String: Any] = [
            "points": [point]
        ]
        _ = try? await request(
            path: "/collections/\(Self.notificationCacheCollection)/points",
            method: "PUT",
            body: body
        )
    }

    func notificationCacheResult(query: OpenClawRetrievalQuery) async throws -> OpenClawNotificationCacheResult? {
        let points = try await scrollNotificationCache(language: query.language, app: query.app)
        let queryTokens = lexicalTokens(cacheComparableText(app: query.app, title: query.title, body: query.body ?? query.text))
        guard !queryTokens.isEmpty else {
            return nil
        }

        let scored = points.compactMap { point -> (point: QdrantPoint, score: Double)? in
            let spokenText = point.string("spoken_text")
            let decision = point.string("decision")
            guard decision == "speak" || decision == "skip" else {
                return nil
            }
            let cacheTokens = lexicalTokens(cacheComparableText(
                app: point.optionalString("app"),
                title: point.optionalString("title"),
                body: point.optionalString("body")
            ))
            guard !cacheTokens.isEmpty else {
                return nil
            }
            let intersection = queryTokens.intersection(cacheTokens).count
            let union = queryTokens.union(cacheTokens).count
            let score = Double(intersection) / Double(max(1, union))
            guard score >= 0.54 else {
                return nil
            }
            guard !spokenText.isEmpty || decision == "skip" else {
                return nil
            }
            return (point, score)
        }
            .sorted { $0.score > $1.score }

        guard let best = scored.first else {
            return nil
        }

        let decision = best.point.string("decision")
        let spokenText = best.point.string("spoken_text")
        let action: OpenClawNotificationCacheResult.Action
        if best.score >= 0.72 {
            action = decision == "skip" ? .reuseSkip : .reuseSpokenText
            await updateNotificationCacheLastUsed(pointID: best.point.id)
        } else {
            guard decision == "speak", !spokenText.isEmpty else {
                return nil
            }
            action = .useAsExample
        }

        return OpenClawNotificationCacheResult(
            id: best.point.id,
            action: action,
            spokenText: spokenText.isEmpty ? "Пропускаю шумное уведомление." : spokenText,
            score: best.score,
            app: best.point.string("app"),
            title: best.point.string("title")
        )
    }

    func storeBusinessMessage(_ message: TelegramBusinessIncomingMessage, direction: String = "incoming") async {
        await ensurePayloadIndexes()
        let payload: [String: Any] = [
            "kind": "telegram_business_message",
            "business_connection_id": message.businessConnectionId,
            "message_id": message.messageId,
            "chat_id": message.chat.id,
            "chat_type": message.chat.type,
            "chat_name": message.chat.displayName,
            "chat_username": message.chat.username ?? "",
            "sender_name": message.senderName ?? "",
            "sender_username": message.senderUsername ?? "",
            "direction": direction,
            "text": message.text,
            "source": "telegram_business",
            "language": "ru",
            "created_at": ISO8601DateFormatter().string(from: message.date),
            "token_estimate": estimatedTokenCount(message.text)
        ]
        let point: [String: Any] = [
            "id": businessMessagePointID(message, direction: direction),
            "payload": payload,
            "vector": Self.placeholderVector
        ]
        _ = try? await request(
            path: "/collections/\(Self.telegramBusinessCollection)/points",
            method: "PUT",
            body: ["points": [point]]
        )
    }

    func businessMessageExists(_ message: TelegramBusinessIncomingMessage, direction: String = "incoming") async -> Bool {
        await ensurePayloadIndexes()
        let body: [String: Any] = [
            "ids": [businessMessagePointID(message, direction: direction)],
            "with_payload": false,
            "with_vector": false
        ]
        guard let data = try? await request(
            path: "/collections/\(Self.telegramBusinessCollection)/points",
            method: "POST",
            body: body
        ),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [[String: Any]] else {
            return false
        }
        return result.isEmpty == false
    }

    private func businessMessagePointID(_ message: TelegramBusinessIncomingMessage, direction: String) -> String {
        "tg-business-\(message.businessConnectionId)-\(message.chat.id)-\(message.messageId)-\(direction)"
    }

    func storeBusinessReply(
        businessConnectionId: String,
        chat: TelegramBusinessChat,
        text: String
    ) async {
        let message = TelegramBusinessIncomingMessage(
            updateId: 0,
            businessConnectionId: businessConnectionId,
            messageId: Int(Date().timeIntervalSince1970),
            chat: chat,
            senderName: "Gracula",
            senderUsername: nil,
            text: text,
            date: Date()
        )
        await storeBusinessMessage(message, direction: "outgoing")
    }

    func searchBusinessMessages(
        query: String,
        businessConnectionId: String,
        chatId: Int64,
        limit: Int = 8
    ) async -> [OpenClawRetrievedSnippet] {
        let filter: [String: Any] = [
            "must": [
                ["key": "kind", "match": ["value": "telegram_business_message"]],
                ["key": "business_connection_id", "match": ["value": businessConnectionId]],
                ["key": "chat_id", "match": ["value": chatId]]
            ]
        ]
        let body: [String: Any] = [
            "filter": filter,
            "limit": 64,
            "with_payload": true,
            "with_vector": false
        ]
        guard let data = try? await request(
            path: "/collections/\(Self.telegramBusinessCollection)/points/scroll",
            method: "POST",
            body: body
        ),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let points = result["points"] as? [[String: Any]] else {
            return []
        }
        let queryTokens = lexicalTokens(query)
        return points.compactMap(QdrantPoint.init)
            .compactMap { point -> OpenClawRetrievedSnippet? in
                let text = point.string("text")
                guard !text.isEmpty else {
                    return nil
                }
                let score = jaccardScore(lhs: queryTokens, rhs: lexicalTokens(text))
                return OpenClawRetrievedSnippet(
                    id: point.id,
                    kind: "telegram_business_message",
                    profile: "telegram_business",
                    source: "telegram_business:\(point.string("chat_name"))",
                    language: point.string("language", fallback: "ru"),
                    channel: nil,
                    app: "Telegram",
                    priority: 0,
                    tokenEstimate: max(1, point.int("token_estimate", fallback: estimatedTokenCount(text))),
                    text: text,
                    score: score
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.id > rhs.id
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    private func allowedKinds(for profile: OpenClawTaskProfile) -> [String] {
        switch profile.name {
        case OpenClawTaskProfile.notificationSpeech.name:
            return ["style_hint", "channel_rule", "notification_example"]
        case OpenClawTaskProfile.simpleChat.name:
            return ["style_hint", "channel_rule", "memory_fact"]
        case OpenClawTaskProfile.deepPersona.name:
            return ["core_persona", "style_hint", "channel_rule", "memory_fact", "notification_example", "deep_persona"]
        default:
            return []
        }
    }

    static func memoryFilterDescription(profile: OpenClawTaskProfile, language: String) -> String {
        let kinds: [String]
        switch profile.name {
        case OpenClawTaskProfile.notificationSpeech.name:
            kinds = ["style_hint", "channel_rule", "notification_example"]
        case OpenClawTaskProfile.simpleChat.name:
            kinds = ["style_hint", "channel_rule", "memory_fact"]
        case OpenClawTaskProfile.deepPersona.name:
            kinds = ["core_persona", "style_hint", "channel_rule", "memory_fact", "notification_example", "deep_persona"]
        default:
            kinds = []
        }
        return "profile=\(profile.name), language=\(language), kind in [\(kinds.joined(separator: ", "))]"
    }

    private func createPayloadIndex(collection: String, fieldName: String, fieldSchema: String) async throws {
        let body: [String: Any] = [
            "field_name": fieldName,
            "field_schema": fieldSchema
        ]
        try await request(
            path: "/collections/\(collection)/index",
            method: "PUT",
            body: body,
            acceptedStatusCodes: Set(200..<300).union([409])
        )
    }

    private func scrollMemory(profile: String, language: String, kinds: [String]) async throws -> [QdrantPoint] {
        let filter: [String: Any] = [
            "must": [
                ["key": "profile", "match": ["value": profile]],
                ["key": "language", "match": ["value": language]],
                ["key": "kind", "match": ["any": kinds]]
            ]
        ]
        let body: [String: Any] = [
            "filter": filter,
            "limit": 48,
            "with_payload": true,
            "with_vector": false
        ]
        let data = try await request(
            path: "/collections/\(Self.memoryCollection)/points/scroll",
            method: "POST",
            body: body
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let points = result["points"] as? [[String: Any]] else {
            return []
        }
        return points.compactMap(QdrantPoint.init)
    }

    private func scrollNotificationCache(language: String, app: String?) async throws -> [QdrantPoint] {
        var must: [[String: Any]] = [
            ["key": "kind", "match": ["value": "notification_cache"]],
            ["key": "language", "match": ["value": language]]
        ]
        if let app, !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            must.append(["key": "app", "match": ["value": app]])
        }
        let body: [String: Any] = [
            "filter": ["must": must],
            "limit": 32,
            "with_payload": true,
            "with_vector": false
        ]
        let data = try await request(
            path: "/collections/\(Self.notificationCacheCollection)/points/scroll",
            method: "POST",
            body: body
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let points = result["points"] as? [[String: Any]] else {
            return []
        }
        return points.compactMap(QdrantPoint.init)
    }

    private func updateNotificationCacheLastUsed(pointID: String) async {
        guard !pointID.isEmpty else {
            return
        }
        let body: [String: Any] = [
            "payload": [
                "last_used_at": ISO8601DateFormatter().string(from: Date())
            ],
            "points": [pointID]
        ]
        _ = try? await request(
            path: "/collections/\(Self.notificationCacheCollection)/points/payload",
            method: "POST",
            body: body
        )
    }

    @discardableResult
    private func request(
        path: String,
        method: String,
        body: [String: Any],
        acceptedStatusCodes: Set<Int> = Set(200..<300)
    ) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 1.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              acceptedStatusCodes.contains(httpResponse.statusCode) else {
            throw OpenClawLocalControllerError.agentFailed("Qdrant request failed for \(path).")
        }
        return data
    }

    private struct QdrantPoint {
        let id: String
        let payload: [String: Any]

        init?(_ object: [String: Any]) {
            guard let payload = object["payload"] as? [String: Any] else {
                return nil
            }
            if let id = object["id"] as? String {
                self.id = id
            } else if let id = object["id"] as? NSNumber {
                self.id = id.stringValue
            } else {
                self.id = ""
            }
            self.payload = payload
        }

        var snippet: OpenClawRetrievedSnippet? {
            let text = string("text")
            guard !text.isEmpty else {
                return nil
            }
            let kind = string("kind")
            let profile = string("profile")
            guard !kind.isEmpty, !profile.isEmpty else {
                return nil
            }
            return OpenClawRetrievedSnippet(
                id: id,
                kind: kind,
                profile: profile,
                source: string("source", fallback: "qdrant"),
                language: string("language", fallback: "ru"),
                channel: optionalString("channel"),
                app: optionalString("app"),
                priority: int("priority"),
                tokenEstimate: max(1, int("token_estimate", fallback: estimatedTokenCount(text))),
                text: text,
                score: 0
            )
        }

        func string(_ key: String, fallback: String = "") -> String {
            optionalString(key) ?? fallback
        }

        func optionalString(_ key: String) -> String? {
            guard let value = payload[key] as? String else {
                return nil
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func int(_ key: String, fallback: Int = 0) -> Int {
            if let value = payload[key] as? Int {
                return value
            }
            if let value = payload[key] as? NSNumber {
                return value.intValue
            }
            if let value = payload[key] as? String,
               let intValue = Int(value) {
                return intValue
            }
            return fallback
        }
    }
}

private func relevanceScore(
    snippet: OpenClawRetrievedSnippet,
    query: OpenClawRetrievalQuery,
    queryTokens: Set<String>
) -> Double {
    let snippetText = [
        snippet.text,
        snippet.source,
        snippet.app,
        snippet.channel,
        snippet.kind
    ]
        .compactMap { $0 }
        .joined(separator: " ")
    let snippetTokens = lexicalTokens(snippetText)
    let overlap = queryTokens.intersection(snippetTokens)
    let denominator = max(1, min(queryTokens.count, 16))
    var score = min(0.55, Double(overlap.count) / Double(denominator))

    let normalizedSnippet = normalizedRetrievalText(snippetText)
    if let title = query.title, !title.isEmpty, normalizedSnippet.contains(normalizedRetrievalText(title)) {
        score += 0.18
    }
    if let body = query.body, !body.isEmpty {
        let normalizedBody = normalizedRetrievalText(body)
        if normalizedBody.count >= 8, normalizedSnippet.contains(normalizedBody) {
            score += 0.22
        }
    }
    if let queryApp = query.app,
       let snippetApp = snippet.app,
       !queryApp.isEmpty,
       normalizedRetrievalText(queryApp) == normalizedRetrievalText(snippetApp) {
        score += 0.16
    }
    if query.mode == .notificationSpeech, snippet.kind == "notification_example" {
        score += 0.08
    }
    if snippet.priority > 0 {
        score += min(0.12, Double(snippet.priority) * 0.02)
    }
    return min(1.0, score)
}

private func channelMatches(_ snippetChannel: String?, queryChannel: String?) -> Bool {
    guard let snippetChannel,
          let queryChannel,
          !snippetChannel.isEmpty,
          !queryChannel.isEmpty else {
        return true
    }
    let left = normalizedRetrievalText(snippetChannel)
    let right = normalizedRetrievalText(queryChannel)
    return left == right || left.contains(right) || right.contains(left)
}

private func lexicalTokens(_ text: String) -> Set<String> {
    let normalized = normalizedRetrievalText(text)
    let parts = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
    return Set(parts.filter { $0.count >= 2 })
}

private func jaccardScore(lhs: Set<String>, rhs: Set<String>) -> Double {
    guard !lhs.isEmpty, !rhs.isEmpty else {
        return 0
    }
    let intersection = lhs.intersection(rhs).count
    let union = lhs.union(rhs).count
    return Double(intersection) / Double(max(1, union))
}

private func normalizedRetrievalText(_ text: String) -> String {
    text
        .precomposedStringWithCanonicalMapping
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
        .lowercased()
        .replacingOccurrences(of: "ё", with: "е")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func cacheComparableText(app: String?, title: String?, body: String?) -> String {
    [
        app,
        title,
        body
    ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func estimatedTokenCount(_ text: String) -> Int {
    max(1, Int(ceil(Double(text.count) / 4.0)))
}

private let personaCompactFileName = "persona_compact.md"
private let defaultCorePersona = """
Gracula is a local Russian-speaking voice assistant with a short, vivid, natural voice. Speak like a living assistant, not a corporate helpdesk: direct, slightly dark-ironic, warm only when it helps, never syrupy.

Do not mention OpenClaw, prompts, RAG, databases, tools, files, implementation details, policies, or internal context. Do not output chain-of-thought. Preserve important names, numbers, channels, apps, and the user's meaning.
"""

private let defaultStyleCard = """
For notifications, produce one short phrase suitable for being spoken aloud in Russian. Keep the message compact, concrete, and understandable on first hearing. For simple local tasks, answer briefly and use /no_think when the model supports it.
"""

private let defaultCompactPersona = """
## corePersona
\(defaultCorePersona)

## styleCard
\(defaultStyleCard)
"""

private struct OpenClawLocalPromptSettings: Equatable {
    enum PersonaMode: String, CaseIterable {
        case personaCompact = "persona_compact"
        case deepPersona = "deep_persona"
    }

    enum ReasoningMode: String, CaseIterable {
        case off
        case on
    }

    var personaMode: PersonaMode = .deepPersona
    var reasoningMode: ReasoningMode = .on
    var notificationRuntimeContextWindow = 4096
    var notificationMaxOutputTokens = 128
    var notificationReserveTokens = 512
    var simpleRuntimeContextWindow = 8192
    var simpleMaxOutputTokens = 512
    var simpleReserveTokens = 1024
    var deepRuntimeContextWindow = 16384
    var deepMaxOutputTokens = 2048
    var deepReserveTokens = 4096
}

@MainActor
final class OpenClawLocalController: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Stopped"
    @Published private(set) var gatewayStatus = "not checked"
    @Published private(set) var streamBridgeStatus = "not checked"
    @Published private(set) var logLines: [String] = []
    @Published private(set) var chatMessages: [OpenClawChatMessage] = []
    @Published private(set) var chatStatusText = "Ready to chat."
    @Published private(set) var isSendingChat = false
    @Published private(set) var pendingTelegramReply: PendingTelegramReply?
    @Published private(set) var telegramUserStatusText = "Telegram user API disabled."
    @Published private(set) var telegramUserDialogs: [TelegramUserDialog] = []
    @Published private(set) var isStartingTelegramUserAPI = false
    @Published private(set) var settingsSnapshot: OpenClawSettingsSnapshot
    @Published private(set) var settingsStatusText = "Settings loaded."
    @Published private(set) var bootstrapStatusText = "Bootstrap not run."
    @Published private(set) var bootstrapDependencyItems: [DependencyReport.Item] = []

    let projectDirectory: URL
    let runtimeLayout: ProjectRuntimeLayout
    let configurationStore: AppConfigurationStore
    let bootstrapper: AppBootstrapper
    let configDirectory: URL
    let workspaceDirectory: URL
    let repositoryDirectory: URL

    private let nodeURL = resolveNodeExecutableURL()
    private let gatewayHost = "127.0.0.1"
    private let fallbackGatewayPort = "18789"
    private let streamBridgePort = "7071"
    private let agentTurnTimeoutSeconds: TimeInterval = 180
    private let directModelTimeoutSeconds: TimeInterval = 120
    private let directMemoryFileLimit = 2
    private let onlyFansPoster = WorkspaceOpeningClient()
    private let telegramCommandRouter: OpenClawVoiceCommandRouter
    private var chatSessionID = "gracula-local-chat"
    private var gatewayProcess: Process?
    private var streamBridgeProcess: Process?
    private var qdrantProcess: Process?
    private var healthTask: Task<Void, Never>?
    private var directModelPrewarmTask: Task<Void, Never>?
    private var consecutiveHealthFailures = 0
    private var startupTask: Task<Void, Never>?
    private var directPersonaContextCache: String?
    private var directCompactPersonaContextCache: String?
    private var telegramBusinessTask: Task<Void, Never>?
    private var telegramUserClient: TelegramUserTDLibClient?

    override init() {
        let runtimeLayout = ProjectRuntimeLayout.resolveDefault()
        let configurationStore = AppConfigurationStore(layout: runtimeLayout)
        let bootstrapper = AppBootstrapper(
            layout: runtimeLayout,
            store: configurationStore,
            verifier: DependencyVerifier(layout: runtimeLayout),
            installer: RuntimeDependencyInstaller(layout: runtimeLayout)
        )
        let telegramHandler = TelegramCommandHandler(
            service: TelegramMacAppAutomationService(),
            eventSink: { event in
                NSLog("%@", event.rawValue)
            }
        )
        self.projectDirectory = runtimeLayout.projectRootURL
        self.runtimeLayout = runtimeLayout
        self.configurationStore = configurationStore
        self.bootstrapper = bootstrapper
        self.configDirectory = runtimeLayout.runtimeDirectoryURL
        self.workspaceDirectory = runtimeLayout.workspaceDirectoryURL
        self.repositoryDirectory = runtimeLayout.openClawGatewayRootURL
        self.telegramCommandRouter = OpenClawVoiceCommandRouter(telegramHandler: telegramHandler)
        self.settingsSnapshot = Self.makeSettingsSnapshot(layout: runtimeLayout, store: configurationStore)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        if shouldResetCurrentSessionOnLaunch() {
            resetChat()
        }
    }

    var chatSessionLabel: String {
        let prefix = "gracula-local-chat-"
        if chatSessionID.hasPrefix(prefix) {
            let suffix = chatSessionID.dropFirst(prefix.count)
            return "gracula-local-chat • \(suffix.prefix(8))"
        }
        return chatSessionID
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        shutdownManagedProcessesForApplicationTermination()
    }

    func start() {
        guard !isRunning else {
            appendLog("OpenClaw is already running.")
            return
        }
        guard startupTask == nil else {
            appendLog("OpenClaw is already starting.")
            return
        }

        startupTask = Task { [weak self] in
            await self?.startWorkflow()
        }
    }

    private func startWorkflow() async {
        defer { startupTask = nil }

        do {
            let bootstrapResult = try bootstrapper.bootstrap()
            applyBootstrapResult(bootstrapResult)
            for diagnostic in bootstrapResult.diagnostics.messages {
                appendLog(diagnostic.message)
            }
            let configuration = bootstrapResult.configuration
            let environment = AppConfigurationEnvironmentBuilder.build(
                configuration: configuration,
                layout: runtimeLayout
            )
            settingsSnapshot = Self.makeSettingsSnapshot(layout: runtimeLayout, store: configurationStore)
            await ensureQdrantServer(environment: environment)
            startTelegramBusinessPolling(environment: environment)
            let primaryModelRef = currentPrimaryModelRef()
            if shouldUseDirectCompletion(for: primaryModelRef) {
                try await ensureDirectModelRuntimeReady(for: primaryModelRef)
                gatewayProcess = nil
                streamBridgeProcess = nil
                isRunning = true
                statusText = "Direct model ready"
                gatewayStatus = "direct mode"
                streamBridgeStatus = "disabled"
                appendLog("Direct model mode active; skipping OpenClaw gateway startup.")
                appendLog("Selected model uses direct completion: \(primaryModelRef)")
                scheduleDirectModelPrewarm(modelRef: primaryModelRef)
                return
            }

            try validateRuntime()

            let configuredGatewayPort = environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort
            if await attachToExistingGatewayIfHealthy(port: configuredGatewayPort) {
                appendLog("Attached to existing OpenClaw gateway before launching a new process.")
            } else {
                do {
                    gatewayProcess = try launchGatewayProcess(environment: environment)
                    isRunning = true
                    statusText = "Starting local OpenClaw..."
                    appendLog("Started OpenClaw gateway locally without Docker.")
                    appendLog("Gateway: http://\(gatewayHost):\(configuredGatewayPort)/")
                } catch {
                    switch await recoverGatewayLaunchConflict(
                        error: error,
                        environment: environment,
                        port: configuredGatewayPort
                    ) {
                    case .attached:
                        break
                    case .retryLaunch:
                        gatewayProcess = try launchGatewayProcess(environment: environment)
                        isRunning = true
                        statusText = "Starting local OpenClaw..."
                        appendLog("Restarted OpenClaw gateway locally after clearing a stale instance.")
                        appendLog("Gateway: http://\(gatewayHost):\(configuredGatewayPort)/")
                    case .unhandled:
                        throw error
                    }
                }
            }

            if isEnabled(environment["OPENCLAW_ENABLE_STREAM_BRIDGE"]) {
                do {
                    streamBridgeProcess = try launchProcess(
                        name: "stream-bridge",
                        arguments: [
                            repositoryDirectory.appendingPathComponent("dist/telegram-stream/docker-stream-bridge.js").path
                        ],
                        environment: environment,
                        updateRunningStateOnExit: false
                    )
                    appendLog("Stream bridge: http://\(gatewayHost):\(streamBridgePort)/health")
                } catch {
                    streamBridgeProcess = nil
                    streamBridgeStatus = "unavailable"
                    appendLog("Stream bridge unavailable: \(error.localizedDescription)")
                }
            } else {
                streamBridgeProcess = nil
                streamBridgeStatus = "disabled"
                appendLog("Stream bridge disabled. Set OPENCLAW_ENABLE_STREAM_BRIDGE=1 to start Telegram/OBS streaming support.")
            }

            scheduleHealthChecks()
        } catch {
            stop()
            statusText = "Start failed"
            appendLog("Start failed: \(error.localizedDescription)")
            appendChatMessage(.error(error.localizedDescription))
        }
    }

    private func launchGatewayProcess(environment: [String: String]) throws -> Process {
        try launchProcess(
            name: "gateway",
            arguments: [
                repositoryDirectory.appendingPathComponent("dist/index.js").path,
                "gateway",
                "run",
                "--allow-unconfigured",
                "--bind",
                environment["OPENCLAW_GATEWAY_BIND"] ?? "loopback",
                "--port",
                environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort
            ],
            environment: environment
        )
    }

    private func attachToExistingGatewayIfHealthy(port: String) async -> Bool {
        let existingGatewayURL = URL(string: "http://\(gatewayHost):\(port)/healthz")!
        let existingGatewayStatus = await checkHealth(url: existingGatewayURL)
        guard existingGatewayStatus == "healthy" else {
            return false
        }

        gatewayProcess = nil
        isRunning = true
        statusText = "Using existing OpenClaw gateway..."
        gatewayStatus = "healthy"
        appendLog("OpenClaw gateway is already running outside the app and passed health check; attaching to http://\(gatewayHost):\(port)/")
        return true
    }

    private func recoverGatewayLaunchConflict(
        error: Error,
        environment: [String: String],
        port: String
    ) async -> GatewayLaunchRecovery {
        let launchErrorMessage = error.localizedDescription
        let normalizedLaunchError = launchErrorMessage.lowercased()
        let gatewayAlreadyRunning = normalizedLaunchError.contains("already running")
            || normalizedLaunchError.contains("port \(port) is already in use")
            || normalizedLaunchError.contains("lock timeout")
            || normalizedLaunchError.contains("use a different port")

        guard gatewayAlreadyRunning else {
            return .unhandled
        }

        if await attachToExistingGatewayIfHealthy(port: port) {
            return .attached
        }

        appendLog("Gateway launch conflicted on port \(port); attempting to stop a stale OpenClaw gateway and retry once.")
        do {
            let stopOutput = try runCommand(
                executableURL: nodeURL,
                arguments: [
                    repositoryDirectory.appendingPathComponent("dist/index.js").path,
                    "gateway",
                    "stop",
                    "--port",
                    port,
                    "--force",
                    "--json"
                ],
                currentDirectoryURL: projectDirectory,
                environment: environment
            )
            let stopSummary = stopOutput.stderr.isEmpty ? stopOutput.stdout : stopOutput.stderr
            if !stopSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendLog(stopSummary, prefix: "gateway-stop")
            }
        } catch {
            appendLog("Automatic gateway stop failed: \(error.localizedDescription)")
        }

        for _ in 0..<5 {
            let status = await checkHealth(url: URL(string: "http://\(gatewayHost):\(port)/healthz")!)
            if status == "offline" {
                return .retryLaunch
            }
            if status == "healthy" {
                return .attached
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        gatewayProcess = nil
        isRunning = false
        gatewayStatus = "conflict"
        statusText = "Stopped"
        appendLog("Gateway port \(port) is still occupied after automatic recovery attempt.")
        return .unhandled
    }

    func stop() {
        directModelPrewarmTask?.cancel()
        directModelPrewarmTask = nil
        healthTask?.cancel()
        healthTask = nil
        telegramBusinessTask?.cancel()
        telegramBusinessTask = nil
        startupTask?.cancel()
        startupTask = nil
        isStartingTelegramUserAPI = false
        terminate(process: gatewayProcess, name: "gateway")
        terminate(process: streamBridgeProcess, name: "stream-bridge")
        terminate(process: qdrantProcess, name: "qdrant")
        gatewayProcess = nil
        streamBridgeProcess = nil
        qdrantProcess = nil
        isRunning = false
        statusText = "Stopped"
        gatewayStatus = "stopped"
        streamBridgeStatus = "stopped"
    }

    func startTelegramUserAPI() async {
        let environment = (try? openClawEnvironment()) ?? [:]
        await startTelegramUserAPI(environment: environment)
    }

    func submitTelegramUserCode(_ code: String) async {
        guard let telegramUserClient else {
            telegramUserStatusText = "Telegram user API is not started."
            return
        }
        let state = await telegramUserClient.submitCode(code)
        telegramUserStatusText = state.displayText
        if case .ready = state {
            await refreshTelegramUserDialogs()
        }
    }

    func submitTelegramUserPassword(_ password: String) async {
        guard let telegramUserClient else {
            telegramUserStatusText = "Telegram user API is not started."
            return
        }
        let state = await telegramUserClient.submitPassword(password)
        telegramUserStatusText = state.displayText
        if case .ready = state {
            await refreshTelegramUserDialogs()
        }
    }

    func refreshTelegramUserDialogs() async {
        guard let telegramUserClient else {
            telegramUserStatusText = "Telegram user API is not started."
            return
        }
        do {
            telegramUserDialogs = try await telegramUserClient.dialogs(limit: 50)
            telegramUserStatusText = "Telegram user API is authorized. Dialogs: \(telegramUserDialogs.count)."
        } catch {
            telegramUserStatusText = error.localizedDescription
        }
    }

    func openDashboard() {
        NSWorkspace.shared.open(URL(string: "http://\(gatewayHost):\(gatewayPort)/")!)
    }

    func refreshHealth() async {
        reloadSettings()
        gatewayStatus = await checkHealth(url: URL(string: "http://\(gatewayHost):\(gatewayPort)/healthz")!)
        updateHealthFailureCount(for: gatewayStatus)
        if streamBridgeProcess?.isRunning == true {
            streamBridgeStatus = await checkHealth(url: URL(string: "http://\(gatewayHost):\(streamBridgePort)/health")!)
        } else if streamBridgeStatus != "disabled" {
            streamBridgeStatus = streamBridgeProcess == nil ? "disabled" : "stopped"
        }
        statusText = isRunning ? "Running" : "Stopped"
    }

    private func updateHealthFailureCount(for status: String) {
        if status == "healthy" {
            consecutiveHealthFailures = 0
        } else {
            consecutiveHealthFailures = min(consecutiveHealthFailures + 1, 8)
        }
    }
    private func startTelegramBusinessPolling(environment: [String: String]) {
        telegramBusinessTask?.cancel()
        telegramBusinessTask = nil

        let settings = telegramBusinessSettings(environment: environment)
        guard settings.enabled else {
            appendLog("Telegram Business mode disabled.")
            return
        }
        guard !settings.botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLog("Telegram Business mode enabled, but bot token is missing.")
            return
        }
        guard OpenClawQdrantClient.make(environment: environment) != nil else {
            appendLog("Telegram Business mode requires Qdrant; polling not started.")
            return
        }

        let service = TelegramBusinessBotService(botToken: settings.botToken)
        telegramBusinessTask = Task { [weak self] in
            await self?.runTelegramBusinessPolling(
                service: service,
                settings: settings,
                environment: environment
            )
        }
        appendLog("Telegram Business polling started.")
    }

    private func startTelegramUserAPI(environment: [String: String]) async {
        let settings = telegramUserSettings(environment: environment)
        guard settings.enabled else {
            await closeTelegramUserClient()
            telegramUserDialogs = []
            telegramUserStatusText = TelegramUserAuthorizationState.disabled.displayText
            appendLog(telegramUserStatusText)
            return
        }

        guard !isStartingTelegramUserAPI else {
            appendLog("Telegram user API is already starting.")
            return
        }

        if let telegramUserClient {
            let state = await telegramUserClient.currentAuthorizationState()
            switch state {
            case .ready, .waitingForCode, .waitingForPassword, .waitingForPhoneNumber:
                telegramUserStatusText = state.displayText
                appendLog("Telegram user API already has an active session.")
                if case .ready = state {
                    await refreshTelegramUserDialogs()
                }
                return
            default:
                await closeTelegramUserClient()
            }
        }

        isStartingTelegramUserAPI = true
        telegramUserStatusText = "Starting Telegram user API..."
        defer { isStartingTelegramUserAPI = false }

        let client = TelegramUserTDLibClient(settings: settings)
        telegramUserClient = client
        let state = await client.start()
        telegramUserStatusText = state.displayText
        appendLog(telegramUserStatusText)
        if case .ready = state {
            await refreshTelegramUserDialogs()
        } else if case .failed = state {
            await closeTelegramUserClient()
        }
    }

    private func closeTelegramUserClient() async {
        guard let telegramUserClient else {
            return
        }
        await telegramUserClient.close()
        if self.telegramUserClient === telegramUserClient {
            self.telegramUserClient = nil
        }
    }

    private func telegramUserSettings(environment: [String: String]) -> TelegramUserSettings {
        var settings = TelegramUserSettings.make(environment: environment, configDirectory: configDirectory)
        let entries = settingsSnapshot.jsonEntries
        settings.enabled = boolConfig(
            "integrations.telegram.user.enabled",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_USER_ENABLED"],
            defaultValue: settings.enabled
        ) || environment["TELEGRAM_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mtproto"
        settings.apiId = intConfig(
            "integrations.telegram.user.apiId",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_API_ID", "TELEGRAM_API_ID"],
            defaultValue: settings.apiId,
            range: 1...Int.max
        )
        settings.apiHash = stringConfig(
            "integrations.telegram.user.apiHash",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_API_HASH", "TELEGRAM_API_HASH"]
        )
        settings.phoneNumber = stringConfig(
            "integrations.telegram.user.phone",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_PHONE", "TELEGRAM_PHONE"]
        )
        settings.tdjsonLibraryPath = stringConfig(
            "integrations.telegram.user.tdjsonLibraryPath",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TDLIB_JSON_LIBRARY"]
        )
        settings.databaseDirectory = stringConfig(
            "integrations.telegram.user.databaseDirectory",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_USER_DATABASE_DIR"]
        )
        settings.filesDirectory = stringConfig(
            "integrations.telegram.user.filesDirectory",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_USER_FILES_DIR"]
        )
        settings.encryptionKey = stringConfig(
            "integrations.telegram.user.encryptionKey",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_USER_ENCRYPTION_KEY"]
        )
        let allowlist = stringConfig(
            "integrations.telegram.user.chatAllowlist",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_USER_CHAT_ALLOWLIST"]
        )
        settings.chatAllowlist = allowlist
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return settings
    }

    private func runTelegramBusinessPolling(
        service: TelegramBusinessBotService,
        settings: TelegramBusinessSettings,
        environment: [String: String]
    ) async {
        var offset: Int?
        let pollDelay = max(0.5, settings.pollIntervalSeconds)
        while !Task.isCancelled {
            do {
                let messages = try await service.getUpdates(offset: offset)
                if let maxUpdateId = messages.map(\.updateId).max() {
                    offset = maxUpdateId + 1
                }

                for message in messages {
                    guard !Task.isCancelled else { return }
                    guard settings.businessConnectionId.isEmpty
                        || settings.businessConnectionId == message.businessConnectionId else {
                        continue
                    }
                    await handleTelegramBusinessMessage(
                        message,
                        service: service,
                        settings: settings,
                        environment: environment
                    )
                }
            } catch {
                appendLog("Telegram Business polling error: \(error.localizedDescription)")
                try? await Task.sleep(for: .seconds(max(2.0, pollDelay)))
            }
            try? await Task.sleep(for: .seconds(pollDelay))
        }
    }

    private func handleTelegramBusinessMessage(
        _ message: TelegramBusinessIncomingMessage,
        service: TelegramBusinessBotService,
        settings: TelegramBusinessSettings,
        environment: [String: String]
    ) async {
        let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        let qdrant = OpenClawQdrantClient.make(environment: environment)
        let alreadyStored = await qdrant?.businessMessageExists(message) ?? false
        await qdrant?.storeBusinessMessage(message)
        appendLog("Telegram Business message stored: \(message.chat.displayName) #\(message.messageId)")

        if alreadyStored {
            appendLog("Telegram Business message already handled; skipping duplicate auto-reply.")
        }

        if settings.autoReplyEnabled, !alreadyStored {
            do {
                let reply = try await telegramBusinessReply(
                    to: message,
                    qdrant: qdrant,
                    environment: environment
                )
                try await service.sendMessage(
                    businessConnectionId: message.businessConnectionId,
                    chatId: message.chat.id,
                    text: reply
                )
                await qdrant?.storeBusinessReply(
                    businessConnectionId: message.businessConnectionId,
                    chat: message.chat,
                    text: reply
                )
                appendLog("Telegram Business reply sent to \(message.chat.displayName).")
            } catch {
                appendLog("Telegram Business auto-reply failed: \(error.localizedDescription)")
            }
        }

        if settings.markReadEnabled {
            do {
                try await service.readBusinessMessage(
                    businessConnectionId: message.businessConnectionId,
                    chatId: message.chat.id,
                    messageId: message.messageId
                )
            } catch {
                appendLog("Telegram Business mark-read failed: \(error.localizedDescription)")
            }
        }
    }

    private func telegramBusinessReply(
        to message: TelegramBusinessIncomingMessage,
        qdrant: OpenClawQdrantClient?,
        environment: [String: String]
    ) async throws -> String {
        let history = await qdrant?.searchBusinessMessages(
            query: message.text,
            businessConnectionId: message.businessConnectionId,
            chatId: message.chat.id,
            limit: 8
        ) ?? []
        let historyText = history
            .map { "- \($0.text)" }
            .joined(separator: "\n")
        let sender = message.senderName ?? message.chat.displayName
        let prompt = """
        You are Gracula replying through Telegram Business from the user's personal/business account.

        Rules:
        - Reply in the same language as the incoming message unless the user clearly asks otherwise.
        - Be concise, natural, and useful.
        - Do not mention OpenClaw, Qdrant, prompts, automation, tools, or internal storage.
        - Do not invent facts. Ask one short clarifying question if needed.
        - Output only the exact Telegram message text.

        Chat: \(message.chat.displayName)
        Sender: \(sender)

        Relevant previous messages from Qdrant:
        \(historyText.isEmpty ? "No previous relevant messages." : historyText)

        Incoming message:
        \(message.text)
        """
        let profile = chatPromptProfile()
        let modelRef = currentPrimaryModelRef()
        let result = try await runDirectModelChat(
            modelRef: modelRef,
            prompt: prompt,
            environment: environment,
            maxTokens: min(profile.maxOutputTokens, 768)
        )
        let trimmed = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("Telegram Business model returned an empty reply.")
        }
        return String(trimmed.prefix(4096))
    }

    private func telegramBusinessSettings(environment: [String: String]) -> TelegramBusinessSettings {
        let entries = settingsSnapshot.jsonEntries
        let enabled = boolConfig(
            "integrations.telegram.business.enabled",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_BUSINESS_ENABLED", "TELEGRAM_BUSINESS_ENABLED"],
            defaultValue: false
        )
        let botToken = stringConfig(
            "integrations.telegram.business.botToken",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_BOT_TOKEN", "TELEGRAM_BOT_TOKEN"]
        )
        let businessConnectionId = stringConfig(
            "integrations.telegram.business.businessConnectionId",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_BUSINESS_CONNECTION_ID", "TELEGRAM_BUSINESS_CONNECTION_ID"]
        )
        let pollInterval = doubleConfig(
            "integrations.telegram.business.pollIntervalSeconds",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_BUSINESS_POLL_INTERVAL_SECONDS"],
            defaultValue: 2,
            range: 0.5...60
        )
        let autoReply = boolConfig(
            "integrations.telegram.business.autoReplyEnabled",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_BUSINESS_AUTO_REPLY"],
            defaultValue: true
        )
        let markRead = boolConfig(
            "integrations.telegram.business.markReadEnabled",
            entries: entries,
            environment: environment,
            environmentKeys: ["GRACULA_TELEGRAM_BUSINESS_MARK_READ"],
            defaultValue: true
        )
        return TelegramBusinessSettings(
            enabled: enabled,
            botToken: botToken,
            businessConnectionId: businessConnectionId,
            pollIntervalSeconds: pollInterval,
            autoReplyEnabled: autoReply,
            markReadEnabled: markRead
        )
    }

    private func stringConfig(
        _ jsonKey: String,
        entries: [OpenClawEditableSetting],
        environment: [String: String],
        environmentKeys: [String]
    ) -> String {
        if let value = entries.first(where: { $0.key == jsonKey })?.value.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return environmentKeys
            .lazy
            .compactMap { environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func boolConfig(
        _ jsonKey: String,
        entries: [OpenClawEditableSetting],
        environment: [String: String],
        environmentKeys: [String],
        defaultValue: Bool
    ) -> Bool {
        if let value = entries.first(where: { $0.key == jsonKey })?.value {
            return isEnabled(value)
        }
        if let value = environmentKeys.compactMap({ environment[$0] }).first {
            return isEnabled(value)
        }
        return defaultValue
    }

    private func doubleConfig(
        _ jsonKey: String,
        entries: [OpenClawEditableSetting],
        environment: [String: String],
        environmentKeys: [String],
        defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        let rawValue = entries.first(where: { $0.key == jsonKey })?.value
            ?? environmentKeys.compactMap { environment[$0] }.first
        guard let rawValue,
              let value = Double(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func intConfig(
        _ jsonKey: String,
        entries: [OpenClawEditableSetting],
        environment: [String: String],
        environmentKeys: [String],
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        let rawValue = entries.first(where: { $0.key == jsonKey })?.value
            ?? environmentKeys.compactMap { environment[$0] }.first
        guard let rawValue,
              let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }
    func reportError(_ message: String) {
        appendChatMessage(.error(message))
    }

    func prepareForLocalAutomation() async -> Bool {
        do {
            let bootstrapResult = try bootstrapper.bootstrap()
            applyBootstrapResult(bootstrapResult)
            for diagnostic in bootstrapResult.diagnostics.messages {
                appendLog(diagnostic.message)
            }
            settingsSnapshot = Self.makeSettingsSnapshot(layout: runtimeLayout, store: configurationStore)
            return true
        } catch {
            let message = "OpenClaw is not ready for local automation: \(error.localizedDescription)"
            appendLog(message)
            appendChatMessage(.error(message))
            return false
        }
    }

    func reloadSettings() {
        settingsSnapshot = Self.makeSettingsSnapshot(layout: runtimeLayout, store: configurationStore)
        directPersonaContextCache = nil
        directCompactPersonaContextCache = nil
        settingsStatusText = "Settings reloaded."
    }

    private func applyBootstrapResult(_ result: AppBootstrapper.Result) {
        bootstrapDependencyItems = result.dependencyReport.items
        switch result.diagnostics.status {
        case .idle:
            bootstrapStatusText = "Bootstrap idle."
        case .bootstrapping:
            bootstrapStatusText = "Bootstrap in progress."
        case .ready:
            bootstrapStatusText = "Bootstrap ready."
        case .degraded:
            bootstrapStatusText = "Bootstrap degraded."
        case .failed:
            bootstrapStatusText = "Bootstrap failed."
        }
    }

    func testSelectedModel(
        environmentEntries: [OpenClawEditableSetting],
        jsonEntries: [OpenClawEditableSetting],
        workspaceFiles: [OpenClawWorkspaceFile]
    ) async {
        do {
            settingsStatusText = "Testing selected model..."
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("gracula-model-test-\(UUID().uuidString)", isDirectory: true)
            let tempLayout = ProjectRuntimeLayout(projectRootURL: tempDirectory)
            let tempStore = AppConfigurationStore(layout: tempLayout)
            let tempBridge = OpenClawCanonicalSettingsBridge(layout: tempLayout, store: tempStore)
            try prepareTestDirectories(
                configDirectory: tempLayout.runtimeDirectoryURL,
                workspaceDirectory: tempLayout.workspaceDirectoryURL
            )
            try tempBridge.apply(
                environmentEntries: environmentEntries,
                jsonEntries: jsonEntries,
                workspaceFiles: workspaceFiles
            )
            try copyAuthStoreIntoTestSandbox(
                sandboxDirectory: tempDirectory
            )

            let environment = AppConfigurationEnvironmentBuilder.build(
                configuration: try tempStore.loadOrCreate(),
                layout: tempLayout
            )
            let primaryModelRef = currentPrimaryModelRef(in: jsonEntries)
            let reply: String
            let metrics: DirectModelMetrics?
            if shouldUseDirectModelSmokeTest(for: primaryModelRef) {
                appendLog("Selected model uses a tool-free probe; running direct completion smoke test.")
                let result = try await runDirectModelSmokeTest(
                    modelRef: primaryModelRef,
                    environment: environment,
                    configurationEntries: jsonEntries
                )
                reply = result.text
                metrics = result.metrics
            } else {
                let testSessionID = "gracula-model-test-\(UUID().uuidString)"
                let response = try await runAgentTurn(
                    message: "Reply with exactly: model test ok",
                    sessionID: testSessionID,
                    environment: environment
                )
                if let status = response.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                   status == "error" {
                    throw OpenClawLocalControllerError.agentFailed(
                        response.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? "Selected model returned an error status."
                    )
                }
                let agentReply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !agentReply.isEmpty else {
                    throw OpenClawLocalControllerError.agentFailed("Selected model returned an empty reply.")
                }
                if agentReply.hasPrefix("LLM error:") {
                    throw OpenClawLocalControllerError.agentFailed(agentReply)
                }
                reply = agentReply
                metrics = nil
            }
            let metricSummary = metrics?.statusSummary
            settingsStatusText = metricSummary.map { "Model test passed. \($0)" } ?? "Model test passed."
            let transcriptSummary = metricSummary.map { "Model test passed: \(reply) [\($0)]" } ?? "Model test passed: \(reply)"
            appendChatMessage(.system(transcriptSummary))
            appendLog("Selected model test passed with reply: \(reply)")
            if let metrics {
                appendLog("Selected model performance: \(metrics.logSummary)")
            }
        } catch {
            let message = "Model test failed: \(error.localizedDescription)"
            settingsStatusText = message
            appendChatMessage(.error(message))
            appendLog(message)
        }
    }

    private func copyAuthStoreIntoTestSandbox(sandboxDirectory: URL) throws {
        let fileManager = FileManager.default
        let sourceAuthStore = configDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("auth-profiles.json")
        guard fileManager.fileExists(atPath: sourceAuthStore.path) else {
            return
        }

        let destinationAuthStore = sandboxDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("auth-profiles.json")
        try fileManager.createDirectory(
            at: destinationAuthStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationAuthStore.path) {
            try fileManager.removeItem(at: destinationAuthStore)
        }
        try fileManager.copyItem(at: sourceAuthStore, to: destinationAuthStore)
        appendLog("Copied auth-profiles.json into the model test sandbox.")
    }

    private func scheduleDirectModelPrewarm(modelRef: String) {
        directModelPrewarmTask?.cancel()
        directModelPrewarmTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.prewarmDirectModelIfNeeded(modelRef: modelRef)
        }
    }

    private func prewarmDirectModelIfNeeded(modelRef: String) async {
        let trimmedRef = modelRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRef.isEmpty, shouldUseDirectCompletion(for: trimmedRef) else {
            return
        }
        guard !isSendingChat else {
            appendLog("Direct model prewarm skipped because a chat turn is already active.")
            return
        }

        appendLog("Prewarming selected direct model on launch: \(trimmedRef)")
        let startedAt = PerformanceLog.checkpoint()
        do {
            let result = try await runDirectModelSmokeTest(
                modelRef: trimmedRef,
                environment: try openClawEnvironment()
            )
            let metricSummary = result.metrics?.statusSummary ?? "no metrics"
            appendLog("[latency] Direct model prewarm completed in \(PerformanceLog.elapsedDescription(since: startedAt)); model=\(trimmedRef); \(metricSummary)")
        } catch is CancellationError {
            appendLog("Direct model prewarm cancelled.")
        } catch {
            appendLog("Direct model prewarm failed: \(error.localizedDescription)")
        }
    }

    func applySettings(
        environmentEntries: [OpenClawEditableSetting],
        jsonEntries: [OpenClawEditableSetting],
        workspaceFiles: [OpenClawWorkspaceFile]
    ) {
        do {
            let wasRunning = isRunning
            let hadTelegramUserClient = telegramUserClient != nil
            let bridge = OpenClawCanonicalSettingsBridge(layout: runtimeLayout, store: configurationStore)
            try bridge.apply(
                environmentEntries: environmentEntries,
                jsonEntries: jsonEntries,
                workspaceFiles: workspaceFiles
            )
            reloadSettings()
            if wasRunning {
                stop()
                start()
            }
            if hadTelegramUserClient {
                Task { [weak self] in
                    await self?.closeTelegramUserClient()
                    await self?.startTelegramUserAPI()
                }
            }
            settingsStatusText =
                if wasRunning || hadTelegramUserClient {
                    "Settings applied and runtime restarted."
                } else {
                    "Settings applied."
                }
            appendLog(settingsStatusText)
        } catch {
            settingsStatusText = "Settings apply failed: \(error.localizedDescription)"
            appendLog(settingsStatusText)
        }
    }

    func resetChat() {
        chatMessages.removeAll(keepingCapacity: true)
        chatStatusText = "Ready to chat."
        chatSessionID = "gracula-local-chat-\(UUID().uuidString)"
        appendChatMessage(.system("Started a new local OpenClaw conversation."))
    }

    @discardableResult
    func sendLocalNotificationSpeech(_ text: String) async -> String? {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return nil
        }

        do {
            isSendingChat = true
            chatStatusText = "Preparing notification speech..."
            try prepareDirectories()
            let primaryModelRef = currentPrimaryModelRef()
            let profile = notificationSpeechProfile()
            let retrievalQuery = OpenClawRetrievalQuery.notificationSpeech(from: message)
            var promptMessage = message
            if let cacheResult = await notificationCacheResult(query: retrievalQuery) {
                appendLog(
                    String(
                        format: "Notification cache hit id=%@ action=%@ app=%@ title=%@ score=%.3f.",
                        cacheResult.id,
                        String(describing: cacheResult.action),
                        cacheResult.app,
                        cacheResult.title,
                        cacheResult.score
                    )
                )
                switch cacheResult.action {
                case .reuseSpokenText:
                    chatStatusText = "Notification speech reused from cache."
                    isSendingChat = false
                    return cacheResult.spokenText
                case .reuseSkip:
                    chatStatusText = "Notification skipped from cache."
                    isSendingChat = false
                    return cacheResult.spokenText
                case .useAsExample:
                    promptMessage += "\n\nSimilar previous spoken text:\n\(cacheResult.spokenText)"
                }
            }
            let prompt = await layeredPrompt(
                userMessage: promptMessage,
                profile: profile,
                modelRef: primaryModelRef,
                retrievalQuery: retrievalQuery
            )
            appendPromptDiagnostics(prompt.breakdown)
            let result = try await runDirectModelChat(
                modelRef: primaryModelRef,
                prompt: prompt.text,
                maxTokens: profile.maxOutputTokens
            )
            let reply = result.text
            guard !reply.isEmpty else {
                throw OpenClawLocalControllerError.agentFailed("Selected model returned an empty notification reply.")
            }
            await storeNotificationCache(inputPrompt: message, spokenText: reply)
            appendLog("OpenClaw notification speech reply received.")
            chatStatusText = "Notification speech ready."
            isSendingChat = false
            return reply
        } catch {
            chatStatusText = "OpenClaw unavailable"
            appendLog("Notification speech failed: \(error.localizedDescription)")
            isSendingChat = false
            return nil
        }
    }

    @discardableResult
    func sendChatMessage(_ text: String) async -> String? {
        let turnStartedAt = PerformanceLog.checkpoint()
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return nil
        }
        directModelPrewarmTask?.cancel()
        directModelPrewarmTask = nil

        do {
            let primaryModelRef = currentPrimaryModelRef()
            if !shouldUseDirectCompletion(for: primaryModelRef),
               shouldResetChatSessionBeforeSending(message) {
                appendLog("Resetting stale chat session before send.")
                resetChat()
            }
            isSendingChat = true
            chatStatusText = "Sending to OpenClaw..."
            appendChatMessage(.user(message))
            appendLog("[latency] Chat turn started; inputCharacters=\(message.count)")

            let telegramResult = await telegramCommandRouter.route(text: message)
            if applyTelegramCommandResult(telegramResult) {
                isSendingChat = false
                return chatMessages.last?.text
            }

            if isExplicitOnlyFansPublishRequest(message) {
                let reply = try await publishOnlyFansPostFromChatCommand(message)
                appendChatMessage(.assistant(reply))
                appendLog("[latency] Assistant reply appended to UI after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
                chatStatusText = "OnlyFans post published."
                isSendingChat = false
                return reply
            }
            if shouldUseDirectCompletion(for: primaryModelRef) {
                appendLog("Selected model uses a tool-free chat path; running direct completion.")
                appendLog("[latency] Direct model request starting; model=\(primaryModelRef)")
                let assistantMessageID = appendChatMessage(.assistant("…"))
                chatStatusText = "Waiting for local model..."
                let profile = chatPromptProfile()
                appendLog("Selected model uses \(profile.name) path; running direct completion.")
                try prepareDirectories()
                let prompt = await layeredPrompt(
                    userMessage: message,
                    profile: profile,
                    modelRef: primaryModelRef,
                    retrievalQuery: retrievalQuery(for: profile, message: message)
                )
                appendPromptDiagnostics(prompt.breakdown)
                let requestedMaxTokens = profile.maxOutputTokens
                let result = try await runDirectModelChat(
                    modelRef: primaryModelRef,
                    prompt: prompt.text,
                    maxTokens: requestedMaxTokens,
                    assistantMessageID: assistantMessageID
                )
                var reply = result.text
                var metrics = result.metrics
                if looksLikeDegenerateDirectModelReply(reply) {
                    appendLog("Direct model produced a degenerate reply; retrying once with stricter decoding.")
                    chatStatusText = "Retrying local model..."
                    let retryPrompt = await layeredPrompt(
                        userMessage: retryPromptForDegenerateReply(originalUserMessage: message),
                        profile: .simpleChat,
                        modelRef: primaryModelRef,
                        retrievalQuery: .simpleChat(message)
                    )
                    appendPromptDiagnostics(retryPrompt.breakdown)
                    let retryResult = try await runDirectModelChat(
                        modelRef: primaryModelRef,
                        prompt: retryPrompt.text,
                        maxTokens: min(requestedMaxTokens, 160),
                        sampling: .strictRetry
                    )
                    reply = retryResult.text
                    metrics = retryResult.metrics
                    if looksLikeDegenerateDirectModelReply(reply) {
                        removePendingAssistantPlaceholder()
                        let failure = "Local model produced a repetitive invalid reply."
                        appendChatMessage(.error(failure))
                        chatStatusText = "Chat failed."
                        appendLog("\(failure) lastReply=\"\(logSnippet(reply))\"")
                        isSendingChat = false
                        return nil
                    }
                }
                guard !reply.isEmpty else {
                    throw OpenClawLocalControllerError.agentFailed("Selected model returned an empty reply.")
                }
                updateChatMessage(id: assistantMessageID, text: reply)
                appendLog("[latency] Direct model answer returned after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
                appendLog("[latency] Assistant reply appended to UI after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
                chatStatusText = "Reply received."
                appendLog("Direct model reply received. characters=\(reply.count), text=\"\(logSnippet(reply))\"")
                if let metrics {
                    appendLog("Direct model performance: \(metrics.logSummary)")
                }
                isSendingChat = false
                return reply
            }

            appendLog("[latency] OpenClaw agent turn starting; session=\(chatSessionID)")
            let response = try await runAgentTurn(message: message, sessionID: chatSessionID)
            let reply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeStaleAssistantReply(reply) {
                appendLog("OpenClaw returned a stale reply; resetting chat and retrying once.")
                resetChat()
                appendChatMessage(.user(message))
                let retryResponse = try await runAgentTurn(message: message, sessionID: chatSessionID)
                let retryReply = retryResponse.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !retryReply.isEmpty, !looksLikeStaleAssistantReply(retryReply) else {
                    let failure = "OpenClaw returned a stale reply for this turn."
                    appendChatMessage(.error(failure))
                    chatStatusText = "Chat failed."
                    appendLog(failure)
                    isSendingChat = false
                    return nil
                }
                appendChatMessage(.assistant(retryReply))
                appendLog("[latency] Assistant retry reply appended to UI after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(retryReply.count)")
                chatStatusText = "Reply received."
                isSendingChat = false
                return retryReply
            }
            if reply.isEmpty {
                let failure = "OpenClaw returned an empty reply for this turn."
                appendChatMessage(.error(failure))
                chatStatusText = "Chat failed."
                appendLog(failure)
                isSendingChat = false
                return nil
            }
            appendLog("[latency] OpenClaw agent answer returned after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
            appendChatMessage(.assistant(reply))
            appendLog("[latency] Assistant reply appended to UI after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
            chatStatusText = "Reply received."
            isSendingChat = false
            return reply
        } catch {
            removePendingAssistantPlaceholder()
            appendChatMessage(.error(error.localizedDescription))
            chatStatusText = "Chat failed."
            appendLog("Chat failed: \(error.localizedDescription)")
            isSendingChat = false
            return nil
        }
    }

    @discardableResult
    func sendPendingTelegramReply() async -> String? {
        let result = await telegramCommandRouter.route(text: "отправь")
        guard applyTelegramCommandResult(result) else {
            return nil
        }
        return chatMessages.last?.text
    }

    @discardableResult
    func cancelPendingTelegramReply() async -> String? {
        let result = await telegramCommandRouter.route(text: "отмени")
        guard applyTelegramCommandResult(result) else {
            return nil
        }
        return chatMessages.last?.text
    }

    private func applyTelegramCommandResult(_ result: TelegramCommandResult) -> Bool {
        switch result {
        case .handled(let message, let pendingReply):
            pendingTelegramReply = pendingReply
            chatStatusText = pendingReply == nil ? "Telegram command handled." : "Telegram reply draft is waiting for confirmation."
            appendChatMessage(.assistant(message))
            return true
        case .notTelegramCommand:
            return false
        }
    }

    private func shouldResetChatSessionBeforeSending(_ message: String) -> Bool {
        guard let lastReply = latestAssistantReplyFromSession() else {
            return false
        }

        return isSessionReplyIncompatibleWithCurrentRuntime(lastReply)
    }

    private func shouldResetCurrentSessionOnLaunch() -> Bool {
        guard let lastReply = latestAssistantReplyFromSession() else {
            return false
        }

        return looksLikeStaleAssistantReply(lastReply)
    }

    private func looksLikeStaleAssistantReply(_ reply: String) -> Bool {
        isSessionReplyIncompatibleWithCurrentRuntime(reply)
    }

    private func isSessionReplyIncompatibleWithCurrentRuntime(_ reply: String) -> Bool {
        let normalizedReply = normalizedCommandText(reply)
        let staleReplyMarkers = [
            "Жду инструкций",
            "Waiting for your instructions",
            "Continue where I left off",
            "Continue where you left off",
            "fill SOUL.md",
            "SOUL.md",
            "What rules should I apply",
            "Can you clarify",
            "не могу честно проверить в интернете",
            "не могу проверить в интернете",
            "проверить билеты в интернете из этого запуска",
            "из этого запуска",
            "открои нормальныи интерактивныи run",
            "доступом к web/поиску",
            "веб-доступом",
            "with web access",
            "open another run",
            "normal interactive run",
        ]
        return staleReplyMarkers
            .map(normalizedCommandText)
            .contains(where: { normalizedReply.contains($0) })
    }

    private func looksLikeDegenerateDirectModelReply(_ reply: String) -> Bool {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else {
            return false
        }

        let scalars = Array(trimmed.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        guard !scalars.isEmpty else {
            return true
        }

        let meaningfulScalars = scalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
        if meaningfulScalars.isEmpty {
            return true
        }

        var frequency: [UnicodeScalar: Int] = [:]
        var longestRun = 1
        var currentRun = 1
        var previousScalar = scalars[0]

        for scalar in scalars {
            frequency[scalar, default: 0] += 1
        }

        for scalar in scalars.dropFirst() {
            if scalar == previousScalar {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 1
                previousScalar = scalar
            }
        }

        let dominantShare = Double(frequency.values.max() ?? 0) / Double(scalars.count)
        if longestRun >= 12 || dominantShare >= 0.55 {
            return true
        }

        let punctuationLikeScalars = scalars.filter {
            !CharacterSet.letters.contains($0) && !CharacterSet.decimalDigits.contains($0)
        }
        let punctuationShare = Double(punctuationLikeScalars.count) / Double(scalars.count)
        return punctuationShare >= 0.72
    }

    private func retryPromptForDegenerateReply(originalUserMessage: String) -> String {
        """
        \(originalUserMessage)

        Ответь обычным русским текстом. Не используй линии-разделители, длинные цепочки из тире, повторяющиеся символы или декоративную пунктуацию. Если запрос похож на скороговорку, цитату или фрагмент фразы, кратко объясни или отреагируй на него естественно.
        """
    }

    private func validateRuntime() throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: nodeURL.path) else {
            throw OpenClawLocalControllerError.missingRuntime("Node runtime not found. Install Node.js 22+ or set GRACULA_NODE_EXECUTABLE.")
        }
        try bootstrapOpenClawCheckoutIfNeeded()
        let distIndexURL = repositoryDirectory.appendingPathComponent("dist/index.js")
        if !fileManager.fileExists(atPath: distIndexURL.path) {
            appendLog("OpenClaw dist/index.js is missing; attempting to build the checkout at \(repositoryDirectory.path).")
            try buildOpenClawCheckout()
            if !fileManager.fileExists(atPath: distIndexURL.path) {
                throw OpenClawLocalControllerError.missingRuntime(
                    "OpenClaw dist/index.js not found after attempting a build. Install dependencies in \(repositoryDirectory.path) and run `pnpm build`, or point GRACULA_OPENCLAW_REPOSITORY_DIR at a built checkout."
                )
            }
        }
    }

    private func bootstrapOpenClawCheckoutIfNeeded() throws {
        let fileManager = FileManager.default
        let packageURL = repositoryDirectory.appendingPathComponent("package.json")
        if fileManager.fileExists(atPath: packageURL.path) {
            return
        }

        let parentDirectory = repositoryDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        appendLog("OpenClaw checkout not found at \(repositoryDirectory.path); cloning it now.")

        let cloneOutput = try runCommand(
            executableURL: URL(filePath: "/usr/bin/git"),
            arguments: [
                "clone",
                "--depth",
                "1",
                "https://github.com/openclaw/openclaw.git",
                repositoryDirectory.path
            ],
            currentDirectoryURL: parentDirectory,
            environment: (try? openClawEnvironment()) ?? [:]
        )

        if cloneOutput.exitCode != 0 {
            throw OpenClawLocalControllerError.missingRuntime(
                cloneOutput.stderr.isEmpty ? cloneOutput.stdout : cloneOutput.stderr
            )
        }

        if !cloneOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(cloneOutput.stdout, prefix: "git")
        }
        if !cloneOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(cloneOutput.stderr, prefix: "git")
        }
    }

    private func buildOpenClawCheckout() throws {
        let fileManager = FileManager.default
        let environment = try openClawEnvironment()
        guard let command = resolvePackageManagerCommand() else {
            throw OpenClawLocalControllerError.missingRuntime(
                "Could not find pnpm or corepack to build OpenClaw automatically."
            )
        }

        appendLog("Building OpenClaw checkout with \(command.displayName).")
        let installOutput = try runCommand(
            executableURL: command.executableURL,
            arguments: command.installArguments,
            currentDirectoryURL: repositoryDirectory,
            environment: environment
        )
        if installOutput.exitCode != 0 {
            throw OpenClawLocalControllerError.missingRuntime(
                installOutput.stderr.isEmpty ? installOutput.stdout : installOutput.stderr
            )
        }
        if !installOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(installOutput.stdout, prefix: command.displayName)
        }
        if !installOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(installOutput.stderr, prefix: command.displayName)
        }

        let buildOutput = try runCommand(
            executableURL: command.executableURL,
            arguments: command.buildArguments,
            currentDirectoryURL: repositoryDirectory,
            environment: environment
        )
        if buildOutput.exitCode != 0 {
            throw OpenClawLocalControllerError.missingRuntime(
                buildOutput.stderr.isEmpty ? buildOutput.stdout : buildOutput.stderr
            )
        }
        if !buildOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(buildOutput.stdout, prefix: command.displayName)
        }
        if !buildOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(buildOutput.stderr, prefix: command.displayName)
        }

        guard fileManager.fileExists(atPath: repositoryDirectory.appendingPathComponent("dist/index.js").path) else {
            throw OpenClawLocalControllerError.missingRuntime(
                "OpenClaw build finished but dist/index.js is still missing."
            )
        }
    }

    private func prepareDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try seedCompactPersonaIfNeeded()
        try validateProjectWorkspaceConfiguration()
        try fileManager.createDirectory(
            at: configDirectory.appendingPathComponent("canvas", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: configDirectory.appendingPathComponent("cron", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func seedCompactPersonaIfNeeded() throws {
        let url = workspaceDirectory.appendingPathComponent(personaCompactFileName)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try defaultCompactPersona.write(to: url, atomically: true, encoding: .utf8)
        appendLog("Created compact persona at \(url.path).")
    }

    private func validateProjectWorkspaceConfiguration() throws {
        let missingFiles = requiredProjectWorkspaceFiles.filter { fileName in
            let url = workspaceDirectory.appendingPathComponent(fileName)
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                return true
            }
            return contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard missingFiles.isEmpty else {
            throw OpenClawLocalControllerError.missingRuntime(
                "Project OpenClaw workspace is incomplete. Missing required personality files in \(workspaceDirectory.path): \(missingFiles.joined(separator: ", "))."
            )
        }
    }

    private func openClawEnvironment(
        configDirectory: URL? = nil,
        workspaceDirectory: URL? = nil,
        configPath: URL? = nil,
        stateDirectory: URL? = nil
    ) throws -> [String: String] {
        var configuration = try configurationStore.loadOrCreate()
        if let configDirectory {
            configuration.runtimePaths.runtimeRootPath = configDirectory.path
        }
        if let workspaceDirectory {
            configuration.runtimePaths.workspacePath = workspaceDirectory.path
        }
        if let stateDirectory {
            configuration.runtimePaths.logsPath = stateDirectory.path
        }
        if let configPath {
            configuration.runtimePaths.canonicalPlistPath = configPath.path
        }
        let environment = AppConfigurationEnvironmentBuilder.build(
            configuration: configuration,
            layout: runtimeLayout
        )
        return environment
    }

    private static func makeSettingsSnapshot(
        layout: ProjectRuntimeLayout,
        store: AppConfigurationStore
    ) -> OpenClawSettingsSnapshot {
        let bridge = OpenClawCanonicalSettingsBridge(layout: layout, store: store)
        return bridge.snapshot()
    }

    private var gatewayPort: String {
        String((try? configurationStore.loadOrCreate().llm.gatewayPort) ?? Int(fallbackGatewayPort) ?? 18789)
    }

    private func configuredGatewayPort(from environment: [String: String]) -> String {
        if let port = normalizedPort(environment["OPENCLAW_GATEWAY_PORT"]) {
            return port
        }
        return String((try? configurationStore.loadOrCreate().llm.gatewayPort) ?? Int(fallbackGatewayPort) ?? 18789)
    }

    private func normalizedPort(_ rawPort: String?) -> String? {
        guard let rawPort else {
            return nil
        }
        let trimmed = rawPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), (1...65535).contains(port) else {
            return nil
        }
        return String(port)
    }

    private func isEnabled(_ rawValue: String?) -> Bool {
        guard let rawValue else {
            return false
        }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private func launchProcess(
        name: String,
        arguments: [String],
        environment: [String: String],
        updateRunningStateOnExit: Bool = true
    ) throws -> Process {
        try launchExecutableProcess(
            name: name,
            executableURL: nodeURL,
            arguments: arguments,
            environment: environment,
            updateRunningStateOnExit: updateRunningStateOnExit
        )
    }

    private func launchExecutableProcess(
        name: String,
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        updateRunningStateOnExit: Bool = true
    ) throws -> Process {
        try launchObservedProcess(
            name: name,
            executableURL: executableURL,
            currentDirectoryURL: projectDirectory,
            arguments: arguments,
            environment: environment,
            updateRunningStateOnExit: updateRunningStateOnExit
        )
    }

    private func launchObservedProcess(
        name: String,
        executableURL: URL,
        currentDirectoryURL: URL,
        arguments: [String],
        environment: [String: String],
        updateRunningStateOnExit: Bool = true
    ) throws -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            guard !Self.shouldSuppressObservedProcessLog(text, processName: name) else {
                return
            }
            Task { @MainActor in
                self?.handleProcessOutput(text, prefix: name)
            }
        }

        process.terminationHandler = { [weak self, weak process] finishedProcess in
            Task { @MainActor in
                self?.appendLog("\(name) exited with code \(finishedProcess.terminationStatus).")
                if updateRunningStateOnExit && process === self?.gatewayProcess {
                    let healthURL = URL(string: "http://\(self?.gatewayHost ?? "127.0.0.1"):\(self?.gatewayPort ?? "18789")/healthz")!
                    let status = await self?.checkHealth(url: healthURL) ?? "offline"
                    if status == "healthy" {
                        self?.gatewayProcess = nil
                        self?.isRunning = true
                        self?.gatewayStatus = "healthy"
                        self?.statusText = "Using existing OpenClaw gateway..."
                        self?.appendLog("Gateway process handed off to an existing healthy gateway.")
                    } else {
                        self?.isRunning = false
                        self?.gatewayStatus = status
                        self?.statusText = "Stopped"
                    }
                } else if process === self?.streamBridgeProcess {
                    self?.streamBridgeStatus = "stopped"
                    if self?.gatewayProcess?.isRunning == true {
                        self?.statusText = "Gateway running, stream bridge stopped"
                    }
                }
            }
        }

        try process.run()
        appendLog("Launched \(name) pid=\(process.processIdentifier).")
        return process
    }

    private func terminate(process: Process?, name: String) {
        guard let process, process.isRunning else {
            return
        }
        appendLog("Stopping \(name) pid=\(process.processIdentifier).")
        process.terminate()
    }

    private func terminateAndWait(process: Process?, name: String, timeoutSeconds: TimeInterval = 2.0) {
        guard let process, process.isRunning else { return }
        appendLog("Stopping \(name) pid=\(process.processIdentifier).")
        process.terminate()
        waitForProcessExit(process, timeoutSeconds: timeoutSeconds)
        guard process.isRunning else { return }
        appendLog("Force killing \(name) pid=\(process.processIdentifier).")
        kill(process.processIdentifier, SIGKILL)
        waitForProcessExit(process, timeoutSeconds: 1.0)
    }

    private func waitForProcessExit(_ process: Process, timeoutSeconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func shutdownManagedProcessesForApplicationTermination() {
        healthTask?.cancel()
        healthTask = nil
        telegramBusinessTask?.cancel()
        telegramBusinessTask = nil
        startupTask?.cancel()
        startupTask = nil
        terminateAndWait(process: streamBridgeProcess, name: "stream-bridge", timeoutSeconds: 1.0)
        streamBridgeProcess = nil
        terminateAndWait(process: gatewayProcess, name: "gateway", timeoutSeconds: 1.0)
        gatewayProcess = nil
        terminateAndWait(process: qdrantProcess, name: "qdrant", timeoutSeconds: 1.0)
        qdrantProcess = nil
    }

    private func handleProcessOutput(_ text: String, prefix name: String) {
        appendLog(text, prefix: name)
    }

    private func scheduleHealthChecks() {
        healthTask?.cancel()
        appendLog("Gateway health check scheduled once after startup.")
        healthTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                await self?.refreshHealth()
            }
        }
    }

    private func waitForGatewayReady(timeoutSeconds: Int = 15) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let status = await checkHealth(url: URL(string: "http://\(gatewayHost):\(gatewayPort)/healthz")!)
            gatewayStatus = status
            updateHealthFailureCount(for: status)
            if status == "healthy" {
                if streamBridgeStatus == "not checked" {
                    streamBridgeStatus = "unknown"
                }
                return
            }
            try await Task.sleep(for: .milliseconds(400))
        }
        throw OpenClawLocalControllerError.gatewayUnavailable("OpenClaw gateway did not become healthy at http://\(gatewayHost):\(gatewayPort)/healthz")
    }

    private func runAgentTurn(
        message: String,
        sessionID: String,
        environment: [String: String]? = nil
    ) async throws -> OpenClawAgentTurnResponse {
        let result = try await runProcess(
            arguments: [
                repositoryDirectory.appendingPathComponent("dist/index.js").path,
                "agent",
                "--local",
                "--session-id",
                sessionID,
                "--message",
                message,
                "--json"
            ],
            environment: environment ?? (try openClawEnvironment()),
            timeoutSeconds: agentTurnTimeoutSeconds
        )

        guard result.exitCode == 0 else {
            throw OpenClawLocalControllerError.agentFailed(
                result.stderr.isEmpty ? "OpenClaw agent exited with code \(result.exitCode)." : result.stderr
            )
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stdout.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("OpenClaw agent returned no output.")
        }

        if let decoded = try? decodeAgentResponse(from: stdout) {
            return decoded
        }

        if let recovered = try recoverJSONObject(from: stdout),
           let decoded = try? decodeAgentResponse(from: recovered) {
            return decoded
        }

        throw OpenClawLocalControllerError.agentFailed("Could not parse OpenClaw JSON response.")
    }

    private func runDirectModelSmokeTest(
        modelRef: String,
        environment: [String: String],
        configurationEntries: [OpenClawEditableSetting]? = nil
    ) async throws -> DirectModelChatResult {
        return try await runDirectModelChat(
            modelRef: modelRef,
            prompt: "Reply with exactly: model test ok",
            environment: environment,
            maxTokens: 32,
            configurationEntries: configurationEntries
        )
    }

    private func runDirectModelChat(
        modelRef: String,
        prompt: String,
        environment: [String: String]? = nil,
        maxTokens: Int = 256,
        assistantMessageID: UUID? = nil,
        sampling: DirectModelSamplingOptions? = nil,
        configurationEntries: [OpenClawEditableSetting]? = nil
    ) async throws -> DirectModelChatResult {
        let startedAt = PerformanceLog.checkpoint()
        let trimmedRef = modelRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRef.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("Selected model is not set.")
        }

        let provider = trimmedRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard provider.count == 2 else {
            throw OpenClawLocalControllerError.agentFailed(
                "Selected model ref must use provider/model format."
            )
        }

        let providerName = String(provider[0]).lowercased()
        let providerModelID = String(provider[1])
        let resolvedConfigurationEntries = configurationEntries ?? settingsSnapshot.jsonEntries
        let openAISettings = openAIChatSettings(in: resolvedConfigurationEntries)
        let effectiveMaxTokens = directModelMaxTokens(
            for: trimmedRef,
            requestedMaxTokens: maxTokens,
            openAISettings: openAISettings
        )
        let effectiveSampling = sampling ?? DirectModelSamplingOptions.standard(
            for: effectiveMaxTokens,
            temperature: openAISettings.temperature,
            topP: openAISettings.topP
        )
        if providerName == "openai" {
            return try await runDirectOpenAIChat(
                modelID: providerModelID,
                prompt: prompt,
                maxTokens: effectiveMaxTokens,
                environment: environment,
                sampling: effectiveSampling,
                configurationEntries: resolvedConfigurationEntries
            )
        }
        throw OpenClawLocalControllerError.agentFailed(
            "Unsupported model provider: \(providerName). GraculaExample supports only `openai/...` with OpenAI API key."
        )
    }

    private func currentPrimaryModelRef(in jsonEntries: [OpenClawEditableSetting]) -> String {
        if let value = jsonEntries.first(where: { $0.key == "agents.defaults.model.primary" })?.value
            ?? jsonEntries.first(where: { $0.key == "agents.defaults.model" })?.value {
            let migrated = OpenClawLLMConfiguration.migratedModelRef(value)
            let normalized = migrated.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.hasPrefix("openai/") {
                return migrated
            }
            return OpenClawLLMConfiguration.defaultModelRef
        }
        return OpenClawLLMConfiguration.defaultModelRef
    }

    private func shouldUseDirectModelSmokeTest(for modelRef: String) -> Bool {
        shouldUseDirectCompletion(for: modelRef)
    }

    private func shouldUseDirectCompletion(for modelRef: String) -> Bool {
        let normalizedModelRef = OpenClawLLMConfiguration.migratedModelRef(modelRef)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedModelRef.isEmpty else {
            return false
        }

        let directModeEnabled = (try? configurationStore.loadOrCreate().llm.directLocalModeEnabled) ?? true
        guard directModeEnabled else {
            return false
        }

        return OpenClawLLMConfiguration.provider(forModelRef: normalizedModelRef) != nil
    }

    private func currentPrimaryModelRef() -> String {
        currentPrimaryModelRef(in: settingsSnapshot.jsonEntries)
    }

    private func localPromptSettings(in jsonEntries: [OpenClawEditableSetting]) -> OpenClawLocalPromptSettings {
        var settings = OpenClawLocalPromptSettings()
        if let rawMode = jsonValue("agents.defaults.localPrompt.mode", in: jsonEntries),
           let mode = OpenClawLocalPromptSettings.PersonaMode(rawValue: rawMode) {
            settings.personaMode = mode
        }
        if let rawReasoning = jsonValue("agents.defaults.localPrompt.reasoning", in: jsonEntries),
           let reasoning = OpenClawLocalPromptSettings.ReasoningMode(rawValue: rawReasoning) {
            settings.reasoningMode = reasoning
        }
        settings.notificationRuntimeContextWindow = intValue(
            "agents.defaults.localPrompt.notificationSpeech.runtimeContextWindow",
            in: jsonEntries,
            default: settings.notificationRuntimeContextWindow,
            range: 1024...4096
        )
        settings.notificationMaxOutputTokens = intValue(
            "agents.defaults.localPrompt.notificationSpeech.maxOutputTokens",
            in: jsonEntries,
            default: settings.notificationMaxOutputTokens,
            range: 16...128
        )
        settings.notificationReserveTokens = intValue(
            "agents.defaults.localPrompt.notificationSpeech.reserveTokens",
            in: jsonEntries,
            default: settings.notificationReserveTokens,
            range: 128...1024
        )
        settings.simpleRuntimeContextWindow = intValue(
            "agents.defaults.localPrompt.simpleChat.runtimeContextWindow",
            in: jsonEntries,
            default: settings.simpleRuntimeContextWindow,
            range: 2048...32768
        )
        settings.simpleMaxOutputTokens = intValue(
            "agents.defaults.localPrompt.simpleChat.maxOutputTokens",
            in: jsonEntries,
            default: settings.simpleMaxOutputTokens,
            range: 64...2048
        )
        settings.simpleReserveTokens = intValue(
            "agents.defaults.localPrompt.simpleChat.reserveTokens",
            in: jsonEntries,
            default: settings.simpleReserveTokens,
            range: 256...4096
        )
        settings.deepRuntimeContextWindow = intValue(
            "agents.defaults.localPrompt.deepPersona.runtimeContextWindow",
            in: jsonEntries,
            default: settings.deepRuntimeContextWindow,
            range: 8192...65536
        )
        settings.deepMaxOutputTokens = intValue(
            "agents.defaults.localPrompt.deepPersona.maxOutputTokens",
            in: jsonEntries,
            default: settings.deepMaxOutputTokens,
            range: 256...8192
        )
        settings.deepReserveTokens = intValue(
            "agents.defaults.localPrompt.deepPersona.reserveTokens",
            in: jsonEntries,
            default: settings.deepReserveTokens,
            range: 1024...8192
        )
        return settings
    }

    private func localPromptSettings() -> OpenClawLocalPromptSettings {
        localPromptSettings(in: settingsSnapshot.jsonEntries)
    }

    private func openAIChatSettings(in entries: [OpenClawEditableSetting]) -> OpenAIDirectChatSettings {
        OpenAIDirectChatSettings(
            temperature: doubleValue(
                "agents.defaults.localPrompt.openAIChat.temperature",
                in: entries,
                default: OpenAIDirectChatSettings.default.temperature,
                range: 0...2
            ),
            topP: doubleValue(
                "agents.defaults.localPrompt.openAIChat.topP",
                in: entries,
                default: OpenAIDirectChatSettings.default.topP,
                range: 0...1
            ),
            maxTokens: intValue(
                "agents.defaults.localPrompt.openAIChat.maxTokens",
                in: entries,
                default: OpenAIDirectChatSettings.default.maxTokens,
                range: 32...8192
            )
        )
    }

    private func openAIProviderBaseURL(in entries: [OpenClawEditableSetting]) -> URL? {
        let configuredBaseURL = jsonValue("models.providers.openai.baseUrl", in: entries)
        let fallbackBaseURL = OpenClawLLMConfiguration.provider(named: "openai")?.baseURL
        let baseURLString = configuredBaseURL?.isEmpty == false ? configuredBaseURL : fallbackBaseURL
        guard let baseURLString, !baseURLString.isEmpty else {
            return nil
        }
        return URL(string: baseURLString)
    }

    private func jsonValue(_ key: String, in entries: [OpenClawEditableSetting]) -> String? {
        entries.first(where: { $0.key == key })?.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func doubleValue(
        _ key: String,
        in entries: [OpenClawEditableSetting],
        default defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard let rawValue = jsonValue(key, in: entries), let value = Double(rawValue) else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func intValue(
        _ key: String,
        in entries: [OpenClawEditableSetting],
        default defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard let rawValue = jsonValue(key, in: entries), let value = Int(rawValue) else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func notificationSpeechProfile() -> OpenClawTaskProfile {
        let settings = localPromptSettings()
        return OpenClawTaskProfile.notificationSpeech.applyingRuntimeOverrides(
            runtimeContextWindow: settings.notificationRuntimeContextWindow,
            maxOutputTokens: settings.notificationMaxOutputTokens,
            reserveTokens: settings.notificationReserveTokens,
            disableThinking: settings.reasoningMode == .off
        )
    }

    private func chatPromptProfile() -> OpenClawTaskProfile {
        let settings = localPromptSettings()
        let baseProfile: OpenClawTaskProfile = settings.personaMode == .deepPersona
            ? .deepPersona
            : .simpleChat
        if settings.personaMode == .deepPersona {
            return baseProfile.applyingRuntimeOverrides(
                runtimeContextWindow: settings.deepRuntimeContextWindow,
                maxOutputTokens: settings.deepMaxOutputTokens,
                reserveTokens: settings.deepReserveTokens,
                disableThinking: settings.reasoningMode == .off
            )
        }
        return baseProfile.applyingRuntimeOverrides(
            runtimeContextWindow: settings.simpleRuntimeContextWindow,
            maxOutputTokens: settings.simpleMaxOutputTokens,
            reserveTokens: settings.simpleReserveTokens,
            disableThinking: settings.reasoningMode == .off
        )
    }

    private func retrievalQuery(for profile: OpenClawTaskProfile, message: String) -> OpenClawRetrievalQuery {
        profile.name == OpenClawTaskProfile.deepPersona.name
            ? .deepPersona(message)
            : .simpleChat(message)
    }

    private func directChatPrompt() -> String {
        let transcript = chatMessages
            .suffix(12)
            .filter { $0.role != .error }
            .map { message in
                "\(message.role.rawValue): \(message.text)"
            }
            .joined(separator: "\n")

        return """
        Continue the conversation below and answer the latest user message directly.
        Keep the answer concise unless the user asks for detail.

        Conversation:
        \(transcript)
        """
    }

    private func layeredPrompt(
        userMessage: String,
        profile: OpenClawTaskProfile,
        modelRef: String,
        retrievalQuery: OpenClawRetrievalQuery
    ) async -> OpenClawLayeredPrompt {
        let providerParts = modelRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        let providerName = providerParts.first.map(String.init) ?? ""
        let modelName = providerParts.count == 2 ? String(providerParts[1]) : modelRef
        let corePersona = profile.includeCorePersona
            ? limitedTokens(personaSection(named: "corePersona") ?? defaultCorePersona, maxTokens: profile.corePersonaTokens)
            : ""
        let styleCard = profile.includeStyleCard
            ? limitedTokens(personaSection(named: "styleCard") ?? defaultStyleCard, maxTokens: profile.styleCardTokens)
            : ""
        let memorySummary = profile.includeMemorySummary
            ? limitedTokens(readWorkspaceText(named: "memory_summary.md") ?? "", maxTokens: profile.maxMemoryTokens)
            : ""
        let history = profile.includeHistory
            ? limitedHistory(maxMessages: profile.maxHistoryMessages)
            : ""
        let fullPersona = profile.includeFullPersonaFiles
            ? limitedTokens(fullPersonaText(), maxTokens: profile.maxRetrievedTokens)
            : ""
        let fullMemory = profile.includeFullMemory
            ? limitedTokens(readWorkspaceText(named: "MEMORY.md") ?? "", maxTokens: profile.maxMemoryTokens)
            : ""
        let retrieval = profile.includeRag
            ? await selectiveMemoryContext(query: retrievalQuery, profile: profile)
            : .empty(query: retrievalQuery, profile: profile)
        var retrievedMemory = retrieval.text

        var baseSections = [
            OpenClawPromptSection(name: "corePersona", text: corePersona),
            OpenClawPromptSection(name: "styleCard", text: styleCard),
            OpenClawPromptSection(name: "memorySummary", text: memorySummary),
            OpenClawPromptSection(name: "history", text: history),
            OpenClawPromptSection(name: "fullPersona", text: fullPersona),
            OpenClawPromptSection(name: "fullMemory", text: fullMemory),
            OpenClawPromptSection(name: "retrievedMemory", text: retrievedMemory),
        ].filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let suffix = ""
        let budget = max(256, profile.runtimeContextWindow - profile.reserveTokens - profile.maxOutputTokens)
        var dropped: [String] = []
        var shrinkingApplied = false
        var userMessageForPrompt = profile.name == OpenClawTaskProfile.notificationSpeech.name
            ? notificationUserMessage(userMessage, includeFallback: true, includeExtraMetadata: true)
            : userMessage
        if profile.name == OpenClawTaskProfile.notificationSpeech.name {
            userMessageForPrompt = limitedTokens(userMessageForPrompt, maxTokens: 2500)
        }

        var sections = baseSections + [OpenClawPromptSection(name: "user", text: userMessageForPrompt + suffix)]
        var text = sections
            .map { "## \($0.name)\n\($0.text)" }
            .joined(separator: "\n\n")

        if estimatedTokens(text) > budget {
            shrinkingApplied = true
            dropped.append("Qdrant snippets")
            baseSections.removeAll { $0.name == "retrievedMemory" }
            retrievedMemory = ""
            sections = baseSections + [OpenClawPromptSection(name: "user", text: userMessageForPrompt + suffix)]
            text = sections.map { "## \($0.name)\n\($0.text)" }.joined(separator: "\n\n")
        }

        if profile.name == OpenClawTaskProfile.notificationSpeech.name, estimatedTokens(text) > budget {
            shrinkingApplied = true
            dropped.append("fallback spoken text")
            userMessageForPrompt = notificationUserMessage(userMessage, includeFallback: false, includeExtraMetadata: true)
            userMessageForPrompt = limitedTokens(userMessageForPrompt, maxTokens: 2500)
            sections = baseSections + [OpenClawPromptSection(name: "user", text: userMessageForPrompt + suffix)]
            text = sections.map { "## \($0.name)\n\($0.text)" }.joined(separator: "\n\n")
        }

        if profile.name == OpenClawTaskProfile.notificationSpeech.name, estimatedTokens(text) > budget {
            shrinkingApplied = true
            dropped.append("extra notification metadata")
            userMessageForPrompt = notificationUserMessage(userMessage, includeFallback: false, includeExtraMetadata: false)
            userMessageForPrompt = limitedTokens(userMessageForPrompt, maxTokens: 2500)
            sections = baseSections + [OpenClawPromptSection(name: "user", text: userMessageForPrompt + suffix)]
            text = sections.map { "## \($0.name)\n\($0.text)" }.joined(separator: "\n\n")
        }

        if estimatedTokens(text) > budget {
            for sectionName in ["history", "workspaceFiles", "tools", "skills", "fullMemory", "fullPersona"] {
                guard estimatedTokens(text) > budget else {
                    break
                }
                if baseSections.contains(where: { $0.name == sectionName }) {
                    shrinkingApplied = true
                    dropped.append(sectionName)
                    baseSections.removeAll { $0.name == sectionName }
                    sections = baseSections + [OpenClawPromptSection(name: "user", text: userMessageForPrompt + suffix)]
                    text = sections.map { "## \($0.name)\n\($0.text)" }.joined(separator: "\n\n")
                }
            }
        }

        if profile.name == OpenClawTaskProfile.notificationSpeech.name, estimatedTokens(text) > budget {
            shrinkingApplied = true
            userMessageForPrompt = minimalNotificationUserMessage(userMessage)
            sections = baseSections + [OpenClawPromptSection(name: "user", text: userMessageForPrompt + suffix)]
            text = sections.map { "## \($0.name)\n\($0.text)" }.joined(separator: "\n\n")
        }

        let totalTokens = estimatedTokens(text)
        let breakdown = OpenClawPromptBreakdown(
            taskProfile: profile.name,
            modelName: modelName,
            providerName: providerName,
            qdrantQuery: limitedTokens(retrievalQuery.text.replacingOccurrences(of: "\n", with: " "), maxTokens: 80),
            qdrantFilters: retrieval.filters,
            retrievedSnippetIDs: retrieval.snippets.map(\.id),
            retrievedSnippetSources: retrieval.snippets.map(\.source),
            retrievedSnippetScores: retrieval.snippets.map(\.score),
            retrievedTokenCount: tokenCount(retrievedMemory),
            systemTokens: tokenCount(corePersona + "\n" + styleCard),
            userTokens: tokenCount(userMessageForPrompt + suffix),
            historyTokens: tokenCount(sections.first(where: { $0.name == "history" })?.text ?? ""),
            workspaceTokens: 0,
            toolsSkillsTokens: 0,
            memoryTokens: tokenCount([memorySummary, fullMemory].filter { !$0.isEmpty }.joined(separator: "\n")),
            ragTokens: tokenCount(retrievedMemory),
            totalTokens: totalTokens,
            runtimeContextWindow: profile.runtimeContextWindow,
            modelContextWindow: modelContextWindow(for: modelRef) ?? profile.runtimeContextWindow,
            reserveTokens: profile.reserveTokens,
            maxOutputTokens: profile.maxOutputTokens,
            shrinkingApplied: shrinkingApplied,
            dropped: dropped,
            sections: sections.map { section in
                OpenClawPromptBreakdown.Section(
                    name: section.name,
                    estimatedTokens: estimatedTokens(section.text),
                    characters: section.text.count
                )
            }
        )
        return OpenClawLayeredPrompt(text: text, breakdown: breakdown)
    }

    private func selectiveMemoryContext(
        query: OpenClawRetrievalQuery,
        profile: OpenClawTaskProfile
    ) async -> OpenClawSelectiveMemoryResult {
        guard let qdrant = qdrantClient() else {
            return .empty(query: query, profile: profile)
        }

        await qdrant.ensurePayloadIndexes()
        do {
            let snippets = try await qdrant.retrieve(query: query, profile: profile)
            guard !snippets.isEmpty else {
                appendLog("Qdrant retrieval for \(profile.name): no relevant snippets above score threshold.")
                return .empty(query: query, profile: profile)
            }

            for snippet in snippets {
                appendLog(
                    String(
                        format: "Qdrant snippet id=%@ source=%@ kind=%@ profile=%@ score=%.3f token_estimate=%d",
                        snippet.id,
                        snippet.source,
                        snippet.kind,
                        snippet.profile,
                        snippet.score,
                        snippet.tokenEstimate
                    )
                )
            }

            var remainingTokens = profile.maxRetrievedTokens
            let context = snippets.compactMap { snippet -> String? in
                guard remainingTokens > 0 else {
                    return nil
                }
                let snippetTokenBudget = min(remainingTokens, max(1, snippet.tokenEstimate))
                let clippedText = limitedTokens(snippet.text, maxTokens: snippetTokenBudget)
                let clippedTokens = estimatedTokens(clippedText)
                remainingTokens -= clippedTokens
                return """
                [source=\(snippet.source), kind=\(snippet.kind), score=\(String(format: "%.3f", snippet.score))]
                \(clippedText)
                """
            }
                .joined(separator: "\n\n")
            return OpenClawSelectiveMemoryResult(
                text: limitedTokens(context, maxTokens: profile.maxRetrievedTokens),
                snippets: snippets,
                query: query,
                filters: OpenClawQdrantClient.memoryFilterDescription(profile: profile, language: query.language)
            )
        } catch {
            appendLog("Qdrant retrieval for \(profile.name) skipped: \(error.localizedDescription)")
            return .empty(query: query, profile: profile)
        }
    }

    private func qdrantClient() -> OpenClawQdrantClient? {
        let environment = (try? openClawEnvironment()) ?? [:]
        return OpenClawQdrantClient.make(environment: environment)
    }

    private func ensureQdrantServer(environment: [String: String]) async {
        guard OpenClawQdrantClient.make(environment: environment) != nil else {
            appendLog("Qdrant disabled by configuration.")
            return
        }

        let baseURLString = environment["GRACULA_QDRANT_URL"]
            ?? environment["OPENCLAW_QDRANT_URL"]
            ?? environment["QDRANT_URL"]
            ?? "http://127.0.0.1:6333"
        guard let baseURL = URL(string: baseURLString) else {
            appendLog("Qdrant URL is invalid: \(baseURLString)")
            return
        }

        if await qdrantIsReady(baseURL: baseURL) {
            appendLog("Qdrant already running at \(baseURL.absoluteString).")
            return
        }
        if qdrantProcess?.isRunning == true {
            appendLog("Waiting for embedded Qdrant at \(baseURL.absoluteString).")
            await waitForQdrantReady(baseURL: baseURL)
            return
        }

        guard let qdrantURL = qdrantExecutableURL(environment: environment) else {
            appendLog("Qdrant binary not found. Put qdrant at .openclaw/bin/qdrant or set GRACULA_QDRANT_BIN.")
            return
        }

        do {
            let storageDirectory = qdrantStorageDirectory(environment: environment)
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            var qdrantEnvironment = environment
            qdrantEnvironment["QDRANT__SERVICE__HTTP_PORT"] = normalizedPort(baseURL.port.map(String.init)) ?? "6333"
            qdrantEnvironment["QDRANT__SERVICE__GRPC_PORT"] = qdrantEnvironment["QDRANT__SERVICE__GRPC_PORT"] ?? "6334"
            qdrantEnvironment["QDRANT__STORAGE__STORAGE_PATH"] = storageDirectory.path

            qdrantProcess = try launchExecutableProcess(
                name: "qdrant",
                executableURL: qdrantURL,
                arguments: [],
                environment: qdrantEnvironment,
                updateRunningStateOnExit: false
            )
            appendLog("Embedded Qdrant: \(baseURL.absoluteString), storage: \(storageDirectory.path)")
            await waitForQdrantReady(baseURL: baseURL)
        } catch {
            qdrantProcess = nil
            appendLog("Embedded Qdrant unavailable: \(error.localizedDescription)")
        }
    }

    private func waitForQdrantReady(baseURL: URL, timeoutSeconds: Int = 20) async {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if await qdrantIsReady(baseURL: baseURL) {
                appendLog("Qdrant is ready at \(baseURL.absoluteString).")
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        appendLog("Qdrant did not become ready within \(timeoutSeconds)s.")
    }

    private func qdrantIsReady(baseURL: URL) async -> Bool {
        let url = baseURL.appendingPathComponent("readyz")
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.6
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func qdrantExecutableURL(environment: [String: String]) -> URL? {
        let explicitCandidates = [environment["GRACULA_QDRANT_BIN"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(URL.init(fileURLWithPath:))

        let bundledCandidates = [
            Bundle.main.url(forResource: "qdrant", withExtension: nil),
            runtimeLayout.qdrantBinaryURL
        ].compactMap { $0 }

        return (explicitCandidates + bundledCandidates).first { url in
            FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    private func qdrantStorageDirectory(environment: [String: String]) -> URL {
        let rawPath = [environment["GRACULA_QDRANT_STORAGE_DIR"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let rawPath {
            return URL(fileURLWithPath: rawPath)
        }
        return runtimeLayout.qdrantStorageDirectoryURL
    }

    private func storeNotificationCache(inputPrompt: String, spokenText: String) async {
        guard let qdrant = qdrantClient() else {
            return
        }
        await qdrant.storeNotificationCache(
            inputPrompt: inputPrompt,
            spokenText: spokenText,
            decision: "speak"
        )
    }

    private func notificationCacheResult(query: OpenClawRetrievalQuery) async -> OpenClawNotificationCacheResult? {
        guard let qdrant = qdrantClient() else {
            return nil
        }
        await qdrant.ensurePayloadIndexes()
        do {
            let result = try await qdrant.notificationCacheResult(query: query)
            if result == nil {
                appendLog("Notification cache lookup: no similar cached notification above threshold.")
            }
            return result
        } catch {
            appendLog("Notification cache lookup skipped: \(error.localizedDescription)")
            return nil
        }
    }

    private func appendPromptDiagnostics(_ breakdown: OpenClawPromptBreakdown) {
        let sectionSummary = breakdown.sections
            .map { "\($0.name)=\($0.estimatedTokens)t/\($0.characters)c" }
            .joined(separator: ", ")
        appendLog(
            """
            Prompt diagnostics: profile=\(breakdown.taskProfile), model=\(breakdown.modelName), provider=\(breakdown.providerName), qdrantQuery=\(breakdown.qdrantQuery), filters=\(breakdown.qdrantFilters), retrievedIDs=\(breakdown.retrievedSnippetIDs), retrievedSources=\(breakdown.retrievedSnippetSources), retrievedScores=\(breakdown.retrievedSnippetScores), retrievedTokens=\(breakdown.retrievedTokenCount), system=\(breakdown.systemTokens)t, user=\(breakdown.userTokens)t, history=\(breakdown.historyTokens)t, workspace=\(breakdown.workspaceTokens)t, toolsSkills=\(breakdown.toolsSkillsTokens)t, memory=\(breakdown.memoryTokens)t, rag=\(breakdown.ragTokens)t, total=\(breakdown.totalTokens)t, runtimeWindow=\(breakdown.runtimeContextWindow)t, modelWindow=\(breakdown.modelContextWindow)t, maxOutput=\(breakdown.maxOutputTokens)t, reserve=\(breakdown.reserveTokens)t, shrinking=\(breakdown.shrinkingApplied), dropped=\(breakdown.dropped), sections=[\(sectionSummary)].
            """
        )
    }

    private func personaSection(named name: String) -> String? {
        guard let compactPersona = readWorkspaceText(named: personaCompactFileName) else {
            return nil
        }
        let marker = "## \(name)"
        guard let start = compactPersona.range(of: marker) else {
            return name == "corePersona"
                ? compactPersona.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
        }
        let sectionStart = start.upperBound
        let rest = compactPersona[sectionStart...]
        let nextSection = rest.range(of: "\n## ")
        let section = nextSection.map { rest[..<$0.lowerBound] } ?? rest[...]
        return String(section).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fullPersonaText() -> String {
        [
            "AGENTS.md",
            "SOUL.md",
            "IDENTITY.md",
            "HEARTBEAT.md",
            "USER.md",
            "TOOLS.md"
        ]
            .compactMap { fileName -> String? in
                guard let contents = readWorkspaceText(named: fileName) else {
                    return nil
                }
                return "### \(fileName)\n\(contents)"
            }
            .joined(separator: "\n\n")
    }

    private func readWorkspaceText(named fileName: String) -> String? {
        let url = workspaceDirectory.appendingPathComponent(fileName)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func runDirectOpenAIChat(
        modelID: String,
        prompt: String,
        maxTokens: Int,
        environment: [String: String]?,
        sampling: DirectModelSamplingOptions,
        configurationEntries: [OpenClawEditableSetting]
    ) async throws -> DirectModelChatResult {
        let resolvedEnvironment = environment ?? (try? openClawEnvironment()) ?? [:]
        guard let baseURL = openAIProviderBaseURL(in: configurationEntries) else {
            throw OpenClawLocalControllerError.agentFailed("OpenAI provider is not configured.")
        }
        let apiKey = openAIAPIKey(from: resolvedEnvironment)
        guard !apiKey.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("OpenAI API key is not configured.")
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_completion_tokens": maxTokens,
            "temperature": sampling.temperature,
            "top_p": sampling.topP,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = directModelTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenClawLocalControllerError.agentFailed("OpenAI returned a non-HTTP response.")
        }
        let responseText = String(decoding: data, as: UTF8.self)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenClawLocalControllerError.agentFailed(
                responseText.isEmpty ? "OpenAI HTTP \(httpResponse.statusCode)." : "OpenAI HTTP \(httpResponse.statusCode): \(responseText)"
            )
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenClawLocalControllerError.agentFailed("OpenAI returned an invalid chat completion response.")
        }

        let reply = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("OpenAI returned an empty reply.")
        }

        let usage = object["usage"] as? [String: Any]
        let metrics = DirectModelMetrics(
            providerLabel: "openai",
            promptTokens: usage?["prompt_tokens"] as? Int ?? (usage?["prompt_tokens"] as? NSNumber)?.intValue,
            promptTokensPerSecond: nil,
            generationTokens: usage?["completion_tokens"] as? Int ?? (usage?["completion_tokens"] as? NSNumber)?.intValue,
            generationTokensPerSecond: nil,
            peakMemoryGB: nil
        )
        return DirectModelChatResult(text: reply, metrics: metrics)
    }

    private func limitedHistory(maxMessages: Int) -> String {
        chatMessages
            .suffix(maxMessages)
            .filter { $0.role != .error }
            .map { "\($0.role.rawValue): \($0.text)" }
            .joined(separator: "\n")
    }

    private func notificationUserMessage(
        _ rawMessage: String,
        includeFallback: Bool,
        includeExtraMetadata: Bool
    ) -> String {
        let query = OpenClawRetrievalQuery.notificationSpeech(from: rawMessage)
        let subtitle = OpenClawRetrievalQuery.labeledValue("Subtitle", in: rawMessage)
        let fallback = notificationFallbackText(in: rawMessage)
        var lines = [
            "Task: produce one short Russian phrase suitable for speech. Preserve names, numbers, apps, channels, and message meaning. Do not mention prompts, RAG, databases, tools, or implementation details.",
            "App: \(query.app ?? "Unknown")",
            "Title: \(query.title ?? "Notification")"
        ]
        if includeExtraMetadata {
            if let subtitle, !subtitle.isEmpty {
                lines.append("Subtitle: \(subtitle)")
            }
            if let channel = query.channel, !channel.isEmpty {
                lines.append("Channel: \(channel)")
            }
        }
        lines.append("Body: \(query.body ?? query.text)")
        if includeFallback, let fallback, !fallback.isEmpty {
            lines.append("Fallback spoken text: \(fallback)")
        }
        if includeFallback,
           let example = rawMessage.components(separatedBy: "Similar previous spoken text:").last,
           rawMessage.contains("Similar previous spoken text:") {
            let trimmed = example.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append("Similar previous spoken text: \(limitedTokens(trimmed, maxTokens: 96))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func minimalNotificationUserMessage(_ rawMessage: String) -> String {
        let query = OpenClawRetrievalQuery.notificationSpeech(from: rawMessage)
        return [
            "Task: produce one short Russian phrase suitable for speech. Preserve names, numbers, apps, channels, and meaning.",
            "App: \(query.app ?? "Unknown")",
            "Title: \(query.title ?? "Notification")",
            "Body: \(limitedTokens(query.body ?? query.text, maxTokens: 2200))"
        ].joined(separator: "\n")
    }

    private func notificationFallbackText(in rawMessage: String) -> String? {
        guard rawMessage.contains("Fallback spoken text:") else {
            return nil
        }
        let fallback = rawMessage.components(separatedBy: "Fallback spoken text:")
            .last?
            .components(separatedBy: "Similar previous spoken text:")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback?.isEmpty == false ? fallback : nil
    }

    private func modelContextWindow(for modelRef: String) -> Int? {
        guard let provider = OpenClawLLMConfiguration.provider(forModelRef: modelRef),
              let data = provider.modelsJSON.data(using: .utf8),
              let models = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        let modelName = modelRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).dropFirst().first.map(String.init) ?? modelRef
        let model = models.first { object in
            (object["id"] as? String) == modelName || (object["name"] as? String) == modelName
        }
        return (model?["contextTokens"] as? Int)
            ?? (model?["contextWindow"] as? Int)
            ?? (model?["contextTokens"] as? NSNumber)?.intValue
            ?? (model?["contextWindow"] as? NSNumber)?.intValue
    }

    private func limitedTokens(_ text: String, maxTokens: Int) -> String {
        let maxCharacters = max(0, maxTokens * 4)
        guard text.count > maxCharacters else {
            return text
        }
        return String(text.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func estimatedTokens(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }

    private func tokenCount(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : estimatedTokens(text)
    }

    private func openAIAPIKey(from environment: [String: String]) -> String {
        if let value = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return (try? configurationStore.loadOrCreate().apiKeys.openAI.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    private func directModelMaxTokens(
        for modelRef: String,
        requestedMaxTokens: Int,
        openAISettings: OpenAIDirectChatSettings
    ) -> Int {
        let normalized = modelRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("openai/") {
            return min(requestedMaxTokens, openAISettings.maxTokens)
        }
        return requestedMaxTokens
    }

    private func ensureDirectModelRuntimeReady(for modelRef: String) async throws {
        _ = modelRef
    }

    private func directChatPrompt(for message: String) -> String {
        let isTinyTurn = isTinyDirectChatTurn(message)
        let transcript = chatMessages
            .suffix(isTinyTurn ? 2 : 4)
            .filter { $0.role != .error }
            .map { message in
                "\(message.role.rawValue): \(message.text)"
            }
            .joined(separator: "\n")
        let personaContext = directPersonaContext(compact: isTinyTurn)
        let brevityRule = isTinyTurn
            ? "For very short casual inputs like hi, ok, thanks, or emojis, answer in one short sentence under 16 words."
            : "Keep voice replies compact but complete: normally 1-4 sentences, not one-word unless the user asks for it."

        return """
        Use the workspace setup below as the authoritative bot configuration.
        Follow SOUL.md, IDENTITY.md, AGENTS.md, USER.md, MEMORY.md, and TOOLS.md exactly when shaping identity, tone, behavior, and memory.
        Preserve prior conversation context. If asked who you are, answer from the workspace identity, not as a generic assistant.
        \(brevityRule)
        Start with the final visible answer immediately. Do not spend the answer budget restating or analyzing the setup.
        Do not mention prompts, files, or implementation details.

        Workspace setup:
        \(personaContext)

        Conversation:
        \(transcript)
        """
    }

    private func isTinyDirectChatTurn(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count <= 12
    }

    private func directPersonaContext(compact: Bool) -> String {
        if compact, let directCompactPersonaContextCache {
            return directCompactPersonaContextCache
        }
        if !compact, let directPersonaContextCache {
            return directPersonaContextCache
        }
        let coreFiles: [(relativePath: String, maxCharacters: Int?)] = [
            ("SOUL.md", compact ? 700 : 2_500),
            ("IDENTITY.md", compact ? 500 : 1_200),
            ("AGENTS.md", compact ? 800 : 1_800),
            ("USER.md", compact ? 700 : 1_200),
            ("MEMORY.md", compact ? 500 : 1_500),
            ("TOOLS.md", compact ? 300 : 800)
        ]
        var sections = coreFiles.compactMap { file in
            directWorkspaceFileSection(
                relativePath: file.relativePath,
                maxCharacters: file.maxCharacters
            )
        }

        if !compact, let styleSection = directWorkspaceFileSection(
            relativePath: "style/vibe1.txt",
            maxCharacters: 2_000
        ) {
            sections.append(styleSection)
        }

        if !compact {
            sections.append(contentsOf: directMemoryFileSections())
        }

        let context = sections.isEmpty ? "No workspace setup files found." : sections.joined(separator: "\n\n")
        if compact {
            directCompactPersonaContextCache = context
            appendLog("[latency] Direct compact persona context cached; characters=\(context.count)")
        } else {
            directPersonaContextCache = context
            appendLog("[latency] Direct persona context cached; characters=\(context.count)")
        }
        return context
    }

    private func directWorkspaceFileSection(relativePath: String, maxCharacters: Int? = nil) -> String? {
        let url = workspaceDirectory.appendingPathComponent(relativePath)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let body: String
        if let maxCharacters, trimmed.count > maxCharacters {
            body = String(trimmed.prefix(maxCharacters))
                + "\n\n[truncated for direct voice speed; full file remains in workspace]"
        } else {
            body = trimmed
        }
        return "## \(relativePath)\n\(body)"
    }

    private func directMemoryFileSections() -> [String] {
        let memoryDirectory = workspaceDirectory.appendingPathComponent("memory", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: memoryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(directMemoryFileLimit)
            .compactMap { url in
                directWorkspaceFileSection(
                    relativePath: "memory/\(url.lastPathComponent)",
                    maxCharacters: 1_000
                )
            }
    }

    private func prepareTestDirectories(configDirectory: URL, workspaceDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: configDirectory.appendingPathComponent("canvas", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: configDirectory.appendingPathComponent("cron", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func runProcess(
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> ProcessOutput {
        try await runExternalProcess(
            executableURL: nodeURL,
            arguments: arguments,
            currentDirectoryURL: projectDirectory,
            environment: environment,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runExternalProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let buffer = ProcessOutputBuffer()
            let completion = ProcessCompletionState()

            @Sendable func finish(
                _ result: Result<ProcessOutput, Error>,
                terminateIfRunning: Bool = false
            ) {
                guard completion.claim() else {
                    return
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                if terminateIfRunning, process.isRunning {
                    let processIdentifier = process.processIdentifier
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                        Darwin.kill(processIdentifier, SIGKILL)
                    }
                }

                switch result {
                case let .success(output):
                    continuation.resume(returning: output)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    buffer.appendStdout(data)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    buffer.appendStderr(data)
                }
            }

            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { finished in
                let snapshot = buffer.snapshot()
                let output = ProcessOutput(
                    stdout: snapshot.stdout,
                    stderr: snapshot.stderr,
                    exitCode: finished.terminationStatus
                )
                finish(.success(output))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            if let timeoutSeconds {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                    let snapshot = buffer.snapshot()
                    let stderr = snapshot.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let suffix = stderr.isEmpty ? "" : " Last error output: \(String(stderr.suffix(1200)))"
                    finish(
                        .failure(
                            OpenClawLocalControllerError.agentFailed(
                                "OpenClaw command timed out after \(Int(timeoutSeconds)) seconds.\(suffix)"
                            )
                        ),
                        terminateIfRunning: true
                    )
                }
            }
        }
    }

    private func runCommand(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let buffer = ProcessOutputBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                buffer.appendStdout(data)
                if let text = String(data: data, encoding: .utf8) {
                    onOutput?(text)
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                buffer.appendStderr(data)
                if let text = String(data: data, encoding: .utf8) {
                    onOutput?(text)
                }
            }
        }

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let snapshot = buffer.snapshot()
        return ProcessOutput(
            stdout: snapshot.stdout,
            stderr: snapshot.stderr,
            exitCode: process.terminationStatus
        )
    }

    private func decodeAgentResponse(from text: String) throws -> OpenClawAgentTurnResponse {
        guard let data = text.data(using: .utf8) else {
            throw OpenClawLocalControllerError.agentFailed("OpenClaw response was not valid UTF-8.")
        }
        return try JSONDecoder().decode(OpenClawAgentTurnResponse.self, from: data)
    }

    private func latestAssistantReplyFromSession() -> String? {
        let sessionURL = configDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(chatSessionID).jsonl")

        guard let contents = try? String(contentsOf: sessionURL) else {
            appendLog("No OpenClaw session transcript found at \(sessionURL.path).")
            return nil
        }

        for line in contents.components(separatedBy: .newlines).reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "message",
                  let message = object["message"] as? [String: Any],
                  message["role"] as? String == "assistant" else {
                continue
            }

            let contentText = assistantContentText(from: message)
            if !contentText.isEmpty {
                appendLog("Recovered OpenClaw reply from session transcript.")
                return contentText
            }

            if let errorMessage = message["errorMessage"] as? String,
               !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        appendLog("OpenClaw session transcript did not contain an assistant reply.")
        return nil
    }

    private func publishOnlyFansPostFromChatCommand(_ message: String) async throws -> String {
        guard let postText = onlyFansPostText(from: message) else {
            return [
                "Я понял команду публикации в OnlyFans, но не нашел текст поста.",
                "Напиши так: `опубликуй пост в OnlyFans: текст поста`.",
                "Если хочешь опубликовать уже написанный пост, сначала попроси меня написать текст, потом отправь `опубликуй этот пост в OnlyFans`."
            ].joined(separator: "\n")
        }

        let trimmedPostText = postText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPostText.isEmpty else {
            return "Я понял команду публикации в OnlyFans, но текст поста пустой. Добавь текст после двоеточия."
        }

        try await onlyFansPoster.publishPost(text: trimmedPostText)
        appendLog("Published OnlyFans post from explicit chat command. characters=\(trimmedPostText.count)")
        return "Опубликовал пост в OnlyFans."
    }

    private func isExplicitOnlyFansPublishRequest(_ message: String) -> Bool {
        let normalized = normalizedCommandText(message)
        let mentionsOnlyFans = [
            "onlyfans",
            "only fans",
            "онлифанс",
            "онли фанс",
            "онли фан",
            "он ли фанс",
            "он ли фан"
        ].contains { normalized.contains($0) }

        let asksToPublish = [
            "опублику",
            "запост",
            "запубли",
            "вылож",
            "размест",
            "отправ",
            "публику",
            "publish",
            "post "
        ].contains { normalized.contains($0) }

        return mentionsOnlyFans && asksToPublish
    }

    private func onlyFansPostText(from message: String) -> String? {
        if let inlineText = inlineOnlyFansPostText(from: message) {
            return inlineText
        }

        if normalizedCommandText(message).contains("этот пост") || normalizedCommandText(message).contains("предыдущии пост") {
            return nil
        }

        return nil
    }

    private func inlineOnlyFansPostText(from message: String) -> String? {
        let separators = [":", ":\n", "\n\n"]
        for separator in separators {
            guard let range = message.range(of: separator) else {
                continue
            }
            let candidate = String(message[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isPublishablePostText(candidate) {
                return candidate
            }
        }

        if let textAfterOnlyFans = textAfterOnlyFansMention(in: message),
           isPublishablePostText(textAfterOnlyFans) {
            return textAfterOnlyFans
        }

        let markerCandidates = [
            "текст поста",
            "пост:",
            "post:"
        ]
        let lowercasedMessage = message.lowercased()
        for marker in markerCandidates {
            guard let range = lowercasedMessage.range(of: marker) else {
                continue
            }
            let candidate = String(message[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":—-")))
            if isPublishablePostText(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func textAfterOnlyFansMention(in message: String) -> String? {
        let normalizedMessage = normalizedCommandText(message)
        let markers = [
            "onlyfans",
            "only fans",
            "онлифанс",
            "онли фанс",
            "онли фан",
            "он ли фанс",
            "он ли фан"
        ]

        for marker in markers {
            guard let range = normalizedMessage.range(of: marker) else {
                continue
            }

            let candidateStartOffset = normalizedMessage.distance(from: normalizedMessage.startIndex, to: range.upperBound)
            guard candidateStartOffset <= message.count,
                  let candidateStart = message.index(message.startIndex, offsetBy: candidateStartOffset, limitedBy: message.endIndex) else {
                continue
            }

            let candidate = String(message[candidateStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":—-.,;")))
            if isPublishablePostText(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func isPublishablePostText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }

    private func normalizedCommandText(_ text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "й", with: "и")
    }

    private func assistantContentText(from message: [String: Any]) -> String {
        guard let content = message["content"] as? [[String: Any]] else {
            return ""
        }

        return content.compactMap { entry -> String? in
            guard entry["type"] as? String == "text",
                  let text = entry["text"] as? String else {
                return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n\n")
    }

    private func recoverJSONObject(from text: String) throws -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    @discardableResult
    private func appendChatMessage(_ message: OpenClawChatMessage) -> UUID {
        chatMessages.append(message)
        if chatMessages.count > 100 {
            chatMessages.removeFirst(chatMessages.count - 100)
        }
        return message.id
    }

    private func updateChatMessage(id: UUID, text: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updatedMessages = chatMessages
        updatedMessages[index].text = text
        chatMessages = updatedMessages
    }

    private func logSnippet(_ text: String, maxCharacters: Int = 1_200) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxCharacters else {
            return normalized
        }
        return "\(normalized.prefix(maxCharacters))..."
    }

    private func removePendingAssistantPlaceholder() {
        guard let index = chatMessages.lastIndex(where: { $0.role == .assistant && $0.text == "…" }) else {
            return
        }
        chatMessages.remove(at: index)
    }

    private nonisolated func checkHealth(url: URL) async -> String {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return "bad response"
            }
            return httpResponse.statusCode == 200 ? "healthy" : "HTTP \(httpResponse.statusCode)"
        } catch {
            return "offline"
        }
    }

    private nonisolated func isTCPPortOpen(host: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let socketDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
                guard socketDescriptor >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                defer { Darwin.close(socketDescriptor) }

                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = port.bigEndian

                let result = host.withCString { cString in
                    inet_pton(AF_INET, cString, &address.sin_addr)
                }
                guard result == 1 else {
                    continuation.resume(returning: false)
                    return
                }

                var socketAddress = sockaddr()
                memcpy(&socketAddress, &address, MemoryLayout<sockaddr_in>.size)
                let connectResult = withUnsafePointer(to: &socketAddress) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                        Darwin.connect(
                            socketDescriptor,
                            reboundPointer,
                            socklen_t(MemoryLayout<sockaddr_in>.size)
                        )
                    }
                }
                continuation.resume(returning: connectResult == 0)
            }
        }
    }

    private static func tokensPerSecond(tokens: Int?, durationNanoseconds: NSNumber?) -> Double? {
        guard let tokens,
              let durationNanoseconds,
              durationNanoseconds.doubleValue > 0 else {
            return nil
        }
        return Double(tokens) / (durationNanoseconds.doubleValue / 1_000_000_000)
    }

    private func appendLog(_ text: String, prefix: String? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }
            let label = prefix.map { "[\($0)] " } ?? ""
            logLines.append("[\(timestamp)] \(label)\(redacted(line))")
        }
        if logLines.count > 180 {
            logLines.removeFirst(logLines.count - 180)
        }
    }

    nonisolated private static func shouldSuppressObservedProcessLog(_ text: String, processName: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard processName == "gateway" else {
            return false
        }
        return normalized.contains("gateway already running locally")
            || normalized.contains("stop it (openclaw gateway stop) or use a different port")
    }

    private func redacted(_ line: String) -> String {
        var output = line
        output = output.replacingOccurrences(
            of: #"rtmps?://[^\s"']+"#,
            with: "[redacted-url]",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?i)(api[_-]?key|token|secret|cookie|authorization)=([^,\s"']+)"#,
            with: "$1=[redacted]",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?i)(api[_-]?key|token|secret|cookie|authorization)["']?\s*:\s*["'][^"']+["']"#,
            with: "$1: \"[redacted]\"",
            options: .regularExpression
        )
        return output
    }

}

struct OpenClawSettingsSnapshot: Equatable {
    let runtimeRows: [OpenClawSettingsRow]
    let permissionRows: [OpenClawSettingsRow]
    let environmentRows: [OpenClawSettingsRow]
    let toolRows: [OpenClawSettingsRow]
    let environmentEntries: [OpenClawEditableSetting]
    let jsonEntries: [OpenClawEditableSetting]
    let workspaceFiles: [OpenClawWorkspaceFile]
}

struct OpenClawSettingsRow: Identifiable, Equatable {
    let id: String
    let name: String
    let value: String
}

struct OpenClawEditableSetting: Identifiable, Equatable {
    enum Source: String, Equatable {
        case environment
        case json
    }

    enum ValueKind: String, Equatable {
        case string
        case bool
        case int
        case double
        case array
        case object
        case null
    }

    let id: String
    let key: String
    let source: Source
    let kind: ValueKind
    let isSecret: Bool
    var value: String

    init(key: String, source: Source, kind: ValueKind, isSecret: Bool, value: String) {
        self.id = "\(source.rawValue):\(key)"
        self.key = key
        self.source = source
        self.kind = kind
        self.isSecret = isSecret
        self.value = value
    }
}

struct OpenClawWorkspaceFile: Identifiable, Equatable {
    let id: String
    let relativePath: String
    let absolutePath: String
    let existsOnDisk: Bool
    let byteCount: Int
    var contents: String

    init(relativePath: String, absolutePath: String, existsOnDisk: Bool, byteCount: Int, contents: String) {
        self.id = relativePath
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.existsOnDisk = existsOnDisk
        self.byteCount = byteCount
        self.contents = contents
    }
}

private func resolveOpenClawRepositoryDirectory() -> URL {
    let fileManager = FileManager.default
    let env = ProcessInfo.processInfo.environment

    if let override = env["GRACULA_OPENCLAW_REPOSITORY_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        return URL(filePath: override, directoryHint: .isDirectory)
    }

    let currentDirectory = URL(filePath: fileManager.currentDirectoryPath, directoryHint: .isDirectory)
    var relativeCandidates: [URL] = []
    if currentDirectory.path != "/" {
        relativeCandidates.append(
            currentDirectory
                .appendingPathComponent("openclaw", isDirectory: true)
                .standardizedFileURL
        )
        relativeCandidates.append(
            currentDirectory
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("openclaw", isDirectory: true)
                .standardizedFileURL
        )
        relativeCandidates.append(
            currentDirectory
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("Vendor", isDirectory: true)
                .appendingPathComponent("openclaw", isDirectory: true)
                .standardizedFileURL
        )
    }

    let userRuntimeCandidate = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("GraculaExample", isDirectory: true)
        .appendingPathComponent("openclaw", isDirectory: true)

    for candidate in relativeCandidates + [userRuntimeCandidate] {
        if fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
    }

    return userRuntimeCandidate
}

private func resolveGraculaProjectDirectory() -> URL {
    let fileManager = FileManager.default
    let env = ProcessInfo.processInfo.environment

    if let sourceRoot = locateGraculaProjectRoot(
        startingAt: URL(filePath: #filePath, directoryHint: .notDirectory).deletingLastPathComponent()
    ) {
        return sourceRoot
    }

    if let override = env["GRACULA_PROJECT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty,
       let overrideRoot = locateGraculaProjectRoot(
        startingAt: URL(filePath: override, directoryHint: .isDirectory)
       ) {
        return overrideRoot
    }

    let currentDirectory = URL(filePath: fileManager.currentDirectoryPath, directoryHint: .isDirectory)
    if let currentRoot = locateGraculaProjectRoot(startingAt: currentDirectory) {
        return currentRoot
    }

    return currentDirectory
}

private func locateGraculaProjectRoot(startingAt url: URL) -> URL? {
    let fileManager = FileManager.default
    var candidate = url.standardizedFileURL

    while candidate.path != "/" {
        if fileManager.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path),
           fileManager.fileExists(atPath: candidate.appendingPathComponent("Examples", isDirectory: true).path),
           fileManager.fileExists(atPath: candidate.appendingPathComponent(".openclaw/workspace", isDirectory: true).path) {
            return candidate
        }
        candidate = candidate.deletingLastPathComponent()
    }

    return nil
}

private let requiredProjectWorkspaceFiles = [
    "SOUL.md",
    "IDENTITY.md",
    "AGENTS.md",
    "USER.md",
    "TOOLS.md",
    "persona_compact.md"
]

private func resolveNodeExecutableURL() -> URL {
    let fileManager = FileManager.default
    let env = ProcessInfo.processInfo.environment
    if let override = env["GRACULA_NODE_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        let url = URL(filePath: override)
        if fileManager.isExecutableFile(atPath: url.path) {
            return url
        }
    }

    let candidates = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        "/usr/bin/node"
    ]
    for candidate in candidates {
        let url = URL(filePath: candidate)
        if fileManager.isExecutableFile(atPath: url.path) {
            return url
        }
    }
    return URL(filePath: candidates.first ?? "/usr/bin/node")
}

private struct PackageManagerCommand {
    let executableURL: URL
    let displayName: String
    let installArguments: [String]
    let buildArguments: [String]
}

private func resolvePackageManagerCommand() -> PackageManagerCommand? {
    let fileManager = FileManager.default
    let env = ProcessInfo.processInfo.environment
    if let override = env["GRACULA_PNPM_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        let url = URL(filePath: override)
        if fileManager.isExecutableFile(atPath: url.path) {
            return PackageManagerCommand(
                executableURL: url,
                displayName: url.lastPathComponent,
                installArguments: ["install", "--frozen-lockfile"],
                buildArguments: ["build"]
            )
        }
    }

    let pnpmCandidates = [
        "/opt/homebrew/bin/pnpm",
        "/usr/local/bin/pnpm",
        "/usr/bin/pnpm"
    ]
    for candidate in pnpmCandidates {
        let url = URL(filePath: candidate)
        if fileManager.isExecutableFile(atPath: url.path) {
            return PackageManagerCommand(
                executableURL: url,
                displayName: "pnpm",
                installArguments: ["install", "--frozen-lockfile"],
                buildArguments: ["build"]
            )
        }
    }

    let corepackCandidates = [
        "/opt/homebrew/bin/corepack",
        "/usr/local/bin/corepack",
        "/usr/bin/corepack"
    ]
    for candidate in corepackCandidates {
        let url = URL(filePath: candidate)
        if fileManager.isExecutableFile(atPath: url.path) {
            return PackageManagerCommand(
                executableURL: url,
                displayName: "corepack pnpm",
                installArguments: ["pnpm", "install", "--frozen-lockfile"],
                buildArguments: ["pnpm", "build"]
            )
        }
    }

    return nil
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func appendStdout(_ data: Data) {
        lock.lock()
        stdoutData.append(data)
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        stderrData.append(data)
        lock.unlock()
    }

    func snapshot() -> (stdout: String, stderr: String) {
        lock.lock()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        lock.unlock()
        return (stdout, stderr)
    }
}

private final class ProcessCompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !didComplete else {
            return false
        }

        didComplete = true
        return true
    }
}

private struct DirectModelChatResult {
    let text: String
    let metrics: DirectModelMetrics?
}

private struct OpenAIDirectChatSettings {
    let temperature: Double
    let topP: Double
    let maxTokens: Int

    static let `default` = OpenAIDirectChatSettings(
        temperature: 0.35,
        topP: 0.85,
        maxTokens: 512
    )
}

private struct DirectModelSamplingOptions {
    let temperature: Double
    let topP: Double
    let repeatPenalty: Double

    static func standard(
        for maxTokens: Int,
        temperature: Double? = nil,
        topP: Double? = nil
    ) -> DirectModelSamplingOptions {
        if let temperature, let topP {
            return DirectModelSamplingOptions(temperature: temperature, topP: topP, repeatPenalty: 1.08)
        }
        if maxTokens <= 64 {
            return DirectModelSamplingOptions(temperature: 0, topP: 0, repeatPenalty: 1.08)
        }
        return DirectModelSamplingOptions(temperature: 0.35, topP: 0.85, repeatPenalty: 1.08)
    }

    static let strictRetry = DirectModelSamplingOptions(
        temperature: 0.1,
        topP: 0.35,
        repeatPenalty: 1.18
    )
}

private struct DirectModelMetrics {
    let providerLabel: String
    let promptTokens: Int?
    let promptTokensPerSecond: Double?
    let generationTokens: Int?
    let generationTokensPerSecond: Double?
    let peakMemoryGB: Double?

    var statusSummary: String {
        var parts: [String] = []
        if let generationTokensPerSecond {
            parts.append("\(Self.format(generationTokensPerSecond)) tok/s")
        }
        if let generationTokens {
            parts.append("\(generationTokens) generated")
        }
        if let promptTokensPerSecond {
            parts.append("prompt \(Self.format(promptTokensPerSecond)) tok/s")
        }
        if let peakMemoryGB {
            parts.append("peak \(Self.format(peakMemoryGB)) GB")
        }
        return parts.isEmpty ? "no throughput metrics reported" : parts.joined(separator: ", ")
    }

    var logSummary: String {
        "\(providerLabel): \(statusSummary)"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct DirectModelScriptResponse: Decodable {
    let text: String
    let metrics: DirectModelScriptMetrics?
}

private struct DirectModelScriptMetrics: Decodable {
    let promptTokens: Int?
    let promptTokensPerSecond: Double?
    let generationTokens: Int?
    let generationTokensPerSecond: Double?
    let peakMemoryGB: Double?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case promptTokensPerSecond = "prompt_tps"
        case generationTokens = "generation_tokens"
        case generationTokensPerSecond = "generation_tps"
        case peakMemoryGB = "peak_memory"
    }
}

enum OpenClawLocalControllerError: LocalizedError {
    case missingRuntime(String)
    case gatewayUnavailable(String)
    case agentFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingRuntime(message):
            return message
        case let .gatewayUnavailable(message):
            return message
        case let .agentFailed(message):
            return message
        }
    }
}

struct OpenClawChatMessage: Identifiable, Equatable {
    enum Role: String {
        case system
        case user
        case assistant
        case error
    }

    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

    static func system(_ text: String) -> OpenClawChatMessage {
        OpenClawChatMessage(role: .system, text: text)
    }

    static func user(_ text: String) -> OpenClawChatMessage {
        OpenClawChatMessage(role: .user, text: text)
    }

    static func assistant(_ text: String) -> OpenClawChatMessage {
        OpenClawChatMessage(role: .assistant, text: text)
    }

    static func error(_ text: String) -> OpenClawChatMessage {
        OpenClawChatMessage(role: .error, text: text)
    }
}

private struct OpenClawAgentTurnResponse: Decodable {
    let runId: String?
    let status: String?
    let summary: String?
    let payloads: [OpenClawAgentTurnPayload]?
    let result: OpenClawAgentTurnResult?
}

private struct OpenClawAgentTurnResult: Decodable {
    let payloads: [OpenClawAgentTurnPayload]?
}

private struct OpenClawAgentTurnPayload: Decodable {
    let text: String?
    let mediaUrl: String?
    let mediaUrls: [String]?
}

private struct ProcessOutput {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private enum GatewayLaunchRecovery {
    case attached
    case retryLaunch
    case unhandled
}

private extension OpenClawAgentTurnResponse {
    var replyText: String {
        let allPayloads = (result?.payloads ?? []) + (payloads ?? [])
        let payloadText = allPayloads.compactMap({ $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .joined(separator: "\n\n")
        if !payloadText.isEmpty {
            return payloadText
        }
        return summary ?? ""
    }
}
