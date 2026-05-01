import Foundation

public struct LightweightTaskProfile: Sendable, Equatable {
    public let name: String
    public let runtimeContextWindow: Int
    public let maxOutputTokens: Int
    public let reserveTokens: Int
    public let maxHistoryMessages: Int
    public let maxMemoryTokens: Int
    public let maxRetrievedSnippets: Int
    public let maxRetrievedTokens: Int
    public let personaCompactTokens: Int
    public let userNotificationTokens: Int
    public let disableThinking: Bool

    public static let notificationSpeech = LightweightTaskProfile(
        name: "notification_speech",
        runtimeContextWindow: 4096,
        maxOutputTokens: 128,
        reserveTokens: 512,
        maxHistoryMessages: 0,
        maxMemoryTokens: 0,
        maxRetrievedSnippets: 2,
        maxRetrievedTokens: 600,
        personaCompactTokens: 500,
        userNotificationTokens: 2500,
        disableThinking: true
    )

    public static let simpleChat = LightweightTaskProfile(
        name: "simple_chat",
        runtimeContextWindow: 8192,
        maxOutputTokens: 512,
        reserveTokens: 1024,
        maxHistoryMessages: 6,
        maxMemoryTokens: 800,
        maxRetrievedSnippets: 3,
        maxRetrievedTokens: 1000,
        personaCompactTokens: 500,
        userNotificationTokens: 0,
        disableThinking: true
    )

    public static let deepPersona = LightweightTaskProfile(
        name: "deep_persona",
        runtimeContextWindow: 32768,
        maxOutputTokens: 2048,
        reserveTokens: 4096,
        maxHistoryMessages: 20,
        maxMemoryTokens: 2000,
        maxRetrievedSnippets: 6,
        maxRetrievedTokens: 5000,
        personaCompactTokens: 500,
        userNotificationTokens: 0,
        disableThinking: false
    )
}

public struct LightweightRetrievedSnippet: Sendable, Equatable {
    public let id: String
    public let source: String
    public let kind: String
    public let profile: String
    public let score: Double
    public let tokenEstimate: Int
    public let text: String

    public init(
        id: String,
        source: String,
        kind: String,
        profile: String,
        score: Double,
        tokenEstimate: Int,
        text: String
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.profile = profile
        self.score = score
        self.tokenEstimate = tokenEstimate
        self.text = text
    }
}

public struct LightweightPromptDiagnostics: Sendable, Equatable {
    public let taskProfile: String
    public let systemTokens: Int
    public let userTokens: Int
    public let historyTokens: Int
    public let workspaceTokens: Int
    public let toolsSkillsTokens: Int
    public let memoryTokens: Int
    public let ragTokens: Int
    public let totalPromptTokens: Int
    public let runtimeContextWindow: Int
    public let maxOutputTokens: Int
    public let reserveTokens: Int
    public let shrinkingApplied: Bool
    public let dropped: [String]
    public let retrievedSnippetIDs: [String]
    public let retrievedSnippetSources: [String]
    public let retrievedSnippetScores: [Double]
    public let retrievedTokenCount: Int
}

public struct LightweightPromptResult: Sendable, Equatable {
    public let text: String
    public let maxOutputTokens: Int
    public let diagnostics: LightweightPromptDiagnostics
}

public struct LightweightNotificationInput: Sendable, Equatable {
    public let app: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let channel: String?
    public let fallbackSpokenText: String?

    public init(
        app: String,
        title: String,
        subtitle: String = "",
        body: String,
        channel: String? = nil,
        fallbackSpokenText: String? = nil
    ) {
        self.app = app
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.channel = channel
        self.fallbackSpokenText = fallbackSpokenText
    }
}

public struct LightweightPromptCompiler: Sendable {
    public init() {}

    public func buildNotificationSpeechPrompt(
        personaCompact: String,
        notification: LightweightNotificationInput,
        retrievedSnippets: [LightweightRetrievedSnippet],
        modelRef: String
    ) -> LightweightPromptResult {
        let profile = LightweightTaskProfile.notificationSpeech
        let persona = limitedTokens(personaCompact, maxTokens: profile.personaCompactTokens)
        var selectedSnippets = selectedRetrievedSnippets(retrievedSnippets, profile: profile)
        var dropped: [String] = []
        var retrieved = retrievedText(selectedSnippets)
        var userBlock = notificationBlock(notification, includeSubtitle: true, includeChannel: true, includeFallback: true)
        userBlock = limitedTokens(userBlock, maxTokens: profile.userNotificationTokens)

        let suffix = shouldDisableThinking(modelRef: modelRef, profile: profile) ? "\n\n/no_think" : ""
        var sections = [
            section("persona_compact", persona),
            section("retrievedMemory", retrieved),
            section("user", userBlock + suffix)
        ].filter { !$0.text.isEmpty }
        var prompt = join(sections)
        let promptBudget = profile.runtimeContextWindow - profile.reserveTokens - profile.maxOutputTokens
        var shrinkingApplied = false

        if estimatedTokens(prompt) > promptBudget {
            shrinkingApplied = true
            selectedSnippets = []
            retrieved = ""
            dropped.append("Qdrant snippets")
            sections = [
                section("persona_compact", persona),
                section("user", userBlock + suffix)
            ].filter { !$0.text.isEmpty }
            prompt = join(sections)
        }

        if estimatedTokens(prompt) > promptBudget {
            shrinkingApplied = true
            userBlock = notificationBlock(notification, includeSubtitle: true, includeChannel: true, includeFallback: false)
            userBlock = limitedTokens(userBlock, maxTokens: profile.userNotificationTokens)
            dropped.append("fallback spoken text")
            prompt = join([section("persona_compact", persona), section("user", userBlock + suffix)])
        }

        if estimatedTokens(prompt) > promptBudget {
            shrinkingApplied = true
            userBlock = notificationBlock(notification, includeSubtitle: false, includeChannel: false, includeFallback: false)
            userBlock = limitedTokens(userBlock, maxTokens: profile.userNotificationTokens)
            dropped.append("extra notification metadata")
            prompt = join([section("persona_compact", persona), section("user", userBlock + suffix)])
        }

        if estimatedTokens(prompt) > promptBudget {
            shrinkingApplied = true
            userBlock = minimalNotificationBlock(notification)
            prompt = join([section("persona_compact", persona), section("user", userBlock + suffix)])
        }

        let diagnostics = diagnostics(
            profile: profile,
            prompt: prompt,
            persona: persona,
            user: userBlock + suffix,
            history: "",
            memory: "",
            rag: retrieved,
            snippets: selectedSnippets,
            shrinkingApplied: shrinkingApplied,
            dropped: dropped
        )
        return LightweightPromptResult(text: prompt, maxOutputTokens: profile.maxOutputTokens, diagnostics: diagnostics)
    }

    public func buildSimpleChatPrompt(
        personaCompact: String,
        message: String,
        history: [String],
        memorySummary: String,
        retrievedSnippets: [LightweightRetrievedSnippet],
        modelRef: String
    ) -> LightweightPromptResult {
        let profile = LightweightTaskProfile.simpleChat
        let persona = limitedTokens(personaCompact, maxTokens: profile.personaCompactTokens)
        let historyText = history.suffix(profile.maxHistoryMessages).joined(separator: "\n")
        let memory = limitedTokens(memorySummary, maxTokens: profile.maxMemoryTokens)
        let snippets = selectedRetrievedSnippets(retrievedSnippets, profile: profile)
        let retrieved = retrievedText(snippets)
        let suffix = shouldDisableThinking(modelRef: modelRef, profile: profile) ? "\n\n/no_think" : ""
        var dropped: [String] = []
        var sections = [
            section("persona_compact", persona),
            section("memorySummary", memory),
            section("history", historyText),
            section("retrievedMemory", retrieved),
            section("user", message + suffix)
        ].filter { !$0.text.isEmpty }
        var prompt = join(sections)
        let promptBudget = profile.runtimeContextWindow - profile.reserveTokens - profile.maxOutputTokens
        var shrinkingApplied = false

        if estimatedTokens(prompt) > promptBudget {
            shrinkingApplied = true
            dropped.append("Qdrant snippets")
            sections.removeAll { $0.name == "retrievedMemory" }
            prompt = join(sections)
        }
        if estimatedTokens(prompt) > promptBudget {
            shrinkingApplied = true
            dropped.append("history")
            sections.removeAll { $0.name == "history" }
            prompt = join(sections)
        }

        let diagnostics = diagnostics(
            profile: profile,
            prompt: prompt,
            persona: persona,
            user: message + suffix,
            history: sections.first(where: { $0.name == "history" })?.text ?? "",
            memory: memory,
            rag: sections.first(where: { $0.name == "retrievedMemory" })?.text ?? "",
            snippets: snippets,
            shrinkingApplied: shrinkingApplied,
            dropped: dropped
        )
        return LightweightPromptResult(text: prompt, maxOutputTokens: profile.maxOutputTokens, diagnostics: diagnostics)
    }

    private func selectedRetrievedSnippets(
        _ snippets: [LightweightRetrievedSnippet],
        profile: LightweightTaskProfile
    ) -> [LightweightRetrievedSnippet] {
        var selected: [LightweightRetrievedSnippet] = []
        var tokens = 0
        for snippet in snippets.sorted(by: { $0.score > $1.score }) {
            guard selected.count < profile.maxRetrievedSnippets else { break }
            let snippetTokens = min(snippet.tokenEstimate, estimatedTokens(snippet.text))
            guard tokens + snippetTokens <= profile.maxRetrievedTokens else { continue }
            selected.append(snippet)
            tokens += snippetTokens
        }
        return selected
    }

    private func retrievedText(_ snippets: [LightweightRetrievedSnippet]) -> String {
        snippets.map { snippet in
            "[source=\(snippet.source), kind=\(snippet.kind), score=\(String(format: "%.3f", snippet.score))]\n\(snippet.text)"
        }.joined(separator: "\n\n")
    }

    private func notificationBlock(
        _ notification: LightweightNotificationInput,
        includeSubtitle: Bool,
        includeChannel: Bool,
        includeFallback: Bool
    ) -> String {
        var lines = [
            "Task: produce one short Russian phrase suitable for speech. Preserve names, numbers, apps, channels, and meaning. Do not mention prompts, RAG, databases, tools, or internal details.",
            "App: \(notification.app)",
            "Title: \(notification.title)"
        ]
        if includeSubtitle, !notification.subtitle.isEmpty {
            lines.append("Subtitle: \(notification.subtitle)")
        }
        if includeChannel, let channel = notification.channel, !channel.isEmpty {
            lines.append("Channel: \(channel)")
        }
        lines.append("Body: \(notification.body)")
        if includeFallback, let fallback = notification.fallbackSpokenText, !fallback.isEmpty {
            lines.append("Fallback spoken text: \(fallback)")
        }
        return lines.joined(separator: "\n")
    }

    private func minimalNotificationBlock(_ notification: LightweightNotificationInput) -> String {
        [
            "Task: produce one short Russian phrase suitable for speech. Preserve names, numbers, apps, channels, and meaning.",
            "App: \(notification.app)",
            "Title: \(notification.title)",
            "Body: \(limitedTokens(notification.body, maxTokens: 2200))"
        ].joined(separator: "\n")
    }

    private struct Section {
        let name: String
        let text: String
    }

    private func section(_ name: String, _ text: String) -> Section {
        Section(name: name, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func join(_ sections: [Section]) -> String {
        sections.map { "## \($0.name)\n\($0.text)" }.joined(separator: "\n\n")
    }

    private func diagnostics(
        profile: LightweightTaskProfile,
        prompt: String,
        persona: String,
        user: String,
        history: String,
        memory: String,
        rag: String,
        snippets: [LightweightRetrievedSnippet],
        shrinkingApplied: Bool,
        dropped: [String]
    ) -> LightweightPromptDiagnostics {
        LightweightPromptDiagnostics(
            taskProfile: profile.name,
            systemTokens: estimatedTokens(persona),
            userTokens: estimatedTokens(user),
            historyTokens: history.isEmpty ? 0 : estimatedTokens(history),
            workspaceTokens: 0,
            toolsSkillsTokens: 0,
            memoryTokens: memory.isEmpty ? 0 : estimatedTokens(memory),
            ragTokens: rag.isEmpty ? 0 : estimatedTokens(rag),
            totalPromptTokens: estimatedTokens(prompt),
            runtimeContextWindow: profile.runtimeContextWindow,
            maxOutputTokens: profile.maxOutputTokens,
            reserveTokens: profile.reserveTokens,
            shrinkingApplied: shrinkingApplied,
            dropped: dropped,
            retrievedSnippetIDs: snippets.map(\.id),
            retrievedSnippetSources: snippets.map(\.source),
            retrievedSnippetScores: snippets.map(\.score),
            retrievedTokenCount: snippets.reduce(0) { $0 + min($1.tokenEstimate, estimatedTokens($1.text)) }
        )
    }
}

public struct LightweightNotificationCacheEntry: Sendable, Equatable {
    public let app: String
    public let title: String
    public let body: String
    public let spokenText: String
    public let decision: String

    public init(app: String, title: String, body: String, spokenText: String, decision: String) {
        self.app = app
        self.title = title
        self.body = body
        self.spokenText = spokenText
        self.decision = decision
    }
}

public enum LightweightNotificationCacheDecision: Sendable, Equatable {
    case none
    case reuseSpokenText(String)
    case reuseSkip(String)
    case useAsExample(String)
}

public struct LightweightNotificationCacheGate: Sendable {
    public init() {}

    public func decision(
        notification: LightweightNotificationInput,
        entries: [LightweightNotificationCacheEntry],
        highThreshold: Double = 0.72,
        exampleThreshold: Double = 0.54
    ) -> LightweightNotificationCacheDecision {
        let query = "\(notification.app) \(notification.title) \(notification.body)"
        let queryTokens = lexicalTokens(query)
        guard let best = entries.max(by: {
            similarity(queryTokens, $0) < similarity(queryTokens, $1)
        }) else {
            return .none
        }

        let score = similarity(queryTokens, best)
        if score >= highThreshold {
            if best.decision == "skip" {
                return .reuseSkip(best.spokenText.isEmpty ? "Пропускаю шумное уведомление." : best.spokenText)
            }
            return .reuseSpokenText(best.spokenText)
        }
        if score >= exampleThreshold, best.decision == "speak", !best.spokenText.isEmpty {
            return .useAsExample(best.spokenText)
        }
        return .none
    }

    private func similarity(_ queryTokens: Set<String>, _ entry: LightweightNotificationCacheEntry) -> Double {
        let entryTokens = lexicalTokens("\(entry.app) \(entry.title) \(entry.body)")
        guard !queryTokens.isEmpty, !entryTokens.isEmpty else {
            return 0
        }
        let intersection = queryTokens.intersection(entryTokens).count
        let union = queryTokens.union(entryTokens).count
        return Double(intersection) / Double(max(1, union))
    }
}

public func estimatedTokens(_ text: String) -> Int {
    max(1, Int(ceil(Double(text.count) / 4.0)))
}

public func limitedTokens(_ text: String, maxTokens: Int) -> String {
    let maxCharacters = max(0, maxTokens * 4)
    guard text.count > maxCharacters else {
        return text
    }
    return String(text.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
}

public func shouldDisableThinking(modelRef: String, profile: LightweightTaskProfile) -> Bool {
    guard profile.disableThinking else {
        return false
    }
    let normalized = modelRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.contains("qwen3") || normalized.contains("/qwen/")
}

private func lexicalTokens(_ text: String) -> Set<String> {
    let normalized = text
        .precomposedStringWithCanonicalMapping
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
        .lowercased()
        .replacingOccurrences(of: "ё", with: "е")
    return Set(normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 })
}
