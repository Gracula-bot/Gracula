import AppKit
import Automation
import Darwin
import Foundation

enum OpenClawRuntimePaths {
    static var configDirectory: URL {
        resolveGraculaProjectDirectory()
            .appendingPathComponent(".openclaw", isDirectory: true)
    }

    static var workspaceDirectory: URL {
        configDirectory.appendingPathComponent("workspace", isDirectory: true)
    }

    static var configURL: URL {
        configDirectory.appendingPathComponent("openclaw.json")
    }
}

struct OpenClawLLMProviderConfiguration {
    let name: String
    let modelPrefixes: [String]
    let environmentKeys: [String]
    let baseURL: String
    let api: String
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

struct OpenClawLocalMLXModelConfiguration {
    let id: String
    let displayName: String
    let localDirectoryName: String?
    let huggingFaceRepository: String?
    let rapidAlias: String?
    let rapidToolCallParser: String?
    let rapidToolFeatures: [String]
    let contextWindow: Int
    let maxTokens: Int

    var modelRef: String {
        "mlx/\(id)"
    }

    var usesRapidMLX: Bool {
        rapidAlias?.isEmpty == false
    }

    var providerModel: OpenClawLLMModelConfiguration {
        OpenClawLLMModelConfiguration(
            id: id,
            name: displayName,
            api: "openai-completions",
            reasoning: false,
            contextWindow: contextWindow,
            maxTokens: maxTokens,
            contextTokens: min(contextWindow, 16_384),
            compat: [
                "supportsTools": true,
                "supportsStrictMode": false
            ]
        )
    }
}

enum OpenClawLLMConfiguration {
    static let localQwenModelRef = "ollama/qwen3:14b"
    static let localQwenMLXModelRef = "mlx/qwen3-14b-4bit"
    static let localNemotronNanoModelRef = "mlx/nemotron-nano"
    static let deprecatedQwen30BMLXModelRef = "mlx/Qwen/Qwen3-30B-A3B-MLX-4bit"

    static let localMLXModels: [OpenClawLocalMLXModelConfiguration] = [
        OpenClawLocalMLXModelConfiguration(
            id: "qwen3-14b-4bit",
            displayName: "Qwen3 14B MLX 4-bit",
            localDirectoryName: "Qwen3-14B-4bit",
            huggingFaceRepository: "mlx-community/Qwen3-14B-4bit",
            rapidAlias: nil,
            rapidToolCallParser: nil,
            rapidToolFeatures: [],
            contextWindow: 32_768,
            maxTokens: 4_096
        ),
        OpenClawLocalMLXModelConfiguration(
            id: "nemotron-nano",
            displayName: "Nemotron Nano 30B MLX 4-bit",
            localDirectoryName: nil,
            huggingFaceRepository: "lmstudio-community/NVIDIA-Nemotron-3-Nano-30B-A3B-MLX-4bit",
            rapidAlias: "nemotron-nano",
            rapidToolCallParser: "nemotron",
            rapidToolFeatures: ["nemotron", "gc-control"],
            contextWindow: 131_072,
            maxTokens: 4_096
        )
    ]

    static let providers: [OpenClawLLMProviderConfiguration] = [
        OpenClawLLMProviderConfiguration(
            name: "ollama",
            modelPrefixes: ["ollama/"],
            environmentKeys: [],
            baseURL: "http://127.0.0.1:11434",
            api: "ollama",
            modelsJSON: OpenClawLLMModelConfiguration.jsonArray([
                OpenClawLLMModelConfiguration(
                    id: "qwen3:14b",
                    name: "Qwen3 14B (local Ollama)",
                    api: "ollama",
                    reasoning: false,
                    contextWindow: 65_536,
                    maxTokens: 8_192,
                    params: [
                        "think": false,
                        "keep_alive": "30m",
                        "num_ctx": 65_536
                    ],
                    compat: ["supportsTools": false]
                )
            ])
        ),
        OpenClawLLMProviderConfiguration(
            name: "mlx",
            modelPrefixes: ["mlx/"],
            environmentKeys: [],
            baseURL: "http://127.0.0.1:8080/v1",
            api: "openai-completions",
            modelsJSON: OpenClawLLMModelConfiguration.jsonArray(localMLXModels.map(\.providerModel))
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
        if trimmed.lowercased() == deprecatedQwen30BMLXModelRef.lowercased() {
            return localNemotronNanoModelRef
        }
        return trimmed
    }

    static func mergeOpenClawJSONEnvironment(from configURL: URL, into environment: inout [String: String]) {
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        mergeEnvVars(from: object, into: &environment)
    }

    static func localMLXModel(for modelID: String) -> OpenClawLocalMLXModelConfiguration? {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return localMLXModels.first { model in
            model.id.lowercased() == normalized
                || model.modelRef.lowercased() == normalized
        }
    }

    static func mergeEnvironmentSources(
        repositoryEnvURL: URL,
        configEnvURL: URL,
        configURL: URL,
        into environment: inout [String: String]
    ) {
        mergeEnvFile(repositoryEnvURL, into: &environment)
        mergeEnvFile(configEnvURL, into: &environment)
        mergeOpenClawJSONEnvironment(from: configURL, into: &environment)
    }

    static func entriesWithProviderDefaults(_ entries: [OpenClawEditableSetting]) -> [OpenClawEditableSetting] {
        var normalized = entries
        for provider in providers {
            ensureEntry(key: provider.baseURLPath, value: provider.baseURL, in: &normalized)
            ensureEntry(key: provider.apiPath, value: provider.api, in: &normalized)
            ensureEntry(key: provider.modelsPath, value: provider.modelsJSON, kind: .array, in: &normalized)
            if provider.name == "ollama" {
                ensureEntry(key: "\(provider.providerPrefix).authHeader", value: "false", kind: .bool, in: &normalized)
            }
        }
        return normalized
    }

    private static func mergeEnvVars(from rootObject: [String: Any], into environment: inout [String: String]) {
        guard let envObject = rootObject["env"] as? [String: Any],
              let vars = envObject["vars"] as? [String: Any] else {
            return
        }

        for (key, rawValue) in vars {
            guard isValidEnvironmentKey(key) else {
                continue
            }
            if let value = rawValue as? String {
                environment[key] = value
            } else if let value = rawValue as? NSNumber {
                environment[key] = value.stringValue
            }
        }
    }

    private static func mergeEnvFile(_ url: URL, into environment: inout [String: String]) {
        guard let contents = try? String(contentsOf: url) else {
            return
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidEnvironmentKey(key) else {
                continue
            }

            var value = String(line[line.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            environment[key] = value
        }
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

    private static func isValidEnvironmentKey(_ key: String) -> Bool {
        key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
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
        runtimeContextWindow: 32768,
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

        for field in memoryFields {
            try? await createPayloadIndex(collection: Self.memoryCollection, fieldName: field.0, fieldSchema: field.1)
        }
        for field in cacheFields {
            try? await createPayloadIndex(collection: Self.notificationCacheCollection, fieldName: field.0, fieldSchema: field.1)
        }
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
            "payload": payload
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

        private func int(_ key: String, fallback: Int = 0) -> Int {
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

@MainActor
final class OpenClawLocalController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Stopped"
    @Published private(set) var gatewayStatus = "not checked"
    @Published private(set) var streamBridgeStatus = "not checked"
    @Published private(set) var logLines: [String] = []
    @Published private(set) var chatMessages: [OpenClawChatMessage] = []
    @Published private(set) var chatStatusText = "Ready to chat."
    @Published private(set) var isSendingChat = false
    @Published private(set) var isPreparingLocalModel = false
    @Published private(set) var localModelStatusText = ""
    @Published private(set) var localModelPreparationProgress: Double?
    @Published private(set) var settingsSnapshot: OpenClawSettingsSnapshot
    @Published private(set) var settingsStatusText = "Settings loaded."

    let repositoryDirectory = resolveOpenClawRepositoryDirectory()
    let configDirectory = OpenClawRuntimePaths.configDirectory
    let workspaceDirectory = OpenClawRuntimePaths.workspaceDirectory

    private let nodeURL = resolveNodeExecutableURL()
    private let gatewayHost = "127.0.0.1"
    private let fallbackGatewayPort = "18789"
    private let streamBridgePort = "7071"
    private let agentTurnTimeoutSeconds: TimeInterval = 180
    private let directModelTimeoutSeconds: TimeInterval = 120
    private let directMLXTimeoutSeconds: TimeInterval = 240
    private let directVoiceTinyMaxTokens = 64
    private let directVoiceShortMaxTokens = 256
    private let directVoiceNormalMaxTokens = 700
    private let directMemoryFileLimit = 2
    private let mlxRuntimeDirectory = resolveMLXRuntimeDirectory()
    private let mlxModelsDirectory = resolveMLXModelsDirectory()
    private let onlyFansPoster = WorkspaceOpeningClient()
    private var chatSessionID = "gracula-local-chat"
    private var gatewayProcess: Process?
    private var streamBridgeProcess: Process?
    private var localModelProcess: Process?
    private var healthTask: Task<Void, Never>?
    private var directModelPrewarmTask: Task<Void, Never>?
    private var consecutiveHealthFailures = 0
    private var startupTask: Task<Void, Never>?
    private var directPersonaContextCache: String?
    private var directCompactPersonaContextCache: String?

    init() {
        self.settingsSnapshot = Self.makeSettingsSnapshot()
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
        directModelPrewarmTask?.cancel()
        gatewayProcess?.terminate()
        streamBridgeProcess?.terminate()
        localModelProcess?.terminate()
        healthTask?.cancel()
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
            try validateRuntime()
            try prepareDirectories()
            let environment = try openClawEnvironment()
            settingsSnapshot = Self.makeSettingsSnapshot(environment: environment)
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

            do {
                gatewayProcess = try launchProcess(
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
                isRunning = true
                statusText = "Starting local OpenClaw..."
                appendLog("Started OpenClaw gateway locally without Docker.")
                appendLog("Gateway: http://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)/")
            } catch {
                let launchErrorMessage = error.localizedDescription
                let normalizedLaunchError = launchErrorMessage.lowercased()
                let gatewayAlreadyRunning = normalizedLaunchError.contains("already running")
                    || normalizedLaunchError.contains("port 18789 is already in use")
                    || normalizedLaunchError.contains("lock timeout")

                if gatewayAlreadyRunning {
                    let existingGatewayURL = URL(
                        string: "http://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)/healthz"
                    )!
                    let existingGatewayStatus = await checkHealth(url: existingGatewayURL)
                    guard existingGatewayStatus == "healthy" else {
                        gatewayProcess = nil
                        isRunning = false
                        gatewayStatus = existingGatewayStatus
                        throw OpenClawLocalControllerError.gatewayUnavailable(
                            "An existing OpenClaw gateway is occupying http://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)/, but /healthz is \(existingGatewayStatus). Stop that stale process and start OpenClaw again."
                        )
                    }

                    gatewayProcess = nil
                    isRunning = true
                    statusText = "Using existing OpenClaw gateway..."
                    gatewayStatus = "healthy"
                    appendLog("OpenClaw gateway is already running outside the app and passed health check; attaching to http://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)/")
                } else {
                    throw error
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
            await ensureLocalModelServer()
        } catch {
            stop()
            statusText = "Start failed"
            appendLog("Start failed: \(error.localizedDescription)")
            appendChatMessage(.error(error.localizedDescription))
        }
    }

    func stop() {
        directModelPrewarmTask?.cancel()
        directModelPrewarmTask = nil
        healthTask?.cancel()
        healthTask = nil
        startupTask?.cancel()
        startupTask = nil
        terminate(process: gatewayProcess, name: "gateway")
        terminate(process: streamBridgeProcess, name: "stream-bridge")
        terminate(process: localModelProcess, name: "mlx-model")
        gatewayProcess = nil
        streamBridgeProcess = nil
        localModelProcess = nil
        isRunning = false
        statusText = "Stopped"
        gatewayStatus = "stopped"
        streamBridgeStatus = "stopped"
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

    func reportError(_ message: String) {
        appendChatMessage(.error(message))
    }

    func prepareForLocalAutomation() async -> Bool {
        do {
            try validateRuntime()
            try prepareDirectories()
            let environment = try openClawEnvironment()
            settingsSnapshot = Self.makeSettingsSnapshot(environment: environment)
            return true
        } catch {
            let message = "OpenClaw is not ready for local automation: \(error.localizedDescription)"
            appendLog(message)
            appendChatMessage(.error(message))
            return false
        }
    }

    func reloadSettings() {
        settingsSnapshot = Self.makeSettingsSnapshot()
        directPersonaContextCache = nil
        directCompactPersonaContextCache = nil
        settingsStatusText = "Settings reloaded."
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
            let tempConfigDirectory = tempDirectory.appendingPathComponent(".openclaw", isDirectory: true)
            let tempWorkspaceDirectory = tempConfigDirectory.appendingPathComponent("workspace", isDirectory: true)
            let tempConfigURL = tempConfigDirectory.appendingPathComponent("openclaw.json")
            try prepareTestDirectories(
                configDirectory: tempConfigDirectory,
                workspaceDirectory: tempWorkspaceDirectory
            )
            try OpenClawSettingsReader.writeEnvironment(
                entries: environmentEntries,
                to: tempConfigDirectory.appendingPathComponent(".env")
            )
            try OpenClawSettingsReader.writeJSON(
                entries: jsonEntries,
                to: tempConfigURL
            )
            try OpenClawSettingsReader.writeWorkspaceFiles(workspaceFiles, to: tempWorkspaceDirectory)
            try copyAuthStoreIntoTestSandbox(
                sandboxDirectory: tempDirectory
            )

            let environment = try openClawEnvironment(
                configDirectory: tempConfigDirectory,
                workspaceDirectory: tempWorkspaceDirectory,
                configPath: tempConfigURL,
                stateDirectory: tempDirectory
            )
            let primaryModelRef = currentPrimaryModelRef(in: jsonEntries)
            let reply: String
            let metrics: DirectModelMetrics?
            if shouldUseDirectModelSmokeTest(for: primaryModelRef) {
                appendLog("Selected model uses a tool-free probe; running direct completion smoke test.")
                let result = try await runDirectModelSmokeTest(
                    modelRef: primaryModelRef,
                    environment: environment
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
            try OpenClawSettingsReader.writeEnvironment(entries: environmentEntries)
            try OpenClawSettingsReader.writeJSON(entries: jsonEntries)
            try OpenClawSettingsReader.writeWorkspaceFiles(workspaceFiles)
            reloadSettings()
            settingsStatusText = isRunning
                ? "Settings applied. Restart OpenClaw to apply process environment changes."
                : "Settings applied."
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
                profile: .notificationSpeech,
                modelRef: primaryModelRef,
                retrievalQuery: retrievalQuery
            )
            appendPromptDiagnostics(prompt.breakdown)
            let result = try await runDirectModelChat(
                modelRef: primaryModelRef,
                prompt: prompt.text,
                maxTokens: OpenClawTaskProfile.notificationSpeech.maxOutputTokens
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
                try prepareDirectories()
                let prompt = await layeredPrompt(
                    userMessage: message,
                    profile: .simpleChat,
                    modelRef: primaryModelRef,
                    retrievalQuery: .simpleChat(message)
                )
                appendPromptDiagnostics(prompt.breakdown)
                let requestedMaxTokens = min(OpenClawTaskProfile.simpleChat.maxOutputTokens, directMaxTokens(for: message))
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

    private func shouldResetChatSessionBeforeSending(_ message: String) -> Bool {
        guard let lastReply = latestAssistantReplyFromSession() else {
            return false
        }

        let normalizedReply = normalizedCommandText(lastReply)
        let staleReplyMarkers = [
            "Жду инструкций",
            "Waiting for your instructions",
            "Continue where I left off",
            "Continue where you left off",
            "fill SOUL.md",
            "SOUL.md",
            "What rules should I apply",
            "Can you clarify",
        ]
        return staleReplyMarkers
            .map(normalizedCommandText)
            .contains(where: { normalizedReply.contains($0) })
    }

    private func shouldResetCurrentSessionOnLaunch() -> Bool {
        guard let lastReply = latestAssistantReplyFromSession() else {
            return false
        }

        return looksLikeStaleAssistantReply(lastReply)
    }

    private func looksLikeStaleAssistantReply(_ reply: String) -> Bool {
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
            environment: ProcessInfo.processInfo.environment
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

    private func openClawEnvironment(
        configDirectory: URL? = nil,
        workspaceDirectory: URL? = nil,
        configPath: URL? = nil,
        stateDirectory: URL? = nil
    ) throws -> [String: String] {
        let configDirectory = configDirectory ?? self.configDirectory
        let workspaceDirectory = workspaceDirectory ?? self.workspaceDirectory
        let stateDirectory = stateDirectory ?? configDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")

        OpenClawLLMConfiguration.mergeEnvironmentSources(
            repositoryEnvURL: repositoryDirectory.appendingPathComponent(".env"),
            configEnvURL: configDirectory.appendingPathComponent(".env"),
            configURL: configDirectory.appendingPathComponent("openclaw.json"),
            into: &environment
        )

        environment["OPENCLAW_CONFIG_DIR"] = configDirectory.path
        environment["OPENCLAW_WORKSPACE_DIR"] = workspaceDirectory.path
        environment["OPENCLAW_STATE_DIR"] = stateDirectory.path
        if let configPath {
            environment["OPENCLAW_CONFIG_PATH"] = configPath.path
        } else {
            environment["OPENCLAW_CONFIG_PATH"] = configDirectory.appendingPathComponent("openclaw.json").path
        }
        environment["OPENCLAW_GATEWAY_BIND"] = "loopback"
        environment["OPENCLAW_GATEWAY_PORT"] = environment["OPENCLAW_GATEWAY_PORT"] ?? configuredGatewayPort(from: environment)
        environment["OPENCLAW_GATEWAY_URL"] = "ws://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)"
        environment["OPENCLAW_BRIDGE_PORT"] = environment["OPENCLAW_BRIDGE_PORT"] ?? "18790"
        environment["OPENCLAW_STREAM_BRIDGE_HOST"] = gatewayHost
        environment["OPENCLAW_STREAM_BRIDGE_PORT"] = streamBridgePort
        environment["OPENCLAW_STREAM_BRIDGE_URL"] = "http://\(gatewayHost):\(streamBridgePort)/api/control/speak"
        environment["OPENCLAW_TRACK_BRIDGE_URL"] = "http://\(gatewayHost):\(streamBridgePort)/track"
        environment["OPENCLAW_TRACK_ONLY_GROUPS"] = environment["OPENCLAW_TRACK_ONLY_GROUPS"] ?? "1"
        environment["OPENCLAW_TRACK_AUTO_LINKS"] = environment["OPENCLAW_TRACK_AUTO_LINKS"] ?? "1"
        environment["BROWSER"] = environment["BROWSER"] ?? "echo"
        return environment
    }

    private static func makeSettingsSnapshot(environment: [String: String]? = nil) -> OpenClawSettingsSnapshot {
        let controller = OpenClawSettingsReader(environment: environment)
        return controller.snapshot()
    }

    private var gatewayPort: String {
        configuredGatewayPort(from: ProcessInfo.processInfo.environment)
    }

    private func configuredGatewayPort(from environment: [String: String]) -> String {
        if let port = normalizedPort(environment["OPENCLAW_GATEWAY_PORT"]) {
            return port
        }
        if let port = configuredGatewayPortFromOpenClawJSON() {
            return port
        }
        return fallbackGatewayPort
    }

    private func configuredGatewayPortFromOpenClawJSON() -> String? {
        let configURL = configDirectory.appendingPathComponent("openclaw.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = object["gateway"] as? [String: Any] else {
            return nil
        }

        if let stringPort = gateway["port"] as? String {
            return normalizedPort(stringPort)
        }
        if let numericPort = gateway["port"] as? NSNumber {
            return normalizedPort(numericPort.stringValue)
        }
        return nil
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
            currentDirectoryURL: repositoryDirectory,
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
                self?.appendLog(text, prefix: name)
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
                } else if process === self?.localModelProcess {
                    self?.localModelProcess = nil
                    self?.endLocalModelPreparationIfNeeded(readyMessage: "Local model stopped")
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
        environment: [String: String]
    ) async throws -> DirectModelChatResult {
        return try await runDirectModelChat(
            modelRef: modelRef,
            prompt: "Reply with exactly: model test ok",
            environment: environment,
            maxTokens: 32
        )
    }

    private func runDirectModelChat(
        modelRef: String,
        prompt: String,
        environment: [String: String]? = nil,
        maxTokens: Int = 256,
        assistantMessageID: UUID? = nil,
        sampling: DirectModelSamplingOptions? = nil
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
        let effectiveMaxTokens = directModelMaxTokens(for: trimmedRef, requestedMaxTokens: maxTokens)
        let effectiveSampling = sampling ?? DirectModelSamplingOptions.standard(for: effectiveMaxTokens)
        if providerName == "ollama" {
            try await ensureDirectModelRuntimeReady(for: trimmedRef)
            return try await runDirectOllamaChat(
                modelID: providerModelID,
                prompt: prompt,
                maxTokens: effectiveMaxTokens,
                startedAt: startedAt,
                assistantMessageID: assistantMessageID,
                sampling: effectiveSampling
            )
        }
        if providerName == "mlx" {
            return try await runDirectMLXChat(
                modelID: providerModelID,
                prompt: prompt,
                maxTokens: effectiveMaxTokens,
                startedAt: startedAt,
                sampling: effectiveSampling
            )
        }
        throw OpenClawLocalControllerError.agentFailed(
            "Unsupported local model provider: \(providerName). Use `ollama/...` or `mlx/...`."
        )
    }

    private func currentPrimaryModelRef(in jsonEntries: [OpenClawEditableSetting]) -> String {
        if let value = jsonEntries.first(where: { $0.key == "agents.defaults.model.primary" })?.value
            ?? jsonEntries.first(where: { $0.key == "agents.defaults.model" })?.value {
            return OpenClawLLMConfiguration.migratedModelRef(value)
        }
        return OpenClawLLMConfiguration.localQwenModelRef
    }

    private func shouldUseDirectModelSmokeTest(for modelRef: String) -> Bool {
        let normalized = modelRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("ollama/")
            || normalized.hasPrefix("mlx/")
            || isLocalQwenModel(modelRef)
    }

    private func shouldUseDirectCompletion(for modelRef: String) -> Bool {
        shouldUseDirectModelSmokeTest(for: modelRef)
    }

    private func currentPrimaryModelRef() -> String {
        currentPrimaryModelRef(in: settingsSnapshot.jsonEntries)
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

        let suffix = profile.disableThinking && isLocalQwenModel(modelRef) ? "\n\n/no_think" : ""
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
        let environment = (try? openClawEnvironment()) ?? ProcessInfo.processInfo.environment
        return OpenClawQdrantClient.make(environment: environment)
    }

    func ensureLocalModelServer(modelRef: String? = nil, environment: [String: String]? = nil) async {
        let activeModelRef = OpenClawLLMConfiguration.migratedModelRef(modelRef ?? currentPrimaryModelRef())
        guard shouldAutoStartLocalModel(for: activeModelRef) else {
            return
        }

        let resolvedEnvironment = environment ?? (try? openClawEnvironment()) ?? ProcessInfo.processInfo.environment
        let provider = OpenClawLLMConfiguration.provider(forModelRef: activeModelRef)
        let baseURLString = provider?.baseURL ?? "http://127.0.0.1:8080/v1"
        guard let baseURL = URL(string: baseURLString) else {
            appendLog("Local MLX model server skipped: invalid base URL \(baseURLString).")
            return
        }

        if await localModelServerHasTargetModel(baseURL: baseURL, modelRef: activeModelRef) {
            appendLog("Local MLX model server is already available for \(activeModelRef).")
            endLocalModelPreparationIfNeeded(readyMessage: "Local model ready")
            return
        }

        guard localModelProcess == nil else {
            beginLocalModelPreparation("Preparing local model \(activeModelRef)...")
            appendLog("Waiting for local MLX model server to become ready for \(activeModelRef).")
            _ = await waitForLocalModelServer(baseURL: baseURL, modelRef: activeModelRef)
            return
        }

        if isLocalTCPPortAcceptingConnections(for: baseURL) {
            beginLocalModelPreparation("Preparing local model \(activeModelRef)...")
            appendLog("Local MLX port is already occupied; waiting for \(activeModelRef) instead of launching another server.")
            if await waitForLocalModelServer(baseURL: baseURL, modelRef: activeModelRef, timeoutSeconds: 30) {
                return
            }
            appendLog("Local MLX model server skipped: port \(baseURL.port ?? 8080) is occupied by a different or unhealthy service.")
            return
        }

        let modelID = activeModelRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .dropFirst()
            .first
            .map(String.init) ?? activeModelRef
        guard let model = OpenClawLLMConfiguration.localMLXModel(for: modelID) else {
            appendLog("Local MLX model server skipped: unsupported model \(modelID).")
            return
        }
        beginLocalModelPreparation(
            model.usesRapidMLX
                ? "Downloading or loading \(model.displayName)..."
                : "Preparing \(model.displayName)..."
        )
        do {
            try bootstrapMLXRuntimeIfNeeded(modelID: modelID)
        } catch {
            endLocalModelPreparationIfNeeded(readyMessage: "Local model unavailable")
            appendLog("Local MLX model bootstrap failed: \(error.localizedDescription)")
            return
        }

        guard let executableURL = resolveLocalMlxServerExecutableURL(model: model, environment: resolvedEnvironment) else {
            endLocalModelPreparationIfNeeded(readyMessage: "Local model unavailable")
            appendLog("Local MLX model server skipped: could not find rapid-mlx, mlx_lm.server, or python.")
            return
        }
        let modelPath: URL?
        if model.usesRapidMLX {
            modelPath = nil
        } else {
            guard let resolvedModelPath = resolveLocalMlxModelPath(modelRef: activeModelRef, environment: resolvedEnvironment) else {
                endLocalModelPreparationIfNeeded(readyMessage: "Local model unavailable")
                appendLog("Local MLX model server skipped: could not find a cached model directory for \(activeModelRef).")
                return
            }
            modelPath = resolvedModelPath
        }

        let arguments = localMlxServerArguments(executableURL: executableURL, model: model, modelPath: modelPath)
        do {
            localModelProcess = try launchExecutableProcess(
                name: "mlx-model",
                executableURL: executableURL,
                arguments: arguments,
                environment: resolvedEnvironment,
                updateRunningStateOnExit: false
            )
            let modelLocation = modelPath?.path ?? model.rapidAlias ?? model.id
            appendLog("Started local MLX model server for \(activeModelRef) using \(modelLocation).")
        } catch {
            localModelProcess = nil
            endLocalModelPreparationIfNeeded(readyMessage: "Local model unavailable")
            if isLocalTCPPortAcceptingConnections(for: baseURL) {
                appendLog("Local MLX model server start found an occupied port; waiting for \(activeModelRef).")
                _ = await waitForLocalModelServer(baseURL: baseURL, modelRef: activeModelRef, timeoutSeconds: 30)
            } else {
                appendLog("Local MLX model server start failed: \(error.localizedDescription)")
            }
            return
        }

        _ = await waitForLocalModelServer(baseURL: baseURL, modelRef: activeModelRef)
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

    private func runDirectOllamaChat(
        modelID: String,
        prompt: String,
        maxTokens: Int,
        startedAt: UInt64,
        assistantMessageID: UUID?,
        sampling: DirectModelSamplingOptions
    ) async throws -> DirectModelChatResult {
        let numCtx = maxTokens <= directVoiceTinyMaxTokens ? 2_048 : 4_096
        appendLog(
            "[latency] Direct Ollama request prepared; model=\(modelID), promptCharacters=\(prompt.count), maxTokens=\(maxTokens), numCtx=\(numCtx), think=false"
        )

        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            throw OpenClawLocalControllerError.agentFailed("Invalid Ollama API URL.")
        }

        let body: [String: Any] = [
            "model": modelID,
            "stream": true,
            "think": false,
            "keep_alive": "30m",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "options": [
                "num_ctx": numCtx,
                "num_predict": maxTokens,
                "temperature": sampling.temperature,
                "top_p": sampling.topP,
                "repeat_penalty": sampling.repeatPenalty
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = directModelTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let requestStartedAt = PerformanceLog.checkpoint()
        appendLog("[latency] Direct Ollama HTTP request starting.")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        appendLog("[latency] Direct Ollama HTTP response headers received in \(PerformanceLog.elapsedDescription(since: requestStartedAt))")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenClawLocalControllerError.agentFailed("Ollama returned a non-HTTP response.")
        }

        var replyBuffer = ""
        var rawLines: [String] = []
        var sawFirstToken = false
        var receivedDone = false
        var finalMetrics: DirectModelMetrics?

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            rawLines.append(line)
            guard let lineData = line.data(using: .utf8),
                  let decoded = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if let error = decoded["error"] as? String,
               !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw OpenClawLocalControllerError.agentFailed("Ollama error: \(error)")
            }

            if let message = decoded["message"] as? [String: Any],
               let chunk = message["content"] as? String,
               !chunk.isEmpty {
                replyBuffer.append(chunk)
                if let assistantMessageID {
                    updateChatMessage(id: assistantMessageID, text: replyBuffer)
                }
                if !sawFirstToken {
                    sawFirstToken = true
                    chatStatusText = "Receiving local reply..."
                    appendLog("[latency] Direct Ollama first token received in \(PerformanceLog.elapsedDescription(since: requestStartedAt))")
                }
            }

            if let done = decoded["done"] as? Bool, done {
                finalMetrics = DirectModelMetrics(
                    providerLabel: "ollama",
                    promptTokens: decoded["prompt_eval_count"] as? Int,
                    promptTokensPerSecond: Self.tokensPerSecond(
                        tokens: decoded["prompt_eval_count"] as? Int,
                        durationNanoseconds: decoded["prompt_eval_duration"] as? NSNumber
                    ),
                    generationTokens: decoded["eval_count"] as? Int,
                    generationTokensPerSecond: Self.tokensPerSecond(
                        tokens: decoded["eval_count"] as? Int,
                        durationNanoseconds: decoded["eval_duration"] as? NSNumber
                    ),
                    peakMemoryGB: nil
                )
                receivedDone = true
                break
            }
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyText = rawLines.joined(separator: "\n")
            throw OpenClawLocalControllerError.agentFailed(
                bodyText.isEmpty ? "Ollama HTTP \(httpResponse.statusCode)." : "Ollama HTTP \(httpResponse.statusCode): \(bodyText)"
            )
        }

        let reply = replyBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("Ollama returned an empty reply.")
        }

        if !receivedDone {
            appendLog("[latency] Direct Ollama stream ended without explicit done flag.")
        }
        appendLog("[latency] Direct Ollama answer decoded after \(PerformanceLog.elapsedDescription(since: startedAt)); replyCharacters=\(reply.count)")
        return DirectModelChatResult(text: reply, metrics: finalMetrics)
    }

    private func runDirectMLXChat(
        modelID: String,
        prompt: String,
        maxTokens: Int,
        startedAt: UInt64,
        sampling: DirectModelSamplingOptions
    ) async throws -> DirectModelChatResult {
        let model = try mlxModelConfiguration(for: modelID)
        if model.usesRapidMLX {
            return try await runDirectRapidMLXChat(
                model: model,
                prompt: prompt,
                maxTokens: maxTokens,
                startedAt: startedAt,
                sampling: sampling
            )
        }
        let pythonURL = try mlxPythonExecutableURL()
        let modelDirectory = try mlxModelDirectory(for: modelID)
        let promptFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gracula-mlx-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: promptFileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: promptFileURL)
        }

        let script = """
        import json
        import os
        from mlx_lm import load, stream_generate
        from mlx_lm.sample_utils import make_sampler

        model_path = os.environ["GRACULA_MLX_MODEL_PATH"]
        prompt_file = os.environ["GRACULA_MLX_PROMPT_FILE"]
        max_tokens = int(os.environ.get("GRACULA_MLX_MAX_TOKENS", "256"))
        temperature = float(os.environ.get("GRACULA_MLX_TEMPERATURE", "0"))
        top_p = float(os.environ.get("GRACULA_MLX_TOP_P", "0"))

        with open(prompt_file, "r", encoding="utf-8") as handle:
            user_prompt = handle.read()

        model, tokenizer = load(model_path)
        if getattr(tokenizer, "chat_template", None) is not None:
            rendered_prompt = tokenizer.apply_chat_template(
                [{"role": "user", "content": user_prompt}],
                add_generation_prompt=True,
                enable_thinking=False,
            )
        else:
            rendered_prompt = user_prompt

        sampler = make_sampler(temp=temperature, top_p=top_p)
        chunks = []
        final_metrics = None
        for response in stream_generate(
            model,
            tokenizer,
            rendered_prompt,
            max_tokens=max_tokens,
            sampler=sampler,
        ):
            if response.text:
                chunks.append(response.text)
            final_metrics = {
                "prompt_tokens": response.prompt_tokens,
                "prompt_tps": response.prompt_tps,
                "generation_tokens": response.generation_tokens,
                "generation_tps": response.generation_tps,
                "peak_memory": response.peak_memory,
                "finish_reason": response.finish_reason,
            }

        text = "".join(chunks).strip()
        if not text:
            raise RuntimeError("MLX returned an empty reply.")

        print(json.dumps({"text": text, "metrics": final_metrics}, ensure_ascii=False))
        """

        var environment = ProcessInfo.processInfo.environment
        environment["GRACULA_MLX_MODEL_PATH"] = modelDirectory.path
        environment["GRACULA_MLX_PROMPT_FILE"] = promptFileURL.path
        environment["GRACULA_MLX_MAX_TOKENS"] = String(maxTokens)
        environment["GRACULA_MLX_TEMPERATURE"] = String(sampling.temperature)
        environment["GRACULA_MLX_TOP_P"] = String(sampling.topP)

        appendLog(
            "[latency] Direct MLX request prepared; modelPath=\(modelDirectory.lastPathComponent), promptCharacters=\(prompt.count), maxTokens=\(maxTokens)"
        )
        let result = try await runExternalProcess(
            executableURL: pythonURL,
            arguments: ["-c", script],
            currentDirectoryURL: repositoryDirectory,
            environment: environment,
            timeoutSeconds: directMLXTimeoutSeconds
        )

        guard result.exitCode == 0 else {
            throw OpenClawLocalControllerError.agentFailed(
                result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = try? JSONDecoder().decode(DirectModelScriptResponse.self, from: Data(stdout.utf8)) else {
            throw OpenClawLocalControllerError.agentFailed("MLX returned an invalid JSON response.")
        }

        let reply = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("MLX returned an empty reply.")
        }

        let metrics = decoded.metrics.map {
            DirectModelMetrics(
                providerLabel: "mlx",
                promptTokens: $0.promptTokens,
                promptTokensPerSecond: $0.promptTokensPerSecond,
                generationTokens: $0.generationTokens,
                generationTokensPerSecond: $0.generationTokensPerSecond,
                peakMemoryGB: $0.peakMemoryGB
            )
        }
        appendLog("[latency] Direct MLX answer decoded after \(PerformanceLog.elapsedDescription(since: startedAt)); replyCharacters=\(reply.count)")
        return DirectModelChatResult(text: reply, metrics: metrics)
    }

    private func runDirectRapidMLXChat(
        model: OpenClawLocalMLXModelConfiguration,
        prompt: String,
        maxTokens: Int,
        startedAt: UInt64,
        sampling: DirectModelSamplingOptions
    ) async throws -> DirectModelChatResult {
        let environment = (try? openClawEnvironment()) ?? ProcessInfo.processInfo.environment
        let modelRef = model.modelRef
        await ensureLocalModelServer(modelRef: modelRef, environment: environment)

        guard let provider = OpenClawLLMConfiguration.provider(forModelRef: modelRef),
              let baseURL = URL(string: provider.baseURL) else {
            throw OpenClawLocalControllerError.agentFailed("Invalid Rapid-MLX base URL.")
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        let body: [String: Any] = [
            "model": model.id,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": maxTokens,
            "temperature": sampling.temperature,
            "top_p": sampling.topP,
            "frequency_penalty": max(0, sampling.repeatPenalty - 1.0),
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = directMLXTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        appendLog(
            "[latency] Rapid-MLX request prepared; model=\(model.id), promptCharacters=\(prompt.count), maxTokens=\(maxTokens)"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenClawLocalControllerError.agentFailed("Rapid-MLX returned a non-HTTP response.")
        }
        let responseText = String(decoding: data, as: UTF8.self)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenClawLocalControllerError.agentFailed(
                responseText.isEmpty ? "Rapid-MLX HTTP \(httpResponse.statusCode)." : "Rapid-MLX HTTP \(httpResponse.statusCode): \(responseText)"
            )
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenClawLocalControllerError.agentFailed("Rapid-MLX returned an invalid chat completion response.")
        }

        let reply = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("Rapid-MLX returned an empty reply.")
        }
        appendLog("[latency] Rapid-MLX answer decoded after \(PerformanceLog.elapsedDescription(since: startedAt)); replyCharacters=\(reply.count), text=\"\(logSnippet(reply))\"")
        return DirectModelChatResult(text: reply, metrics: nil)
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

    private func isLocalQwenModel(_ modelRef: String) -> Bool {
        let normalized = modelRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("qwen3") || normalized.contains("/qwen/")
    }

    private func shouldAutoStartLocalModel(for modelRef: String) -> Bool {
        OpenClawLLMConfiguration.provider(forModelRef: modelRef)?.name == "mlx"
    }

    private func localMlxServerArguments(
        executableURL: URL,
        model: OpenClawLocalMLXModelConfiguration,
        modelPath: URL?
    ) -> [String] {
        if executableURL.lastPathComponent == "rapid-mlx", let rapidAlias = model.rapidAlias {
            var arguments = [
                "serve",
                rapidAlias,
                "--served-model-name",
                model.id,
                "--host",
                "127.0.0.1",
                "--port",
                "8080",
                "--log-level",
                "WARNING",
                "--enable-auto-tool-choice",
                "--no-thinking"
            ]
            if let parser = model.rapidToolCallParser {
                arguments += ["--tool-call-parser", parser]
            }
            return arguments
        }

        guard let modelPath else {
            return []
        }
        let baseArguments = [
            "--model",
            modelPath.path,
            "--host",
            "127.0.0.1",
            "--port",
            "8080",
            "--use-default-chat-template",
            "--log-level",
            "INFO"
        ]
        if executableURL.lastPathComponent == "python3" {
            return ["-m", "mlx_lm.server"] + baseArguments
        }
        return baseArguments
    }

    private func resolveLocalMlxServerExecutableURL(
        model: OpenClawLocalMLXModelConfiguration,
        environment: [String: String]
    ) -> URL? {
        let candidates = [
            environment["GRACULA_RAPID_MLX_BIN"],
            environment["GRACULA_MLX_SERVER_BIN"],
            environment["OPENCLAW_MLX_SERVER_BIN"],
            environment["MLX_LM_SERVER_BIN"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(filePath: $0, directoryHint: .notDirectory) }

        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return found
        }

        if model.usesRapidMLX, let rapidURL = resolveRapidMLXExecutableURL() {
            return rapidURL
        }

        let defaultScript = mlxRuntimeDirectory
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("mlx_lm.server")
        if FileManager.default.fileExists(atPath: defaultScript.path) {
            return defaultScript
        }

        let pythonBinary = mlxRuntimeDirectory
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
        if FileManager.default.fileExists(atPath: pythonBinary.path) {
            return pythonBinary
        }

        return nil
    }

    private func resolveLocalMlxModelPath(modelRef: String, environment: [String: String]) -> URL? {
        let candidates = [
            environment["GRACULA_MLX_MODEL_PATH"],
            environment["OPENCLAW_MLX_MODEL_PATH"],
            environment["MLX_MODEL_PATH"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(filePath: $0, directoryHint: .isDirectory) }

        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return found
        }

        let modelID = modelRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .dropFirst()
            .first
            .map(String.init) ?? modelRef
        if let model = OpenClawLLMConfiguration.localMLXModel(for: modelID) {
            guard let localDirectoryName = model.localDirectoryName else {
                return nil
            }
            let modelDirectory = mlxModelsDirectory.appendingPathComponent(localDirectoryName, isDirectory: true)
            return FileManager.default.fileExists(atPath: modelDirectory.path) ? modelDirectory : nil
        }

        return nil
    }

    private func localModelServerHasTargetModel(baseURL: URL, modelRef: String) async -> Bool {
        guard isLocalTCPPortAcceptingConnections(for: baseURL) else {
            return false
        }

        let url = baseURL.appendingPathComponent("models")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            let text = String(decoding: data, as: UTF8.self)
            let modelName = modelRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).dropFirst().first.map(String.init) ?? modelRef
            return text.contains(modelName) || text.contains(modelRef)
        } catch {
            return false
        }
    }

    nonisolated private func isLocalTCPPortAcceptingConnections(for url: URL) -> Bool {
        guard let host = url.host,
              ["127.0.0.1", "localhost", "::1"].contains(host),
              let port = url.port else {
            return true
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
                ) == 0
            }
        }
    }

    private func directModelMaxTokens(for modelRef: String, requestedMaxTokens: Int) -> Int {
        return requestedMaxTokens
    }

    private func directMaxTokens(for message: String) -> Int {
        let normalizedCount = message.trimmingCharacters(in: .whitespacesAndNewlines).count
        if normalizedCount <= 12 {
            return directVoiceTinyMaxTokens
        }
        return normalizedCount <= 160 ? directVoiceShortMaxTokens : directVoiceNormalMaxTokens
    }

    private func ensureDirectModelRuntimeReady(for modelRef: String) async throws {
        let normalized = modelRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("mlx/") {
            try bootstrapMLXRuntimeIfNeeded(
                modelID: String(modelRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).last ?? "")
            )
        } else if normalized.hasPrefix("ollama/") {
            try await ensureOllamaModelAvailable(
                modelID: String(modelRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).last ?? "")
            )
        }
    }

    private func ensureOllamaModelAvailable(modelID: String) async throws {
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            return
        }
        if await ollamaHasModel(trimmedID) {
            return
        }
        guard let ollamaURL = resolveOllamaExecutableURL() else {
            throw OpenClawLocalControllerError.missingRuntime(
                "Ollama model \(trimmedID) is not available and the `ollama` executable was not found. Install Ollama or set PATH so the app can run `ollama pull \(trimmedID)` on first use."
            )
        }

        appendLog("Ollama model \(trimmedID) is missing; pulling it automatically.")
        let output = try runCommand(
            executableURL: ollamaURL,
            arguments: ["pull", trimmedID],
            currentDirectoryURL: configDirectory,
            environment: ProcessInfo.processInfo.environment
        )
        guard output.exitCode == 0 else {
            throw OpenClawLocalControllerError.missingRuntime(
                output.stderr.isEmpty ? output.stdout : output.stderr
            )
        }
        appendLog("Ollama model \(trimmedID) is ready.")
    }

    private func ollamaHasModel(_ modelID: String) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            return false
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = object["models"] as? [[String: Any]] else {
                return false
            }
            return models.contains { model in
                guard let name = model["name"] as? String else {
                    return false
                }
                return name == modelID || name.hasPrefix("\(modelID):")
            }
        } catch {
            return false
        }
    }

    private func bootstrapMLXRuntimeIfNeeded(modelID: String) throws {
        let model = try mlxModelConfiguration(for: modelID)
        if model.usesRapidMLX {
            guard resolveRapidMLXExecutableURL() != nil else {
                throw OpenClawLocalControllerError.missingRuntime(
                    "Rapid-MLX was not found. Install it with Homebrew or set GRACULA_RAPID_MLX_BIN before selecting \(model.displayName)."
                )
            }
            appendLog("Rapid-MLX runtime ready for \(model.id).")
            return
        }
        let existingPythonURL = try? mlxPythonExecutableURL()
        let existingModelDirectory = try? mlxModelDirectory(for: model.id)
        if let pythonURL = existingPythonURL, existingModelDirectory != nil {
            appendLog("MLX runtime ready at \(pythonURL.path); model=\(model.id).")
            return
        }

        try FileManager.default.createDirectory(at: mlxRuntimeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mlxModelsDirectory, withIntermediateDirectories: true)

        if (try? mlxPythonExecutableURL()) == nil {
            guard let systemPythonURL = resolveSystemPython3ExecutableURL() else {
                throw OpenClawLocalControllerError.missingRuntime(
                    "Python 3 was not found, so the MLX runtime cannot be prepared automatically."
                )
            }
            appendLog("MLX runtime is missing; creating Python virtual environment at \(mlxRuntimeDirectory.path).")
            try requireSuccessfulCommand(
                runCommand(
                    executableURL: systemPythonURL,
                    arguments: ["-m", "venv", mlxRuntimeDirectory.appendingPathComponent(".venv", isDirectory: true).path],
                    currentDirectoryURL: mlxRuntimeDirectory,
                    environment: ProcessInfo.processInfo.environment
                ),
                action: "create MLX Python virtual environment"
            )
        }

        let pythonURL = try mlxPythonExecutableURL()
        let pipURL = pythonURL.deletingLastPathComponent().appendingPathComponent("pip")
        appendLog("Installing MLX Python packages if needed.")
        try requireSuccessfulCommand(
            runCommand(
                executableURL: pythonURL,
                arguments: ["-m", "pip", "install", "--upgrade", "pip", "mlx-lm", "huggingface_hub"],
                currentDirectoryURL: mlxRuntimeDirectory,
                environment: ProcessInfo.processInfo.environment
            ),
            action: "install MLX Python packages"
        )
        if !FileManager.default.fileExists(atPath: pipURL.path) {
            appendLog("MLX pip executable was not created, but Python package installation completed through `python -m pip`.")
        }

        if (try? mlxModelDirectory(for: model.id)) == nil {
            guard let localDirectoryName = model.localDirectoryName,
                  let huggingFaceRepository = model.huggingFaceRepository else {
                throw OpenClawLocalControllerError.missingRuntime(
                    "MLX model \(model.id) does not define a local download target."
                )
            }
            let modelDirectory = mlxModelsDirectory.appendingPathComponent(localDirectoryName, isDirectory: true)
            let script = """
            import os
            from huggingface_hub import snapshot_download

            snapshot_download(
                repo_id=os.environ["GRACULA_MLX_REPOSITORY"],
                local_dir=os.environ["GRACULA_MLX_MODEL_DIR"],
                local_dir_use_symlinks=False,
            )
            """
            var environment = ProcessInfo.processInfo.environment
            environment["GRACULA_MLX_REPOSITORY"] = huggingFaceRepository
            environment["GRACULA_MLX_MODEL_DIR"] = modelDirectory.path
            appendLog("MLX model \(model.id) is missing; downloading \(huggingFaceRepository).")
            try requireSuccessfulCommand(
                runCommand(
                    executableURL: pythonURL,
                    arguments: ["-c", script],
                    currentDirectoryURL: mlxModelsDirectory,
                    environment: environment,
                    onOutput: { [weak self] text in
                        Task { @MainActor in
                            self?.appendLog(text, prefix: "download MLX model \(model.id)")
                        }
                    }
                ),
                action: "download MLX model \(model.id)"
            )
        }
    }

    private func mlxPythonExecutableURL() throws -> URL {
        let url = mlxRuntimeDirectory
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw OpenClawLocalControllerError.missingRuntime(
                "MLX runtime not found at \(url.path). Install it into Application Support before selecting the MLX backend."
            )
        }
        return url
    }

    private func mlxModelConfiguration(for modelID: String) throws -> OpenClawLocalMLXModelConfiguration {
        guard let model = OpenClawLLMConfiguration.localMLXModel(for: modelID) else {
            throw OpenClawLocalControllerError.missingRuntime(
                "Unsupported MLX model id: \(modelID). Add it to OpenClawLLMConfiguration.localMLXModels before selecting it."
            )
        }
        return model
    }

    private func mlxModelDirectory(for modelID: String) throws -> URL {
        let model = try mlxModelConfiguration(for: modelID)
        guard let localDirectoryName = model.localDirectoryName else {
            throw OpenClawLocalControllerError.missingRuntime(
                "MLX model \(model.id) is served by Rapid-MLX and does not use a Gracula model cache directory."
            )
        }
        let url = mlxModelsDirectory.appendingPathComponent(localDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let repository = model.huggingFaceRepository ?? model.id
            throw OpenClawLocalControllerError.missingRuntime(
                "MLX model files not found at \(url.path). The app will try to download \(repository) automatically on first use."
            )
        }
        return url
    }

    private func requireSuccessfulCommand(_ output: ProcessOutput, action: String) throws {
        guard output.exitCode == 0 else {
            let details = output.stderr.isEmpty ? output.stdout : output.stderr
            throw OpenClawLocalControllerError.missingRuntime(
                "Could not \(action). \(details.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        if !output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(output.stdout, prefix: action)
        }
        if !output.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(output.stderr, prefix: action)
        }
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

    private func waitForLocalModelServer(baseURL: URL, modelRef: String, timeoutSeconds: Int = 180) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if await localModelServerHasTargetModel(baseURL: baseURL, modelRef: modelRef) {
                endLocalModelPreparationIfNeeded(readyMessage: "Local model ready")
                appendLog("Local MLX model server is ready for \(modelRef).")
                return true
            }
            beginLocalModelPreparation("Waiting for local model server \(modelRef)...")
            try? await Task.sleep(for: .seconds(1))
        }
        endLocalModelPreparationIfNeeded(readyMessage: "Local model unavailable")
        appendLog("Local MLX model server did not become ready for \(modelRef) within \(timeoutSeconds)s.")
        return false
    }

    private func beginLocalModelPreparation(_ message: String) {
        isPreparingLocalModel = true
        localModelStatusText = message
        localModelPreparationProgress = nil
        statusText = message
        if isSendingChat {
            chatStatusText = message
        }
    }

    private func endLocalModelPreparationIfNeeded(readyMessage: String) {
        guard isPreparingLocalModel else {
            return
        }
        isPreparingLocalModel = false
        localModelPreparationProgress = nil
        localModelStatusText = readyMessage
        if statusText.contains("model") || statusText.contains("Model") || statusText.contains("Downloading") {
            statusText = isRunning ? readyMessage : statusText
        }
        if isSendingChat,
           chatStatusText.contains("model") || chatStatusText.contains("Model") || chatStatusText.contains("Downloading") {
            chatStatusText = readyMessage
        }
    }

    private func updateLocalModelPreparationProgress(from text: String, prefix: String?) {
        guard isPreparingLocalModel else {
            return
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if let percent = Self.firstPercentage(in: line) {
                localModelPreparationProgress = percent
                let percentValue = Int((percent * 100).rounded())
                localModelStatusText = "Downloading model... \(percentValue)%"
                statusText = localModelStatusText
                if isSendingChat {
                    chatStatusText = localModelStatusText
                }
                continue
            }

            if line.localizedCaseInsensitiveContains("Ready:") ||
                line.localizedCaseInsensitiveContains("runtime ready") ||
                line.localizedCaseInsensitiveContains("Local MLX model server is ready") {
                localModelPreparationProgress = 1
            }

            guard prefix == "mlx-model" || prefix?.contains("download MLX model") == true else {
                continue
            }

            if line.localizedCaseInsensitiveContains("downloading") ||
                line.localizedCaseInsensitiveContains("fetching") ||
                line.localizedCaseInsensitiveContains("loading") {
                localModelStatusText = line
                statusText = line
                if isSendingChat {
                    chatStatusText = line
                }
            }
        }
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
            currentDirectoryURL: repositoryDirectory,
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
        updateLocalModelPreparationProgress(from: text, prefix: prefix)
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
        guard processName == "mlx-model" else {
            return false
        }
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .allSatisfy { line in
                line.contains(#""GET /v1/models HTTP/1.1" 200"#)
                    || line.contains(#""GET /models HTTP/1.1" 200"#)
            }
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

    private static func firstPercentage(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,3})%"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captureRange = Range(match.range(at: 1), in: text),
              let value = Double(text[captureRange]),
              (0...100).contains(value) else {
            return nil
        }
        return value / 100
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

enum OpenClawSettingsApplyError: LocalizedError {
    case invalidJSONValue(String)
    case invalidJSONObject

    var errorDescription: String? {
        switch self {
        case let .invalidJSONValue(key):
            return "Invalid JSON value for \(key)."
        case .invalidJSONObject:
            return "openclaw.json must contain a JSON object."
        }
    }
}

struct OpenClawSettingsReader {
    private let repositoryDirectory = resolveOpenClawRepositoryDirectory()
    private let configDirectory = OpenClawRuntimePaths.configDirectory
    private let workspaceDirectory = OpenClawRuntimePaths.workspaceDirectory
    private let nodeURL = resolveNodeExecutableURL()
    private let gatewayHost = "127.0.0.1"
    private let fallbackGatewayPort = "18789"
    private let streamBridgePort = "7071"
    private let environment: [String: String]

    init(environment: [String: String]? = nil) {
        var mergedEnvironment = ProcessInfo.processInfo.environment
        OpenClawLLMConfiguration.mergeEnvironmentSources(
            repositoryEnvURL: repositoryDirectory.appendingPathComponent(".env"),
            configEnvURL: configDirectory.appendingPathComponent(".env"),
            configURL: configDirectory.appendingPathComponent("openclaw.json"),
            into: &mergedEnvironment
        )
        if let environment {
            mergedEnvironment.merge(environment) { _, newValue in newValue }
        }
        self.environment = mergedEnvironment
    }

    func snapshot() -> OpenClawSettingsSnapshot {
        let gatewayPort = configuredGatewayPort(from: environment)
        let runtimeRows = [
            row("Repository", repositoryDirectory.path),
            row("Node runtime", nodeURL.path),
            row("Gateway script", repositoryDirectory.appendingPathComponent("dist/index.js").path),
            row("Gateway URL", "http://\(gatewayHost):\(gatewayPort)/"),
            row("Gateway health", "http://\(gatewayHost):\(gatewayPort)/healthz"),
            row("Stream bridge health", "http://\(gatewayHost):\(streamBridgePort)/health"),
            row("Config file", configDirectory.appendingPathComponent("openclaw.json").path),
            row("Repo .env", repositoryDirectory.appendingPathComponent(".env").path),
            row("User .env", configDirectory.appendingPathComponent(".env").path)
        ]

        let permissionRows = [
            row("Gateway bind", environment["OPENCLAW_GATEWAY_BIND"] ?? "loopback"),
            row("Config directory", configDirectory.path),
            row("Workspace directory", workspaceDirectory.path),
            row("Canvas directory", configDirectory.appendingPathComponent("canvas", isDirectory: true).path),
            row("Cron directory", configDirectory.appendingPathComponent("cron", isDirectory: true).path),
            row("Browser launch", environment["BROWSER"] ?? "echo"),
            row("Track only groups", environment["OPENCLAW_TRACK_ONLY_GROUPS"] ?? "1"),
            row("Track auto links", environment["OPENCLAW_TRACK_AUTO_LINKS"] ?? "1")
        ]

        let environmentKeys = environment.keys
            .filter { key in
                key.hasPrefix("OPENCLAW_")
                    || key.hasPrefix("GRACULA_")
                    || key.hasPrefix("TELEGRAM_")
                    || key.hasPrefix("ONLYFANS_")
                    || key == "BROWSER"
            }
            .sorted()
        let environmentRows = environmentKeys.map { key in
            row(key, redacted(environment[key] ?? "", forKey: key))
        }
        let environmentEntries = environmentKeys.map { key in
            OpenClawEditableSetting(
                key: key,
                source: .environment,
                kind: .string,
                isSecret: isSecretKey(key),
                value: environment[key] ?? ""
            )
        }
        let jsonEntries = flattenJSONSettings()
        let workspaceFiles = readWorkspaceFiles()
        let configuredToolRows = jsonEntries
            .filter { entry in
                entry.key.hasPrefix("tools.")
                    || entry.key.hasPrefix("plugins.")
                    || entry.key.hasPrefix("hooks.")
                    || entry.key.hasPrefix("skills.")
            }
            .map { entry in
                row(entry.key, entry.isSecret ? "[redacted]" : entry.value)
            }
        let rapidMLXToolRows = OpenClawLLMConfiguration.localMLXModels
            .filter(\.usesRapidMLX)
            .flatMap { model in
                [
                    row("rapid-mlx.\(model.id).alias", model.rapidAlias ?? model.id),
                    row("rapid-mlx.\(model.id).tool-parser", model.rapidToolCallParser ?? "none"),
                    row("rapid-mlx.\(model.id).tools", model.rapidToolFeatures.isEmpty ? "none" : model.rapidToolFeatures.joined(separator: ", "))
                ]
            }
        let toolRows = configuredToolRows + rapidMLXToolRows

        return OpenClawSettingsSnapshot(
            runtimeRows: runtimeRows,
            permissionRows: permissionRows,
            environmentRows: environmentRows,
            toolRows: toolRows,
            environmentEntries: environmentEntries,
            jsonEntries: jsonEntries,
            workspaceFiles: workspaceFiles
        )
    }

    static func writeEnvironment(entries: [OpenClawEditableSetting]) throws {
        let url = resolveOpenClawRepositoryDirectory().appendingPathComponent(".env")
        try writeEnvironment(entries: entries, to: url)
    }

    static func writeEnvironment(entries: [OpenClawEditableSetting], to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent(".env.bak.\(backupTimestamp())")
            try? fileManager.copyItem(at: url, to: backupURL)
        }

        let lines = entries
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(escapedEnvValue($0.value))" }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeJSON(entries: [OpenClawEditableSetting]) throws {
        try writeJSON(entries: entries, to: OpenClawRuntimePaths.configURL)
    }

    static func writeJSON(entries: [OpenClawEditableSetting], to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("openclaw.json.bak.\(backupTimestamp())")
            try? fileManager.copyItem(at: url, to: backupURL)
        }

        let normalizedEntries = OpenClawLLMConfiguration.entriesWithProviderDefaults(entries)
        let rootObject: NSMutableDictionary
        if let data = try? Data(contentsOf: url),
           !data.isEmpty,
           let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rootObject = NSMutableDictionary(dictionary: object)
        } else {
            rootObject = NSMutableDictionary()
        }

        for entry in normalizedEntries {
            guard let value = try jsonValue(from: entry) else {
                continue
            }
            setJSONValue(value, forPath: entry.key, in: rootObject)
        }

        guard JSONSerialization.isValidJSONObject(rootObject) else {
            throw OpenClawSettingsApplyError.invalidJSONObject
        }
        let data = try JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    static func writeWorkspaceFiles(_ files: [OpenClawWorkspaceFile]) throws {
        try writeWorkspaceFiles(files, to: OpenClawRuntimePaths.workspaceDirectory)
    }

    static func writeWorkspaceFiles(_ files: [OpenClawWorkspaceFile], to workspaceDirectory: URL) throws {
        let fileManager = FileManager.default
        for file in files {
            guard isEditableWorkspaceFile(file.relativePath) else {
                continue
            }
            let url = workspaceDirectory.appendingPathComponent(file.relativePath)
            if fileManager.fileExists(atPath: url.path) {
                let backupURL = url.deletingLastPathComponent()
                    .appendingPathComponent("\(url.lastPathComponent).bak.\(backupTimestamp())")
                try? fileManager.copyItem(at: url, to: backupURL)
            }
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func row(_ name: String, _ value: String) -> OpenClawSettingsRow {
        OpenClawSettingsRow(id: name, name: name, value: value.isEmpty ? "Not set" : value)
    }

    private func flattenJSONSettings() -> [OpenClawEditableSetting] {
        let configURL = configDirectory.appendingPathComponent("openclaw.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var entries: [OpenClawEditableSetting] = []
        flattenJSONValue(object, prefix: "", into: &entries)
        return entries.sorted { $0.key < $1.key }
    }

    private func readWorkspaceFiles() -> [OpenClawWorkspaceFile] {
        let workspaceURL = workspaceDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: workspaceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let discoveredNames = urls
            .map(\.lastPathComponent)
            .filter(Self.isEditableWorkspaceFile)
        let names = Set(discoveredNames)
            .union(Self.coreEditableWorkspaceFileNames)
            .sorted()

        return names.map { name in
            let url = workspaceURL.appendingPathComponent(name)
            let existsOnDisk = FileManager.default.fileExists(atPath: url.path)
            let contents = (try? String(contentsOf: url)) ?? ""
            let byteCount = (try? Data(contentsOf: url).count) ?? 0
            return OpenClawWorkspaceFile(
                relativePath: name,
                absolutePath: url.path,
                existsOnDisk: existsOnDisk,
                byteCount: byteCount,
                contents: contents
            )
        }
    }

    private func flattenJSONValue(_ value: Any, prefix: String, into entries: inout [OpenClawEditableSetting]) {
        if let dictionary = value as? [String: Any], !dictionary.isEmpty {
            for key in dictionary.keys.sorted() {
                let nextPrefix = prefix.isEmpty ? key : "\(prefix).\(key)"
                flattenJSONValue(dictionary[key] as Any, prefix: nextPrefix, into: &entries)
            }
            return
        }

        let kind = valueKind(for: value)
        entries.append(
            OpenClawEditableSetting(
                key: prefix,
                source: .json,
                kind: kind,
                isSecret: isSecretKey(prefix),
                value: editableString(for: value, kind: kind)
            )
        )
    }

    private func valueKind(for value: Any) -> OpenClawEditableSetting.ValueKind {
        switch value {
        case is NSNull:
            return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool
            }
            return floor(number.doubleValue) == number.doubleValue ? .int : .double
        case is String:
            return .string
        case is [Any]:
            return .array
        case is [String: Any]:
            return .object
        default:
            return .string
        }
    }

    private func editableString(for value: Any, kind: OpenClawEditableSetting.ValueKind) -> String {
        switch kind {
        case .null:
            return "null"
        case .bool, .int, .double:
            return "\(value)"
        case .string:
            return value as? String ?? "\(value)"
        case .array, .object:
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  let string = String(data: data, encoding: .utf8) else {
                return "\(value)"
            }
            return string
        }
    }

    private func configuredGatewayPort(from environment: [String: String]) -> String {
        if let port = normalizedPort(environment["OPENCLAW_GATEWAY_PORT"]) {
            return port
        }
        if let port = configuredGatewayPortFromOpenClawJSON() {
            return port
        }
        return fallbackGatewayPort
    }

    private func configuredGatewayPortFromOpenClawJSON() -> String? {
        let configURL = configDirectory.appendingPathComponent("openclaw.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = object["gateway"] as? [String: Any] else {
            return nil
        }

        if let stringPort = gateway["port"] as? String {
            return normalizedPort(stringPort)
        }
        if let numericPort = gateway["port"] as? NSNumber {
            return normalizedPort(numericPort.stringValue)
        }
        return nil
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

    private func redacted(_ value: String, forKey key: String) -> String {
        guard !value.isEmpty else {
            return "Not set"
        }
        if isSecretKey(key) {
            return "[redacted]"
        }
        if value.count > 80 {
            return String(value.prefix(77)) + "..."
        }
        return value
    }

    private func isSecretKey(_ key: String) -> Bool {
        key.range(of: #"(?i)(token|secret|key|cookie|authorization|password|apiKey|api_key)"#, options: .regularExpression) != nil
    }

    private static func isSecretKey(_ key: String) -> Bool {
        key.range(of: #"(?i)(token|secret|key|cookie|authorization|password|apiKey|api_key)"#, options: .regularExpression) != nil
    }

    private static func escapedEnvValue(_ value: String) -> String {
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           !value.contains("#"),
           !value.contains("\""),
           !value.contains("'") {
            return value
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func jsonValue(from entry: OpenClawEditableSetting) throws -> Any? {
        let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch entry.kind {
        case .string:
            return entry.value
        case .bool:
            guard !trimmed.isEmpty else {
                return nil
            }
            if ["true", "1", "yes"].contains(trimmed.lowercased()) {
                return true
            }
            if ["false", "0", "no"].contains(trimmed.lowercased()) {
                return false
            }
            return nil
        case .int:
            guard !trimmed.isEmpty else {
                return nil
            }
            guard let value = Int(trimmed) else {
                return nil
            }
            return value
        case .double:
            guard !trimmed.isEmpty else {
                return nil
            }
            guard let value = Double(trimmed) else {
                return nil
            }
            return value
        case .null:
            return NSNull()
        case .array, .object:
            guard !trimmed.isEmpty else {
                return nil
            }
            guard let data = trimmed.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            return value
        }
    }

    private static func setJSONValue(_ value: Any, forPath path: String, in root: NSMutableDictionary) {
        let components = path.split(separator: ".").map(String.init)
        guard let last = components.last else {
            return
        }
        var current = root
        for component in components.dropLast() {
            if let existing = current[component] as? NSMutableDictionary {
                current = existing
            } else if let existing = current[component] as? [String: Any] {
                let dictionary = NSMutableDictionary(dictionary: existing)
                current[component] = dictionary
                current = dictionary
            } else {
                let dictionary = NSMutableDictionary()
                current[component] = dictionary
                current = dictionary
            }
        }
        current[last] = value
    }

    private static func isEditableWorkspaceFile(_ relativePath: String) -> Bool {
        guard !relativePath.contains("/"),
              relativePath.hasSuffix(".md") || relativePath.hasSuffix(".txt") else {
            return false
        }
        return coreEditableWorkspaceFileNames.contains(relativePath)
            || relativePath.hasPrefix("IDENTITY")
            || relativePath.hasPrefix("SOUL")
            || relativePath.hasPrefix("AGENT")
            || relativePath.hasPrefix("TOOL")
    }

    private static let coreEditableWorkspaceFileNames: Set<String> = [
            "AGENTS.md",
            "BOOTSTRAP.md",
            "HEARTBEAT.md",
            "IDENTITY.md",
            "IDENTITY-female.md",
            "MEMORY.md",
            "SOUL.md",
            "TOOLS.md",
            "USER.md",
            "memory_summary.md",
            "persona_compact.md",
            "rag_excerpts.md"
        ]
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

    if let override = env["GRACULA_PROJECT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        return URL(filePath: override, directoryHint: .isDirectory)
    }

    let currentDirectory = URL(filePath: fileManager.currentDirectoryPath, directoryHint: .isDirectory)
    var candidate = currentDirectory.standardizedFileURL
    while candidate.path != "/" {
        if fileManager.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path),
           fileManager.fileExists(atPath: candidate.appendingPathComponent("Examples", isDirectory: true).path) {
            return candidate
        }
        candidate = candidate.deletingLastPathComponent()
    }

    return fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Gracula", isDirectory: true)
}

private func resolveMLXRuntimeDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("GraculaExample", isDirectory: true)
        .appendingPathComponent("MLXRuntime", isDirectory: true)
}

private func resolveMLXModelsDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("GraculaExample", isDirectory: true)
        .appendingPathComponent("MLXModels", isDirectory: true)
}

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

private func resolveSystemPython3ExecutableURL() -> URL? {
    resolveExecutableURL(
        environmentKey: "GRACULA_PYTHON3_EXECUTABLE",
        candidates: [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
    )
}

private func resolveOllamaExecutableURL() -> URL? {
    resolveExecutableURL(
        environmentKey: "GRACULA_OLLAMA_EXECUTABLE",
        candidates: [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/usr/bin/ollama"
        ]
    )
}

private func resolveRapidMLXExecutableURL() -> URL? {
    resolveExecutableURL(
        environmentKey: "GRACULA_RAPID_MLX_BIN",
        candidates: [
            "/opt/homebrew/bin/rapid-mlx",
            "/usr/local/bin/rapid-mlx",
            "/usr/bin/rapid-mlx"
        ]
    )
}

private func resolveExecutableURL(environmentKey: String, candidates: [String]) -> URL? {
    let fileManager = FileManager.default
    let env = ProcessInfo.processInfo.environment
    if let override = env[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        let url = URL(filePath: override)
        if fileManager.isExecutableFile(atPath: url.path) {
            return url
        }
    }
    for candidate in candidates {
        let url = URL(filePath: candidate)
        if fileManager.isExecutableFile(atPath: url.path) {
            return url
        }
    }
    return nil
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

private struct DirectModelSamplingOptions {
    let temperature: Double
    let topP: Double
    let repeatPenalty: Double

    static func standard(for maxTokens: Int) -> DirectModelSamplingOptions {
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
