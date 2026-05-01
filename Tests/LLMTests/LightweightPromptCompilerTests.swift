import LLM
import Testing

@Test
func notificationSpeechPromptStaysSmallAndExcludesHeavyContext() {
    let compiler = LightweightPromptCompiler()
    let notification = LightweightNotificationInput(
        app: "org.telegram.desktop",
        title: "XOR",
        subtitle: "TapMap",
        body: "В канал TapMap пришло 3 новых сообщения про сборку.",
        channel: "TapMap",
        fallbackSpokenText: "XOR написал в TapMap."
    )
    let snippets = (0..<8).map { index in
        LightweightRetrievedSnippet(
            id: "snippet-\(index)",
            source: "fixture-\(index)",
            kind: "notification_example",
            profile: "notification_speech",
            score: 0.9 - Double(index) * 0.01,
            tokenEstimate: 120,
            text: String(repeating: "пример речи ", count: 40)
        )
    }

    let result = compiler.buildNotificationSpeechPrompt(
        personaCompact: String(repeating: "Gracula говорит коротко. ", count: 70),
        notification: notification,
        retrievedSnippets: snippets,
        modelRef: "mlx/Qwen/Qwen3-30B-A3B-MLX-4bit"
    )

    #expect(result.diagnostics.totalPromptTokens < 2_000)
    #expect(result.diagnostics.totalPromptTokens < 4_096)
    #expect(result.diagnostics.systemTokens <= 500)
    #expect(result.diagnostics.retrievedSnippetIDs.count <= 2)
    #expect(result.diagnostics.retrievedTokenCount <= 600)
    #expect(result.maxOutputTokens <= 128)
    #expect(result.text.contains("/no_think"))
    #expect(result.text.contains("App: org.telegram.desktop"))
    #expect(result.text.contains("Title: XOR"))
    #expect(result.text.contains("Body: В канал TapMap"))
    #expect(!result.text.contains("SOUL.md"))
    #expect(!result.text.contains("MEMORY.md"))
    #expect(!result.text.contains("IDENTITY.md"))
    #expect(!result.text.contains("HEARTBEAT.md"))
    #expect(!result.text.contains("USER.md"))
    #expect(!result.text.contains("workspace files"))
    #expect(!result.text.contains("available skills"))
    #expect(!result.text.contains("tool schemas"))
}

@Test
func notificationSpeechBuildsMinimalPromptWhenQdrantReturnsNothing() {
    let compiler = LightweightPromptCompiler()
    let result = compiler.buildNotificationSpeechPrompt(
        personaCompact: "Gracula: коротко, по-русски, без внутренностей.",
        notification: LightweightNotificationInput(app: "Calendar", title: "Созвон", body: "Через 10 минут"),
        retrievedSnippets: [],
        modelRef: "mlx/Qwen/Qwen3-30B-A3B-MLX-4bit"
    )

    #expect(result.diagnostics.retrievedSnippetIDs.isEmpty)
    #expect(result.diagnostics.ragTokens == 0)
    #expect(result.text.contains("App: Calendar"))
    #expect(result.text.contains("Title: Созвон"))
    #expect(result.text.contains("Body: Через 10 минут"))
    #expect(result.diagnostics.totalPromptTokens < 4_096)
}

@Test
func promptShrinkingDropsQdrantAndFallbackBeforeCurrentNotification() {
    let compiler = LightweightPromptCompiler()
    let hugeSnippets = (0..<2).map { index in
        LightweightRetrievedSnippet(
            id: "huge-\(index)",
            source: "MEMORY.md",
            kind: "notification_example",
            profile: "notification_speech",
            score: 0.95,
            tokenEstimate: 300,
            text: String(repeating: "лишний контекст ", count: 300)
        )
    }
    let result = compiler.buildNotificationSpeechPrompt(
        personaCompact: String(repeating: "persona ", count: 2_200),
        notification: LightweightNotificationInput(
            app: "Telegram",
            title: "XOR",
            subtitle: String(repeating: "metadata ", count: 900),
            body: String(repeating: "важное тело уведомления ", count: 700),
            channel: "TapMap",
            fallbackSpokenText: String(repeating: "fallback ", count: 900)
        ),
        retrievedSnippets: hugeSnippets,
        modelRef: "mlx/Qwen/Qwen3-30B-A3B-MLX-4bit"
    )

    #expect(result.diagnostics.totalPromptTokens <= 4_096 - 512 - 128)
    #expect(result.diagnostics.shrinkingApplied)
    #expect(result.diagnostics.dropped.contains("Qdrant snippets"))
    #expect(result.text.contains("App: Telegram"))
    #expect(result.text.contains("Title: XOR"))
    #expect(result.text.contains("Body:"))
    #expect(result.text.contains("Task:"))
}

@Test
func notificationCacheCanReuseSpokenTextOrSkipDecision() {
    let gate = LightweightNotificationCacheGate()
    let notification = LightweightNotificationInput(
        app: "Telegram",
        title: "XOR",
        body: "В TapMap новый релиз 42."
    )

    let speak = gate.decision(
        notification: notification,
        entries: [
            LightweightNotificationCacheEntry(
                app: "Telegram",
                title: "XOR",
                body: "В TapMap новый релиз 42.",
                spokenText: "XOR принес в TapMap релиз 42.",
                decision: "speak"
            )
        ]
    )
    #expect(speak == .reuseSpokenText("XOR принес в TapMap релиз 42."))

    let skip = gate.decision(
        notification: notification,
        entries: [
            LightweightNotificationCacheEntry(
                app: "Telegram",
                title: "XOR",
                body: "В TapMap новый релиз 42.",
                spokenText: "Пропускаю шумное уведомление.",
                decision: "skip"
            )
        ]
    )
    #expect(skip == .reuseSkip("Пропускаю шумное уведомление."))
}

@Test
func cacheResultCanBeUsedAsSingleExampleWhenSimilarButNotDuplicate() {
    let gate = LightweightNotificationCacheGate()
    let decision = gate.decision(
        notification: LightweightNotificationInput(
            app: "Telegram",
            title: "TapMap",
            body: "XOR отправил новую карту района."
        ),
        entries: [
            LightweightNotificationCacheEntry(
                app: "Telegram",
                title: "TapMap",
                body: "XOR отправил новую карту центра.",
                spokenText: "XOR кинул свежую карту TapMap.",
                decision: "speak"
            )
        ],
        highThreshold: 0.95,
        exampleThreshold: 0.35
    )

    #expect(decision == .useAsExample("XOR кинул свежую карту TapMap."))
}

@Test
func simpleChatCapsHistoryMemoryAndAvoidsWorkspaceToolsSkillsByDefault() {
    let compiler = LightweightPromptCompiler()
    let result = compiler.buildSimpleChatPrompt(
        personaCompact: String(repeating: "Gracula отвечает коротко. ", count: 100),
        message: "Что с задачей?",
        history: (0..<20).map { "message-\($0)" },
        memorySummary: String(repeating: "память ", count: 1_200),
        retrievedSnippets: [
            LightweightRetrievedSnippet(id: "a", source: "memory", kind: "memory_fact", profile: "simple_chat", score: 0.9, tokenEstimate: 400, text: String(repeating: "факт ", count: 300)),
            LightweightRetrievedSnippet(id: "b", source: "style", kind: "style_hint", profile: "simple_chat", score: 0.8, tokenEstimate: 400, text: String(repeating: "стиль ", count: 300)),
            LightweightRetrievedSnippet(id: "c", source: "rule", kind: "channel_rule", profile: "simple_chat", score: 0.7, tokenEstimate: 400, text: String(repeating: "правило ", count: 300))
        ],
        modelRef: "mlx/Qwen/Qwen3-30B-A3B-MLX-4bit"
    )

    #expect(result.diagnostics.totalPromptTokens < 8_192)
    #expect(result.diagnostics.historyTokens <= estimatedTokens((14..<20).map { "message-\($0)" }.joined(separator: "\n")))
    #expect(result.diagnostics.memoryTokens <= 800)
    #expect(result.diagnostics.workspaceTokens == 0)
    #expect(result.diagnostics.toolsSkillsTokens == 0)
    #expect(result.diagnostics.retrievedTokenCount <= 1_000)
    #expect(result.maxOutputTokens <= 512)
    #expect(result.text.contains("/no_think"))
}
