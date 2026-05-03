import AppKit
import SwiftUI

struct AudioRecorderExampleView: View {
    @StateObject private var viewModel: AudioRecorderViewModel
    @StateObject private var openClawController = OpenClawLocalController()
    @State private var didBootstrapOpenClaw = false

    init(viewModel: AudioRecorderViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        TabView {
            OpenClawMainTabView(
                viewModel: viewModel,
                openClawController: openClawController
            )
            .tabItem {
                Label("Main", systemImage: "message.and.waveform")
            }

            GraculaSettingsTabView(
                viewModel: viewModel,
                openClawController: openClawController
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .task {
            openClawController.start()
            viewModel.setLocalNotificationProcessor { notification, fallbackText in
                guard await openClawController.prepareForLocalAutomation() else {
                    return nil
                }
                return await openClawController.sendLocalNotificationSpeech(
                    localNotificationPrompt(
                        notification: notification,
                        fallbackText: fallbackText
                    )
                )
            }
            await openClawController.ensureLocalModelServer()
            await viewModel.loadRecordings()
            guard !didBootstrapOpenClaw else {
                return
            }
            didBootstrapOpenClaw = true
            openClawController.stop()
            openClawController.start()
        }
    }
}

private func localNotificationPrompt(
    notification: LocalNotification,
    fallbackText: String
) -> String {
    """
    Local macOS notification received. Prepare the exact short text that Gracula should speak aloud to the user.

    Rules:
    - Reply in Russian.
    - One short sentence unless the notification itself requires more.
    - Do not mention implementation details, databases, prompts, or OpenClaw.
    - Preserve important names, numbers, and message content.
    - If the notification is not useful to announce, reply with a very short reason.

    Notification:
    App: \(notification.appIdentifier)
    Title: \(notification.title)
    Subtitle: \(notification.subtitle)
    Body: \(notification.body)

    Fallback spoken text:
    \(fallbackText)
    """
}

private struct OpenClawMainTabView: View {
    @ObservedObject var viewModel: AudioRecorderViewModel
    @ObservedObject var openClawController: OpenClawLocalController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gracula")
                            .font(.title2)
                        Text("Chat locally, start the bot, and record a message.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                OpenClawControlView(controller: openClawController)

                OpenClawChatView(controller: openClawController)

                OpenClawLogView(controller: openClawController)

                HStack {
                    Button {
                        Task {
                            await viewModel.toggleRecording(
                                sendRecognizedText: { message in
                                    await openClawController.sendChatMessage(message)
                                },
                                reportError: { openClawController.reportError($0) }
                            )
                        }
                    } label: {
                        Label(viewModel.buttonTitle, systemImage: viewModel.buttonSystemImage)
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isTranscribing)

                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OpenClawLogView: View {
    @ObservedObject var controller: OpenClawLocalController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Logs")
                        .font(.headline)
                    Text("Runtime and chat trace from the local OpenClaw process.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.logLines.joined(separator: "\n"), forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(controller.logLines.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if controller.logLines.isEmpty {
                            Text("No logs yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
                        } else {
                            ForEach(Array(controller.logLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(minHeight: 160, maxHeight: 240)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: controller.logLines.count) { _, _ in
                    guard let lastIndex = controller.logLines.indices.last else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct GraculaSettingsTabView: View {
    @ObservedObject var viewModel: AudioRecorderViewModel
    @ObservedObject var openClawController: OpenClawLocalController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2)
                    Text("Edit the helper brain, recorder, voice, and workspace files.")
                        .foregroundStyle(.secondary)
                }

                RecorderSettingsSection(viewModel: viewModel)
                VoicePipelineSettingsEditorView(viewModel: viewModel)
                LocalNotificationSettingsSection(viewModel: viewModel)
                OpenClawSettingsView(controller: openClawController)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BrainSettingsSection: View {
    let snapshot: OpenClawSettingsSnapshot
    @Binding var environmentEntries: [OpenClawEditableSetting]
    @Binding var jsonEntries: [OpenClawEditableSetting]
    @State private var selectedPreset: BrainPreset = .localQwen
    @State private var customModelRef = ""
    @State private var googleApiKey = ""
    @State private var openRouterApiKey = ""
    @State private var kiloCodeApiKey = ""
    @State private var isSyncing = false

    init(
        snapshot: OpenClawSettingsSnapshot,
        environmentEntries: Binding<[OpenClawEditableSetting]>,
        jsonEntries: Binding<[OpenClawEditableSetting]>
    ) {
        self.snapshot = snapshot
        self._environmentEntries = environmentEntries
        self._jsonEntries = jsonEntries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Brain", systemImage: "sparkles")

            Text("Active brain: \(activeBrainDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Suggested model", selection: $selectedPreset) {
                ForEach(BrainPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPreset) { _, newValue in
                guard !isSyncing else { return }
                applyPreset(newValue)
            }

            TextField("Primary model ref", text: $customModelRef)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: customModelRef) { _, newValue in
                    guard !isSyncing else { return }
                    applyCustomModelRef(newValue)
                }

            SecureField("Google Gemini API key", text: $googleApiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: googleApiKey) { _, newValue in
                    guard !isSyncing else { return }
                    upsertAPIKey(for: "google", value: newValue)
                }

            SecureField("OpenRouter API key", text: $openRouterApiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: openRouterApiKey) { _, newValue in
                    guard !isSyncing else { return }
                    upsertAPIKey(for: "openrouter", value: newValue)
                }

            SecureField("KiloCode API key", text: $kiloCodeApiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: kiloCodeApiKey) { _, newValue in
                    guard !isSyncing else { return }
                    upsertAPIKey(for: "kilocode", value: newValue)
                }

            Text("API keys are stored in the OpenClaw provider config and exported to provider environment variables when OpenClaw runs.")

            Text("Local backends: Ollama at `http://127.0.0.1:11434` or MLX under Application Support.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: syncDraftFromSnapshot)
        .onChange(of: jsonEntries) { _, _ in
            syncDraftFromSnapshot()
        }
        .onChange(of: snapshot) { _, _ in
            syncDraftFromSnapshot()
        }
    }

    private func syncDraftFromSnapshot() {
        isSyncing = true
        defer { isSyncing = false }

        let currentModel = currentPrimaryModelRef()
        if currentModel.isEmpty {
            selectedPreset = .localQwen
            customModelRef = selectedPreset.modelRef
        } else {
            selectedPreset = BrainPreset.allCases.first(where: { $0.modelRef == currentModel }) ?? .custom
            customModelRef = currentModel
        }
        googleApiKey = apiKey(for: "google")
        openRouterApiKey = apiKey(for: "openrouter")
        kiloCodeApiKey = apiKey(for: "kilocode")
        ensureProviderDefaults()
    }

    private var activeBrainDisplayName: String {
        let currentModel = currentPrimaryModelRef().trimmingCharacters(in: .whitespacesAndNewlines)
        if currentModel.isEmpty {
            return "Not set"
        }
        if let preset = BrainPreset.allCases.first(where: { $0.modelRef == currentModel }) {
            return "\(preset.displayName) (\(currentModel))"
        }
        return currentModel
    }

    private func applyPreset(_ preset: BrainPreset) {
        isSyncing = true
        defer { isSyncing = false }

        customModelRef = preset.modelRef
        upsertJSONSetting(
            key: primaryModelKey(),
            value: preset.modelRef,
            isSecret: false
        )
        clearModelFallbacks()
        applyRuntimeDefaults(for: preset)
    }

    private func applyCustomModelRef(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPreset = BrainPreset.allCases.first(where: { $0.modelRef == trimmed }) ?? .custom

        isSyncing = true
        defer { isSyncing = false }

        selectedPreset = resolvedPreset
        upsertJSONSetting(
            key: primaryModelKey(),
            value: trimmed,
            isSecret: false
        )
        clearModelFallbacks()
        applyRuntimeDefaults(for: resolvedPreset)
    }

    private func applyRuntimeDefaults(for preset: BrainPreset) {
        switch preset {
        case .localQwen:
            ensureOllamaProviderDefaults()
        case .localQwenMLX:
            break
        case .openaiGPT54,
             .openaiCodexGPT54,
             .anthropicOpus46,
             .anthropicSonnet46,
             .kiloAutoFree,
             .kilocodeAuto,
             .googleGeminiPro,
             .googleGeminiFlash,
             .mlxQwen30B:
            ensureProviderDefaults()
        case .custom:
            if customModelRef.lowercased().hasPrefix("ollama/") {
                ensureOllamaProviderDefaults()
            } else {
                ensureProviderDefaults()
            }
        }
    }

    private func currentPrimaryModelRef() -> String {
        if let value = value(for: "agents.defaults.model.primary") {
            return value
        }
        if let value = value(for: "agents.defaults.model") {
            return value
        }
        return OpenClawLLMConfiguration.localQwenModelRef
    }

    private func primaryModelKey() -> String {
        if hasJSONEntry(for: "agents.defaults.model.primary") {
            return "agents.defaults.model.primary"
        }
        if hasJSONEntry(for: "agents.defaults.model") {
            return "agents.defaults.model"
        }
        return "agents.defaults.model.primary"
    }

    private func hasJSONEntry(for key: String) -> Bool {
        jsonEntries.contains(where: { $0.key == key })
            || snapshot.jsonEntries.contains(where: { $0.key == key })
    }

    private func value(for key: String) -> String? {
        jsonEntries.first(where: { $0.key == key })?.value
            ?? snapshot.jsonEntries.first(where: { $0.key == key })?.value
    }

    private func environmentValue(for key: String) -> String? {
        environmentEntries.first(where: { $0.key == key })?.value
            ?? snapshot.environmentEntries.first(where: { $0.key == key })?.value
    }

    private func upsertJSONSetting(
        key: String,
        value: String,
        isSecret: Bool,
        kind: OpenClawEditableSetting.ValueKind = .string
    ) {
        if let index = jsonEntries.firstIndex(where: { $0.key == key }) {
            jsonEntries[index] = OpenClawEditableSetting(
                key: key,
                source: .json,
                kind: kind,
                isSecret: isSecret,
                value: value
            )
            return
        }

        jsonEntries.append(
            OpenClawEditableSetting(
                key: key,
                source: .json,
                kind: kind,
                isSecret: isSecret,
                value: value
            )
        )
    }

    private func upsertEnvironmentSetting(
        key: String,
        value: String,
        isSecret: Bool
    ) {
        if let index = environmentEntries.firstIndex(where: { $0.key == key }) {
            environmentEntries[index] = OpenClawEditableSetting(
                key: key,
                source: .environment,
                kind: .string,
                isSecret: isSecret,
                value: value
            )
            return
        }

        environmentEntries.append(
            OpenClawEditableSetting(
                key: key,
                source: .environment,
                kind: .string,
                isSecret: isSecret,
                value: value
            )
        )
    }

    private func ensureProviderDefaults() {
        for providerName in ["google", "kilocode", "openrouter", "mlx"] {
            guard let provider = OpenClawLLMConfiguration.provider(named: providerName) else {
                continue
            }
            ensureProviderDefaults(provider)
        }
        ensureJSONSetting(
            key: "agents.defaults.model.primary",
            value: BrainPreset.localQwen.modelRef,
            isSecret: false
        )
        ensureJSONSetting(
            key: "agents.defaults.model.fallbacks",
            value: "[]",
            isSecret: false,
            kind: .array
        )
        ensureJSONSetting(
            key: "agents.defaults.thinkingDefault",
            value: "off",
            isSecret: false
        )
        ensureJSONSetting(
            key: "agents.defaults.reasoningDefault",
            value: "off",
            isSecret: false
        )
        ensureOllamaProviderDefaults()
    }

    private func clearModelFallbacks() {
        upsertJSONSetting(
            key: "agents.defaults.model.fallbacks",
            value: "[]",
            isSecret: false,
            kind: .array
        )
    }

    private func ensureProviderDefaults(_ provider: OpenClawLLMProviderConfiguration) {
        ensureJSONSetting(
            key: provider.baseURLPath,
            value: provider.baseURL,
            isSecret: false
        )
        ensureJSONSetting(
            key: provider.apiPath,
            value: provider.api,
            isSecret: false
        )
        ensureJSONSetting(
            key: provider.modelsPath,
            value: provider.modelsJSON,
            isSecret: false,
            kind: .array
        )
    }

    private func ensureOllamaProviderDefaults() {
        let providerPrefix = "models.providers.ollama"
        ensureJSONSetting(
            key: "\(providerPrefix).baseUrl",
            value: "http://127.0.0.1:11434",
            isSecret: false
        )
        ensureJSONSetting(
            key: "\(providerPrefix).api",
            value: "ollama",
            isSecret: false
        )
        ensureJSONSetting(
            key: "\(providerPrefix).authHeader",
            value: "false",
            isSecret: false,
            kind: .bool
        )
        ensureJSONSetting(
            key: "\(providerPrefix).models",
            value: Self.ollamaProviderModelsJSON,
            isSecret: false,
            kind: .array
        )
    }

    private func ensureEnvironmentSetting(
        key: String,
        value settingValue: String,
        isSecret: Bool
    ) {
        let current = environmentValue(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current, !current.isEmpty {
            return
        }
        upsertEnvironmentSetting(key: key, value: settingValue, isSecret: isSecret)
    }

    private func ensureJSONSetting(
        key: String,
        value settingValue: String,
        isSecret: Bool,
        kind: OpenClawEditableSetting.ValueKind = .string
    ) {
        let current = value(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current, !current.isEmpty, current != "[]" {
            return
        }
        upsertJSONSetting(key: key, value: settingValue, isSecret: isSecret, kind: kind)
    }

    private func apiKey(for providerName: String) -> String {
        guard let provider = OpenClawLLMConfiguration.provider(named: providerName) else {
            return ""
        }
        if let jsonAPIKey = value(for: provider.apiKeyPath)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !jsonAPIKey.isEmpty {
            return jsonAPIKey
        }
        return provider.environmentKeys
            .lazy
            .compactMap { environmentValue(for: $0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func upsertAPIKey(for providerName: String, value: String) {
        guard let provider = OpenClawLLMConfiguration.provider(named: providerName) else {
            return
        }
        upsertJSONSetting(
            key: provider.apiKeyPath,
            value: value,
            isSecret: true
        )
    }

    private static var ollamaProviderModelsJSON: String {
        """
        [
          {
            "id": "qwen3:14b",
            "name": "Qwen3 14B (local Ollama)",
            "api": "ollama",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 65536,
            "maxTokens": 8192,
            "params": {
              "think": false,
              "keep_alive": "30m",
              "num_ctx": 65536
            },
            "compat": {
              "supportsTools": false
            }
          }
        ]
        """
    }
}

enum BrainPreset: String, CaseIterable, Identifiable {
    case localQwen = "ollama/qwen3:14b"
    case localQwenMLX = "mlx/qwen3-14b-4bit"
    case openaiGPT54 = "openai/gpt-5.4"
    case openaiCodexGPT54 = "openai-codex/gpt-5.4"
    case anthropicOpus46 = "anthropic/claude-opus-4-6"
    case anthropicSonnet46 = "anthropic/claude-sonnet-4-6"
    case kiloAutoFree = "openrouter/free"
    case kilocodeAuto = "kilocode/kilo/auto"
    case googleGeminiPro = "google/gemini-3.1-pro-preview"
    case googleGeminiFlash = "google/gemini-3-flash-preview"
    case mlxQwen30B = "mlx/Qwen/Qwen3-30B-A3B-MLX-4bit"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localQwen:
            return "Local Qwen3 14B"
        case .localQwenMLX:
            return "Local Qwen3 14B MLX 4-bit"
        case .openaiGPT54:
            return "OpenAI GPT-5.4"
        case .openaiCodexGPT54:
            return "OpenAI Codex GPT-5.4"
        case .anthropicOpus46:
            return "Anthropic Claude Opus 4.6"
        case .anthropicSonnet46:
            return "Anthropic Claude Sonnet 4.6"
        case .kiloAutoFree:
            return "Kilo Auto Free"
        case .kilocodeAuto:
            return "KiloCode Kilo Auto"
        case .googleGeminiPro:
            return "Google Gemini 3.1 Pro"
        case .googleGeminiFlash:
            return "Google Gemini 3 Flash"
        case .mlxQwen30B:
            return "Local Qwen 3 30B"
        case .custom:
            return "Custom"
        }
    }

    var modelRef: String {
        switch self {
        case .custom:
            return ""
        default:
            return rawValue
        }
    }
}

private struct RecorderSettingsSection: View {
    @ObservedObject var viewModel: AudioRecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recorder", systemImage: "mic")

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Input device", selection: $viewModel.selectedInputDeviceID) {
                        ForEach(viewModel.inputDevices) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isRecording || viewModel.isTranscribing)

                    Button {
                        viewModel.refreshInputDevices()
                    } label: {
                        Label("Refresh Devices", systemImage: "arrow.clockwise")
                    }
                }

                Spacer()
            }
        }
    }
}

private struct VoicePipelineSettingsEditorView: View {
    @ObservedObject var viewModel: AudioRecorderViewModel
    @State private var draft = VoicePipelineSettings()
    @State private var statusText = "Ready to edit voice settings."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Voice Pipeline", systemImage: "waveform")

            VStack(alignment: .leading, spacing: 14) {
                Picker("Recognition backend", selection: $draft.speechRecognitionBackend) {
                    ForEach(SpeechRecognitionBackend.allCases, id: \.self) { backend in
                        Text(label(for: backend)).tag(backend)
                    }
                }
                .pickerStyle(.menu)

                Group {
                    TextField("Whisper model", text: $draft.whisperModelName)
                    TextField("Whisper language", text: $draft.whisperLanguageCode)
                }

                Group {
                    TextField("Parakeet model", text: $draft.parakeetModelName)
                    TextField("Parakeet language", text: $draft.parakeetLanguageCode)
                }

                Picker("Speech backend", selection: $draft.speechSynthesisBackend) {
                    ForEach(SpeechSynthesisBackend.allCases, id: \.self) { backend in
                        Text(label(for: backend)).tag(backend)
                    }
                }
                .pickerStyle(.menu)

                Toggle(
                    "Start voice automatically",
                    isOn: Binding(
                        get: { draft.startVoiceAutomatically },
                        set: { draft.startVoiceAutomatically = $0 }
                    )
                )

                Text("Speak the recognized text aloud after transcription.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Picker(
                    "System voice",
                    selection: Binding(
                        get: { draft.appleSystemVoiceIdentifier ?? "" },
                        set: { newValue in
                            draft.appleSystemVoiceIdentifier = newValue.isEmpty ? nil : newValue
                            if let voice = viewModel.systemVoices.first(where: { $0.id == newValue }) {
                                draft.appleSystemVoiceLanguageCode = voice.languageCode
                            }
                        }
                    )
                ) {
                    Text("Automatic").tag("")
                    ForEach(viewModel.systemVoices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speech rate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(draft.appleSystemSpeechRate) },
                                set: { draft.appleSystemSpeechRate = Float($0) }
                            ),
                            in: 0.1...1.0,
                            step: 0.01
                        )
                        Text(String(format: "%.2f", draft.appleSystemSpeechRate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speech pitch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(draft.appleSystemSpeechPitch) },
                                set: { draft.appleSystemSpeechPitch = Float($0) }
                            ),
                            in: 0.1...1.0,
                            step: 0.01
                        )
                        Text(String(format: "%.2f", draft.appleSystemSpeechPitch))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button {
                    reloadDraft()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }

                Button {
                    viewModel.applyVoiceSettings(draft)
                    statusText = "Voice settings saved."
                } label: {
                    Label("Save Voice Settings", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("File: \(VoicePipelineSettingsStore.defaultFileURL().path)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .onAppear {
            reloadDraft()
        }
    }

    private func reloadDraft() {
        draft = viewModel.currentVoiceSettings()
        statusText = "Loaded voice settings."
    }

    private func label(for backend: SpeechRecognitionBackend) -> String {
        switch backend {
        case .whisper:
            return "Whisper"
        case .parakeet:
            return "Parakeet"
        }
    }

    private func label(for backend: SpeechSynthesisBackend) -> String {
        switch backend {
        case .disabled:
            return "Disabled"
        case .appleSystem:
            return "Apple System"
        }
    }
}

private struct LocalNotificationSettingsSection: View {
    @ObservedObject var viewModel: AudioRecorderViewModel
    @State private var draft = VoicePipelineSettings()
    @State private var statusText = "Ready to edit notification settings."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Local Notifications", systemImage: "bell.badge")

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Speak new macOS notifications", isOn: $draft.announceLocalNotifications)

                Toggle("Include app name", isOn: $draft.includeNotificationAppName)

                HStack(spacing: 12) {
                    Text("Poll interval")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $draft.localNotificationPollIntervalSeconds,
                        in: 1...10,
                        step: 1
                    )
                    Text("\(Int(draft.localNotificationPollIntervalSeconds))s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Status: \(viewModel.notificationMonitorStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.latestNotificationText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack {
                Button {
                    reloadDraft()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }

                Button {
                    var settings = viewModel.currentVoiceSettings()
                    settings.announceLocalNotifications = draft.announceLocalNotifications
                    settings.includeNotificationAppName = draft.includeNotificationAppName
                    settings.localNotificationPollIntervalSeconds = draft.localNotificationPollIntervalSeconds
                    viewModel.applyVoiceSettings(settings)
                    statusText = "Notification settings saved."
                } label: {
                    Label("Save Notification Settings", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.restartNotificationMonitor()
                    statusText = "Notification monitor restarted."
                } label: {
                    Label("Restart Monitor", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    viewModel.openPrivacySettings()
                } label: {
                    Label("Full Disk Access", systemImage: "lock.shield")
                }

                Spacer()
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("macOS does not expose other apps' notifications through a public API. This monitor reads the local Notification Center database, sends new notifications to OpenClaw, and speaks OpenClaw's reply. Full Disk Access is required when macOS blocks the database.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            reloadDraft()
        }
    }

    private func reloadDraft() {
        draft = viewModel.currentVoiceSettings()
        statusText = "Loaded notification settings."
    }
}

private func sectionHeader(_ title: String, systemImage: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: systemImage)
        Text(title)
            .font(.headline)
    }
}
