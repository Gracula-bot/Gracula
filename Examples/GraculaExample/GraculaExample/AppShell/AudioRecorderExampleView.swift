import SwiftUI

struct AudioRecorderExampleView: View {
    @StateObject private var viewModel: AudioRecorderViewModel
    @StateObject private var openClawController = OpenClawLocalController()

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
            await viewModel.loadRecordings()
        }
    }
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
                OpenClawSettingsView(controller: openClawController)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BrainSettingsSection: View {
    let snapshot: OpenClawSettingsSnapshot
    @Binding var jsonEntries: [OpenClawEditableSetting]
    @State private var selectedPreset: BrainPreset = .openaiGPT54
    @State private var customModelRef = ""
    @State private var googleApiKey = ""
    @State private var kiloCodeApiKey = ""
    @State private var isSyncing = false

    init(snapshot: OpenClawSettingsSnapshot, jsonEntries: Binding<[OpenClawEditableSetting]>) {
        self.snapshot = snapshot
        self._jsonEntries = jsonEntries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Brain", systemImage: "sparkles")

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
                    upsertJSONSetting(
                        key: "models.providers.google.apiKey",
                        value: newValue,
                        isSecret: true
                    )
                }

            SecureField("KiloCode API key", text: $kiloCodeApiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: kiloCodeApiKey) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(
                        key: "models.providers.kilocode.apiKey",
                        value: newValue,
                        isSecret: true
                    )
                }

            Text("Google Gemini works with `google/gemini-3.1-pro-preview` or `google/gemini-3-flash-preview`. OpenClaw also accepts `GEMINI_API_KEY` and `GOOGLE_API_KEY` for provider auth.")
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
            selectedPreset = .openaiGPT54
            customModelRef = selectedPreset.modelRef
        } else {
            selectedPreset = BrainPreset.allCases.first(where: { $0.modelRef == currentModel }) ?? .custom
            customModelRef = currentModel
        }
        googleApiKey = value(for: "models.providers.google.apiKey") ?? ""
        kiloCodeApiKey = value(for: "models.providers.kilocode.apiKey") ?? ""
        ensureProviderDefaults()
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
    }

    private func currentPrimaryModelRef() -> String {
        if let value = value(for: "agents.defaults.model.primary") {
            return value
        }
        if let value = value(for: "agents.defaults.model") {
            return value
        }
        return ""
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

    private func ensureProviderDefaults() {
        ensureGoogleProviderDefaults()
        ensureKilocodeProviderDefaults()
    }

    private func ensureGoogleProviderDefaults() {
        let providerPrefix = "models.providers.google"
        ensureJSONSetting(
            key: "\(providerPrefix).baseUrl",
            value: "https://generativelanguage.googleapis.com/v1beta",
            isSecret: false
        )
        ensureJSONSetting(
            key: "\(providerPrefix).api",
            value: "google-generative-ai",
            isSecret: false
        )
        ensureJSONSetting(
            key: "\(providerPrefix).models",
            value: Self.googleProviderModelsJSON,
            isSecret: false,
            kind: .array
        )
    }

    private func ensureKilocodeProviderDefaults() {
        let providerPrefix = "models.providers.kilocode"
        ensureJSONSetting(
            key: "\(providerPrefix).baseUrl",
            value: "https://api.kilo.ai/api/gateway/",
            isSecret: false
        )
        ensureJSONSetting(
            key: "\(providerPrefix).api",
            value: "openai-completions",
            isSecret: false
        )
        ensureJSONSetting(
            key: "\(providerPrefix).models",
            value: Self.kilocodeProviderModelsJSON,
            isSecret: false,
            kind: .array
        )
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

    private static var googleProviderModelsJSON: String {
        """
        [
          {
            "id": "gemini-3.1-pro-preview",
            "name": "Gemini 3.1 Pro Preview",
            "api": "google-generative-ai",
            "reasoning": true,
            "input": ["text", "image"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 1048576,
            "maxTokens": 65536
          },
          {
            "id": "gemini-3-flash-preview",
            "name": "Gemini 3 Flash Preview",
            "api": "google-generative-ai",
            "reasoning": false,
            "input": ["text", "image"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 1048576,
            "maxTokens": 65536
          }
        ]
        """
    }

    private static var kilocodeProviderModelsJSON: String {
        """
        [
          {
            "id": "kilo/auto",
            "name": "Kilo Auto",
            "reasoning": true,
            "input": ["text", "image"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 1000000,
            "maxTokens": 128000
          }
        ]
        """
    }
}

enum BrainPreset: String, CaseIterable, Identifiable {
    case openaiGPT54 = "openai/gpt-5.4"
    case openaiCodexGPT54 = "openai-codex/gpt-5.4"
    case anthropicOpus46 = "anthropic/claude-opus-4-6"
    case anthropicSonnet46 = "anthropic/claude-sonnet-4-6"
    case kilocodeAuto = "kilocode/kilo/auto"
    case googleGeminiPro = "google/gemini-3.1-pro-preview"
    case googleGeminiFlash = "google/gemini-3-flash-preview"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openaiGPT54:
            return "OpenAI GPT-5.4"
        case .openaiCodexGPT54:
            return "OpenAI Codex GPT-5.4"
        case .anthropicOpus46:
            return "Anthropic Claude Opus 4.6"
        case .anthropicSonnet46:
            return "Anthropic Claude Sonnet 4.6"
        case .kilocodeAuto:
            return "KiloCode Kilo Auto"
        case .googleGeminiPro:
            return "Google Gemini 3.1 Pro"
        case .googleGeminiFlash:
            return "Google Gemini 3 Flash"
        case .custom:
            return "Custom"
        }
    }

    var modelRef: String {
        switch self {
        case .custom:
            return ""
        case .kilocodeAuto:
            return "kilocode/kilo/auto"
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

                TextField("VoxCPM server base URL", text: $draft.voxcpmServerBaseURL)
                TextField("VoxCPM model", text: $draft.voxcpmModelName)
                TextField("VoxCPM voice", text: $draft.voxcpmVoiceName)
                TextField("VoxCPM device", text: $draft.voxcpmDevice)
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
        case .voxcpmLocal:
            return "VoxCPM Local"
        case .voxcpmServer:
            return "VoxCPM Server"
        }
    }
}

private func sectionHeader(_ title: String, systemImage: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: systemImage)
        Text(title)
            .font(.headline)
    }
}
