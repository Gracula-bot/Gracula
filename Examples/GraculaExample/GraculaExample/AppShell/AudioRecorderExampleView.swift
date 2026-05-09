import AppKit
import Persistence
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
            await viewModel.loadRecordings()
            guard !didBootstrapOpenClaw else {
                return
            }
            didBootstrapOpenClaw = true
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
    @State private var isHandlingSpaceHold = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    recordButton

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
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            ZStack {
                SpaceHoldRecordingMonitor(
                    isEnabled: !viewModel.isTranscribing,
                    onPress: startSpaceHoldRecording,
                    onRelease: stopSpaceHoldRecording
                )
                InitialWindowFocusResetter()
            }
        )
    }

    private var recordButton: some View {
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
            VStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 56, height: 56)

                    Image(systemName: viewModel.buttonSystemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(viewModel.isRecording ? "Recording" : "Record")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 88)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isTranscribing)
        .help(viewModel.buttonTitle)
    }

    private func startSpaceHoldRecording() {
        guard !isHandlingSpaceHold else {
            return
        }
        isHandlingSpaceHold = true
        Task {
            await viewModel.beginHoldToRecord(
                reportError: { openClawController.reportError($0) }
            )
        }
    }

    private func stopSpaceHoldRecording() {
        guard isHandlingSpaceHold else {
            return
        }
        isHandlingSpaceHold = false
        Task {
            await viewModel.endHoldToRecord(
                sendRecognizedText: { message in
                    await openClawController.sendChatMessage(message)
                },
                reportError: { openClawController.reportError($0) }
            )
        }
    }
}

private struct InitialWindowFocusResetter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct SpaceHoldRecordingMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPress: onPress, onRelease: onRelease)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installIfNeeded()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onPress = onPress
        context.coordinator.onRelease = onRelease
        context.coordinator.installIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        var isEnabled = true
        var onPress: () -> Void
        var onRelease: () -> Void
        private var keyDownMonitor: Any?
        private var keyUpMonitor: Any?
        private var isSpaceHeld = false

        init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
            self.onPress = onPress
            self.onRelease = onRelease
        }

        deinit {
            teardown()
        }

        func installIfNeeded() {
            if keyDownMonitor == nil {
                keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handleKeyDown(event) ?? event
                }
            }
            if keyUpMonitor == nil {
                keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                    self?.handleKeyUp(event) ?? event
                }
            }
        }

        func teardown() {
            if let keyDownMonitor {
                NSEvent.removeMonitor(keyDownMonitor)
                self.keyDownMonitor = nil
            }
            if let keyUpMonitor {
                NSEvent.removeMonitor(keyUpMonitor)
                self.keyUpMonitor = nil
            }
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard shouldHandle(event) else {
                return event
            }
            guard !event.isARepeat else {
                return nil
            }
            guard !isSpaceHeld else {
                return nil
            }
            isSpaceHeld = true
            onPress()
            return nil
        }

        private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
            guard event.keyCode == 49 else {
                return event
            }
            guard isSpaceHeld else {
                return event
            }
            isSpaceHeld = false
            onRelease()
            return nil
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard isEnabled, event.keyCode == 49 else {
                return false
            }
            guard NSApp.isActive,
                  let window = NSApp.keyWindow else {
                return false
            }
            let responder = window.firstResponder
            if responder is NSTextView || responder is NSTextField {
                return false
            }
            return true
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

                settingsSectionCard {
                    RecorderSettingsSection(viewModel: viewModel)
                }

                settingsSectionCard {
                    VoicePipelineSettingsEditorView(viewModel: viewModel)
                }

                settingsSectionCard {
                    LocalNotificationSettingsSection(viewModel: viewModel)
                }

                settingsSectionCard {
                    OpenClawSettingsView(controller: openClawController)
                }
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
    let canonicalPlistPath: String
    let applyDraftSettings: () -> String
    @State private var selectedPreset: BrainPreset = .openAIGPT54Mini
    @State private var customModelRef = ""
    @State private var openAIApiKey = ""
    @State private var braveAPIKey = ""
    @State private var geminiAPIKey = ""
    @State private var xaiAPIKey = ""
    @State private var perplexityAPIKey = ""
    @State private var moonshotAPIKey = ""
    @State private var firecrawlAPIKey = ""
    @State private var openAITemperature = 0.35
    @State private var openAITopP = 0.85
    @State private var openAIMaxTokens = 512
    @State private var qdrantURL = ""
    @State private var qdrantBinaryPath = ""
    @State private var qdrantStoragePath = ""
    @State private var telegramBusinessEnabled = false
    @State private var telegramBusinessBotToken = ""
    @State private var telegramBusinessConnectionId = ""
    @State private var telegramBusinessAutoReplyEnabled = true
    @State private var telegramBusinessMarkReadEnabled = true
    @State private var telegramBusinessPollIntervalSeconds = 2
    @State private var telegramUserEnabled = false
    @State private var telegramUserAPIId = ""
    @State private var telegramUserAPIHash = ""
    @State private var telegramUserPhone = ""
    @State private var telegramUserTDLibPath = ""
    @State private var telegramUserDatabaseDirectory = ""
    @State private var telegramUserFilesDirectory = ""
    @State private var telegramUserEncryptionKey = ""
    @State private var telegramUserChatAllowlist = ""
    @State private var selectedPersonaMode: BrainPersonaMode = .deepPersona
    @State private var selectedReasoningMode: BrainReasoningMode = .on
    @State private var notificationContextTokens = 4096
    @State private var notificationOutputTokens = 128
    @State private var notificationReserveTokens = 512
    @State private var simpleContextTokens = 8192
    @State private var simpleOutputTokens = 512
    @State private var simpleReserveTokens = 1024
    @State private var deepContextTokens = 16384
    @State private var deepOutputTokens = 2048
    @State private var deepReserveTokens = 4096
    @State private var openAIApplyStatus = ""
    @State private var isSyncing = false
    @State private var didSeedProviderDefaults = false

    init(
        snapshot: OpenClawSettingsSnapshot,
        environmentEntries: Binding<[OpenClawEditableSetting]>,
        jsonEntries: Binding<[OpenClawEditableSetting]>,
        canonicalPlistPath: String,
        applyDraftSettings: @escaping () -> String
    ) {
        self.snapshot = snapshot
        self._environmentEntries = environmentEntries
        self._jsonEntries = jsonEntries
        self.canonicalPlistPath = canonicalPlistPath
        self.applyDraftSettings = applyDraftSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Brain", systemImage: "sparkles")

            Text("Active brain: \(activeBrainDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsLabeledField("Suggested model") {
                Picker("Suggested model", selection: $selectedPreset) {
                    ForEach(BrainPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: selectedPreset) { _, newValue in
                guard !isSyncing else { return }
                applyPreset(newValue)
            }

            SettingsLabeledField("Primary model ref") {
                TextField("Primary model ref", text: $customModelRef)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
                .onChange(of: customModelRef) { _, newValue in
                    guard !isSyncing else { return }
                    applyCustomModelRef(newValue)
                }

            Divider()

            Picker("Persona mode", selection: $selectedPersonaMode) {
                ForEach(BrainPersonaMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedPersonaMode) { _, newValue in
                guard !isSyncing else { return }
                upsertJSONSetting(
                    key: "agents.defaults.localPrompt.mode",
                    value: newValue.rawValue,
                    isSecret: false
                )
            }

            Picker("Reasoning", selection: $selectedReasoningMode) {
                ForEach(BrainReasoningMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedReasoningMode) { _, newValue in
                guard !isSyncing else { return }
                upsertJSONSetting(
                    key: "agents.defaults.localPrompt.reasoning",
                    value: newValue.rawValue,
                    isSecret: false
                )
            }

            promptTokenControls

            apiKeyControls

            openAIRequestControls

            Text("Push-safe template: `ConfigFiles/AppConfiguration.example.plist`. Local runtime config: `ConfigFiles/AppConfiguration.plist`.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            qdrantControls

            Divider()

            telegramBusinessControls

            Divider()

            telegramUserControls
        }
        .onAppear {
            syncDraftFromSnapshot()
            seedProviderDefaultsIfNeeded()
        }
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
        if currentModel.isEmpty || OpenClawLLMConfiguration.isLegacyLocalDefault(currentModel) {
            selectedPreset = .openAIGPT54Mini
            customModelRef = selectedPreset.modelRef
        } else {
            selectedPreset = BrainPreset.allCases.first(where: { $0.modelRef == currentModel }) ?? .custom
            customModelRef = currentModel
        }
        openAIApiKey = apiKey(for: "openai")
        braveAPIKey = environmentValue(forAny: ["BRAVE_API_KEY"]) ?? ""
        geminiAPIKey = environmentValue(forAny: ["GEMINI_API_KEY"]) ?? ""
        xaiAPIKey = environmentValue(forAny: ["XAI_API_KEY"]) ?? ""
        perplexityAPIKey = environmentValue(forAny: ["PERPLEXITY_API_KEY"]) ?? ""
        moonshotAPIKey = environmentValue(forAny: ["KIMI_API_KEY", "MOONSHOT_API_KEY"]) ?? ""
        firecrawlAPIKey = environmentValue(forAny: ["FIRECRAWL_API_KEY"]) ?? ""
        openAITemperature = doubleValue(
            for: "agents.defaults.localPrompt.openAIChat.temperature",
            default: 0.35,
            range: 0...2
        )
        openAITopP = doubleValue(
            for: "agents.defaults.localPrompt.openAIChat.topP",
            default: 0.85,
            range: 0...1
        )
        openAIMaxTokens = intValue(
            for: "agents.defaults.localPrompt.openAIChat.maxTokens",
            default: 512,
            range: 32...8192
        )
        selectedPersonaMode = BrainPersonaMode(rawValue: value(for: "agents.defaults.localPrompt.mode") ?? "") ?? .deepPersona
        selectedReasoningMode = BrainReasoningMode(rawValue: value(for: "agents.defaults.localPrompt.reasoning") ?? "") ?? .on
        notificationContextTokens = intValue(
            for: "agents.defaults.localPrompt.notificationSpeech.runtimeContextWindow",
            default: 4096,
            range: 1024...4096
        )
        notificationOutputTokens = intValue(
            for: "agents.defaults.localPrompt.notificationSpeech.maxOutputTokens",
            default: 128,
            range: 16...128
        )
        notificationReserveTokens = intValue(
            for: "agents.defaults.localPrompt.notificationSpeech.reserveTokens",
            default: 512,
            range: 128...1024
        )
        simpleContextTokens = intValue(
            for: "agents.defaults.localPrompt.simpleChat.runtimeContextWindow",
            default: 8192,
            range: 2048...32768
        )
        simpleOutputTokens = intValue(
            for: "agents.defaults.localPrompt.simpleChat.maxOutputTokens",
            default: 512,
            range: 64...2048
        )
        simpleReserveTokens = intValue(
            for: "agents.defaults.localPrompt.simpleChat.reserveTokens",
            default: 1024,
            range: 256...4096
        )
        deepContextTokens = intValue(
            for: "agents.defaults.localPrompt.deepPersona.runtimeContextWindow",
            default: 16384,
            range: 8192...65536
        )
        deepOutputTokens = intValue(
            for: "agents.defaults.localPrompt.deepPersona.maxOutputTokens",
            default: 2048,
            range: 256...8192
        )
        deepReserveTokens = intValue(
            for: "agents.defaults.localPrompt.deepPersona.reserveTokens",
            default: 4096,
            range: 1024...8192
        )
        let runtimeLayout = ProjectRuntimeLayout.resolveDefault()
        qdrantURL = environmentValue(for: "GRACULA_QDRANT_URL") ?? "http://127.0.0.1:6333"
        qdrantBinaryPath = environmentValue(for: "GRACULA_QDRANT_BIN")
            ?? runtimeLayout.qdrantBinaryURL.path
        qdrantStoragePath = environmentValue(for: "GRACULA_QDRANT_STORAGE_DIR")
            ?? runtimeLayout.qdrantStorageDirectoryURL.path
        telegramBusinessEnabled = boolValue(
            for: "integrations.telegram.business.enabled",
            default: false
        )
        telegramBusinessBotToken = value(for: "integrations.telegram.business.botToken")
            ?? environmentValue(for: "GRACULA_TELEGRAM_BOT_TOKEN")
            ?? environmentValue(for: "TELEGRAM_BOT_TOKEN")
            ?? ""
        telegramBusinessConnectionId = value(for: "integrations.telegram.business.businessConnectionId")
            ?? environmentValue(for: "GRACULA_TELEGRAM_BUSINESS_CONNECTION_ID")
            ?? ""
        telegramBusinessAutoReplyEnabled = boolValue(
            for: "integrations.telegram.business.autoReplyEnabled",
            default: true
        )
        telegramBusinessMarkReadEnabled = boolValue(
            for: "integrations.telegram.business.markReadEnabled",
            default: true
        )
        telegramBusinessPollIntervalSeconds = intValue(
            for: "integrations.telegram.business.pollIntervalSeconds",
            default: 2,
            range: 1...60
        )
        telegramUserEnabled = boolValue(
            for: "integrations.telegram.user.enabled",
            default: false
        ) || environmentValue(for: "TELEGRAM_MODE")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mtproto"
        telegramUserAPIId = value(for: "integrations.telegram.user.apiId")
            ?? environmentValue(for: "GRACULA_TELEGRAM_API_ID")
            ?? environmentValue(for: "TELEGRAM_API_ID")
            ?? ""
        telegramUserAPIHash = value(for: "integrations.telegram.user.apiHash")
            ?? environmentValue(for: "GRACULA_TELEGRAM_API_HASH")
            ?? environmentValue(for: "TELEGRAM_API_HASH")
            ?? ""
        telegramUserPhone = value(for: "integrations.telegram.user.phone")
            ?? environmentValue(for: "GRACULA_TELEGRAM_PHONE")
            ?? environmentValue(for: "TELEGRAM_PHONE")
            ?? ""
        let preferredTDLibPath = value(for: "integrations.telegram.user.tdjsonLibraryPath")
            ?? environmentValue(for: "GRACULA_TDLIB_JSON_LIBRARY")
            ?? runtimeLayout.binDirectoryURL.appendingPathComponent("libtdjson.dylib").path
        telegramUserTDLibPath = TDLibLibraryLocator.resolveExistingPath(
            preferredPath: preferredTDLibPath
        ) ?? preferredTDLibPath
        telegramUserDatabaseDirectory = value(for: "integrations.telegram.user.databaseDirectory")
            ?? environmentValue(for: "GRACULA_TELEGRAM_USER_DATABASE_DIR")
            ?? runtimeLayout.runtimeDirectoryURL.appendingPathComponent("telegram-user/database").path
        telegramUserFilesDirectory = value(for: "integrations.telegram.user.filesDirectory")
            ?? environmentValue(for: "GRACULA_TELEGRAM_USER_FILES_DIR")
            ?? runtimeLayout.runtimeDirectoryURL.appendingPathComponent("telegram-user/files").path
        telegramUserEncryptionKey = value(for: "integrations.telegram.user.encryptionKey")
            ?? environmentValue(for: "GRACULA_TELEGRAM_USER_ENCRYPTION_KEY")
            ?? ""
        telegramUserChatAllowlist = value(for: "integrations.telegram.user.chatAllowlist")
            ?? environmentValue(for: "GRACULA_TELEGRAM_USER_CHAT_ALLOWLIST")
            ?? ""
    }

    private func seedProviderDefaultsIfNeeded() {
        guard !didSeedProviderDefaults else {
            return
        }
        didSeedProviderDefaults = true
        migrateLegacyLocalDefaultIfNeeded()
        guard value(for: "agents.defaults.model.primary") == nil,
              value(for: "agents.defaults.model") == nil else {
            return
        }
        ensureProviderDefaults()
        syncDraftFromSnapshot()
    }

    private var apiKeyControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("API Keys", systemImage: "key")

            SettingsLabeledField("OpenAI API key") {
                HStack(alignment: .center, spacing: 8) {
                    SecureField("OpenAI API key", text: $openAIApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: openAIApiKey) { _, newValue in
                            guard !isSyncing else { return }
                            upsertAPIKey(for: "openai", value: newValue)
                        }

                    Button {
                        let persistedKey = openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        let status = applyDraftSettings()
                        if status.lowercased().contains("failed") {
                            openAIApplyStatus = status
                        } else if persistedKey.isEmpty {
                            openAIApplyStatus = "OpenAI API key cleared in \(canonicalPlistPath)."
                        } else {
                            openAIApplyStatus = "OpenAI API key recorded in \(canonicalPlistPath)."
                        }
                    } label: {
                        Label("Apply", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !openAIApplyStatus.isEmpty {
                Text(openAIApplyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsLabeledField("Brave Search API key") {
                SecureField("Brave Search API key (optional)", text: $braveAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: braveAPIKey) { _, newValue in
                        guard !isSyncing else { return }
                        upsertEnvironmentAliases(keys: ["BRAVE_API_KEY"], value: newValue)
                    }
            }

            SettingsLabeledField("Gemini API key") {
                SecureField("Gemini API key", text: $geminiAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: geminiAPIKey) { _, newValue in
                        guard !isSyncing else { return }
                        upsertEnvironmentAliases(keys: ["GEMINI_API_KEY"], value: newValue)
                    }
            }

            SettingsLabeledField("xAI API key") {
                SecureField("xAI API key", text: $xaiAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: xaiAPIKey) { _, newValue in
                        guard !isSyncing else { return }
                        upsertEnvironmentAliases(keys: ["XAI_API_KEY"], value: newValue)
                    }
            }

            SettingsLabeledField("Perplexity API key") {
                SecureField("Perplexity API key", text: $perplexityAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: perplexityAPIKey) { _, newValue in
                        guard !isSyncing else { return }
                        upsertEnvironmentAliases(keys: ["PERPLEXITY_API_KEY"], value: newValue)
                    }
            }

            SettingsLabeledField("Moonshot / Kimi API key") {
                SecureField("Moonshot / Kimi API key", text: $moonshotAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: moonshotAPIKey) { _, newValue in
                        guard !isSyncing else { return }
                        upsertEnvironmentAliases(keys: ["KIMI_API_KEY", "MOONSHOT_API_KEY"], value: newValue)
                    }
            }

            SettingsLabeledField("Firecrawl API key") {
                SecureField("Firecrawl API key", text: $firecrawlAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: firecrawlAPIKey) { _, newValue in
                        guard !isSyncing else { return }
                        upsertEnvironmentAliases(keys: ["FIRECRAWL_API_KEY"], value: newValue)
                    }
            }

            Text("These fields update the draft settings immediately and are written into the project when you press Apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var qdrantControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Qdrant", systemImage: "externaldrive.connected.to.line.below")
            SettingsLabeledField("Qdrant URL") {
                TextField("Qdrant URL", text: $qdrantURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
                .onChange(of: qdrantURL) { _, newValue in
                    guard !isSyncing else { return }
                    upsertEnvironmentSetting(key: "GRACULA_QDRANT_URL", value: newValue)
                    upsertEnvironmentSetting(key: "OPENCLAW_QDRANT_URL", value: newValue)
                    upsertEnvironmentSetting(key: "QDRANT_URL", value: newValue)
                }
            SettingsLabeledField("Embedded qdrant binary") {
                TextField("Embedded qdrant binary", text: $qdrantBinaryPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
                .onChange(of: qdrantBinaryPath) { _, newValue in
                    guard !isSyncing else { return }
                    upsertEnvironmentSetting(key: "GRACULA_QDRANT_BIN", value: newValue)
                    upsertEnvironmentSetting(key: "OPENCLAW_QDRANT_BIN", value: newValue)
                }
            SettingsLabeledField("Qdrant storage") {
                TextField("Qdrant storage", text: $qdrantStoragePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
                .onChange(of: qdrantStoragePath) { _, newValue in
                    guard !isSyncing else { return }
                    upsertEnvironmentSetting(key: "GRACULA_QDRANT_STORAGE_DIR", value: newValue)
                    upsertEnvironmentSetting(key: "OPENCLAW_QDRANT_STORAGE_DIR", value: newValue)
                }
        }
    }

    private var openAIRequestControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("OpenAI Request Settings", systemImage: "slider.horizontal.3")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", openAITemperature))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $openAITemperature, in: 0...2, step: 0.05)
                    .onChange(of: openAITemperature) { _, newValue in
                        guard !isSyncing else { return }
                        upsertJSONSetting(
                            key: "agents.defaults.localPrompt.openAIChat.temperature",
                            value: String(format: "%.2f", newValue),
                            isSecret: false,
                            kind: .double
                        )
                        syncOpenAIProviderModelParameters()
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Top P")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", openAITopP))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $openAITopP, in: 0...1, step: 0.05)
                    .onChange(of: openAITopP) { _, newValue in
                        guard !isSyncing else { return }
                        upsertJSONSetting(
                            key: "agents.defaults.localPrompt.openAIChat.topP",
                            value: String(format: "%.2f", newValue),
                            isSecret: false,
                            kind: .double
                        )
                        syncOpenAIProviderModelParameters()
                    }
            }

            Stepper(value: $openAIMaxTokens, in: 32...8192, step: 32) {
                Text("OpenAI max tokens cap: \(openAIMaxTokens)")
                    .font(.caption)
            }
            .onChange(of: openAIMaxTokens) { _, newValue in
                guard !isSyncing else { return }
                upsertJSONSetting(
                    key: "agents.defaults.localPrompt.openAIChat.maxTokens",
                    value: String(newValue),
                    isSecret: false,
                    kind: .int
                )
            }

            Text("These values are applied to direct OpenAI chat requests after you press Apply.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var telegramBusinessControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Telegram Business", systemImage: "paperplane")

            Toggle("Enable Telegram Business mode", isOn: $telegramBusinessEnabled)
                .onChange(of: telegramBusinessEnabled) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(
                        key: "integrations.telegram.business.enabled",
                        value: newValue ? "true" : "false",
                        isSecret: false,
                        kind: .bool
                    )
                }

            SecureField("Bot token", text: $telegramBusinessBotToken)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramBusinessBotToken) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(
                        key: "integrations.telegram.business.botToken",
                        value: newValue,
                        isSecret: true
                    )
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_BOT_TOKEN", value: newValue, isSecret: true)
                }

            TextField("Business connection ID (optional)", text: $telegramBusinessConnectionId)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramBusinessConnectionId) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(
                        key: "integrations.telegram.business.businessConnectionId",
                        value: newValue,
                        isSecret: false
                    )
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_BUSINESS_CONNECTION_ID", value: newValue)
                }

            Toggle("Auto reply from OpenClaw", isOn: $telegramBusinessAutoReplyEnabled)
                .onChange(of: telegramBusinessAutoReplyEnabled) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(
                        key: "integrations.telegram.business.autoReplyEnabled",
                        value: newValue ? "true" : "false",
                        isSecret: false,
                        kind: .bool
                    )
                }

            Toggle("Mark incoming messages as read", isOn: $telegramBusinessMarkReadEnabled)
                .onChange(of: telegramBusinessMarkReadEnabled) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(
                        key: "integrations.telegram.business.markReadEnabled",
                        value: newValue ? "true" : "false",
                        isSecret: false,
                        kind: .bool
                    )
                }

            Stepper(value: $telegramBusinessPollIntervalSeconds, in: 1...60, step: 1) {
                Text("Poll interval: \(telegramBusinessPollIntervalSeconds)s")
                    .font(.caption)
            }
            .onChange(of: telegramBusinessPollIntervalSeconds) { _, newValue in
                guard !isSyncing else { return }
                upsertJSONSetting(
                    key: "integrations.telegram.business.pollIntervalSeconds",
                    value: String(newValue),
                    isSecret: false,
                    kind: .int
                )
            }
        }
    }

    private var telegramUserControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Telegram User API", systemImage: "person.crop.circle.badge.checkmark")

            Toggle("Enable Telegram user API", isOn: $telegramUserEnabled)
                .onChange(of: telegramUserEnabled) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(
                        key: "integrations.telegram.user.enabled",
                        value: newValue ? "true" : "false",
                        isSecret: false,
                        kind: .bool
                    )
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_USER_ENABLED", value: newValue ? "1" : "0")
                }

            TextField("api_id from my.telegram.org", text: $telegramUserAPIId)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramUserAPIId) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(key: "integrations.telegram.user.apiId", value: newValue, isSecret: true, kind: .int)
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_API_ID", value: newValue, isSecret: true)
                }

            SecureField("api_hash from my.telegram.org", text: $telegramUserAPIHash)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramUserAPIHash) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(key: "integrations.telegram.user.apiHash", value: newValue, isSecret: true)
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_API_HASH", value: newValue, isSecret: true)
                }

            TextField("Phone number (+...)", text: $telegramUserPhone)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramUserPhone) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(key: "integrations.telegram.user.phone", value: newValue, isSecret: true)
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_PHONE", value: newValue, isSecret: true)
                }

            TextField("libtdjson.dylib path", text: $telegramUserTDLibPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramUserTDLibPath) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(key: "integrations.telegram.user.tdjsonLibraryPath", value: newValue, isSecret: false)
                    upsertEnvironmentSetting(key: "GRACULA_TDLIB_JSON_LIBRARY", value: newValue)
                }

            TextField("TDLib database directory", text: $telegramUserDatabaseDirectory)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramUserDatabaseDirectory) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(key: "integrations.telegram.user.databaseDirectory", value: newValue, isSecret: false)
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_USER_DATABASE_DIR", value: newValue)
                }

            TextField("TDLib files directory", text: $telegramUserFilesDirectory)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramUserFilesDirectory) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(key: "integrations.telegram.user.filesDirectory", value: newValue, isSecret: false)
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_USER_FILES_DIR", value: newValue)
                }

            SecureField("Local TDLib encryption key", text: $telegramUserEncryptionKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramUserEncryptionKey) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(key: "integrations.telegram.user.encryptionKey", value: newValue, isSecret: true)
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_USER_ENCRYPTION_KEY", value: newValue, isSecret: true)
                }

            TextField("Allowed chats (comma separated IDs or titles)", text: $telegramUserChatAllowlist)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: telegramUserChatAllowlist) { _, newValue in
                    guard !isSyncing else { return }
                    upsertJSONSetting(key: "integrations.telegram.user.chatAllowlist", value: newValue, isSecret: false)
                    upsertEnvironmentSetting(key: "GRACULA_TELEGRAM_USER_CHAT_ALLOWLIST", value: newValue)
                }

            Text("Reads personal chats through TDLib after phone login. Keep an allowlist for production use.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var promptTokenControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            promptTokenRow(
                title: "Notification speech",
                context: $notificationContextTokens,
                output: $notificationOutputTokens,
                reserve: $notificationReserveTokens,
                contextRange: 1024...4096,
                outputRange: 16...128,
                reserveRange: 128...1024,
                keyPrefix: "agents.defaults.localPrompt.notificationSpeech"
            )
            promptTokenRow(
                title: "Simple chat",
                context: $simpleContextTokens,
                output: $simpleOutputTokens,
                reserve: $simpleReserveTokens,
                contextRange: 2048...32768,
                outputRange: 64...2048,
                reserveRange: 256...4096,
                keyPrefix: "agents.defaults.localPrompt.simpleChat"
            )
            promptTokenRow(
                title: "Deep persona",
                context: $deepContextTokens,
                output: $deepOutputTokens,
                reserve: $deepReserveTokens,
                contextRange: 8192...65536,
                outputRange: 256...8192,
                reserveRange: 1024...8192,
                keyPrefix: "agents.defaults.localPrompt.deepPersona"
            )
        }
    }

    private func promptTokenRow(
        title: String,
        context: Binding<Int>,
        output: Binding<Int>,
        reserve: Binding<Int>,
        contextRange: ClosedRange<Int>,
        outputRange: ClosedRange<Int>,
        reserveRange: ClosedRange<Int>,
        keyPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                promptStepperRow("Context", value: context, range: contextRange, key: "\(keyPrefix).runtimeContextWindow")
                promptStepperRow("Output", value: output, range: outputRange, key: "\(keyPrefix).maxOutputTokens")
                promptStepperRow("Reserve", value: reserve, range: reserveRange, key: "\(keyPrefix).reserveTokens")
            }
        }
    }

    private func promptStepperRow(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        key: String
    ) -> some View {
        GridRow {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Stepper(value: value, in: range, step: tokenStep(for: range)) {
                Text("\(value.wrappedValue)")
                    .font(.system(.caption, design: .monospaced))
            }
            .onChange(of: value.wrappedValue) { _, newValue in
                guard !isSyncing else { return }
                upsertJSONSetting(
                    key: key,
                    value: String(newValue),
                    isSecret: false,
                    kind: .int
                )
            }
        }
    }

    private func tokenStep(for range: ClosedRange<Int>) -> Int {
        range.upperBound <= 128 ? 16 : 256
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
        let modelRef = sanitizedModelRef(preset.modelRef)
        isSyncing = true
        defer { isSyncing = false }

        customModelRef = modelRef
        upsertJSONSetting(
            key: primaryModelKey(),
            value: modelRef,
            isSecret: false
        )
        clearModelFallbacks()
        applyRuntimeDefaults(for: preset)
    }

    private func applyCustomModelRef(_ value: String) {
        let trimmed = sanitizedModelRef(value)
        let resolvedPreset = BrainPreset.allCases.first(where: { $0.modelRef == trimmed }) ?? .custom

        isSyncing = true
        defer { isSyncing = false }

        selectedPreset = resolvedPreset
        customModelRef = trimmed
        upsertJSONSetting(
            key: primaryModelKey(),
            value: trimmed,
            isSecret: false
        )
        clearModelFallbacks()
        applyRuntimeDefaults(for: resolvedPreset)
    }

    private func applyRuntimeDefaults(for preset: BrainPreset) {
        let modelRef = sanitizedModelRef(preset == .custom ? customModelRef : preset.modelRef)
        if let provider = OpenClawLLMConfiguration.provider(forModelRef: modelRef) {
            ensureProviderDefaults(provider)
        } else {
            ensureProviderDefaults()
        }
        ensureCommonBrainDefaults()
    }

    private func currentPrimaryModelRef() -> String {
        if let value = value(for: "agents.defaults.model.primary") {
            return sanitizedModelRef(OpenClawLLMConfiguration.migratedModelRef(value))
        }
        if let value = value(for: "agents.defaults.model") {
            return sanitizedModelRef(OpenClawLLMConfiguration.migratedModelRef(value))
        }
        return OpenClawLLMConfiguration.defaultModelRef
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

    private func intValue(for key: String, default defaultValue: Int, range: ClosedRange<Int>) -> Int {
        guard let rawValue = value(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Int(rawValue) else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func doubleValue(for key: String, default defaultValue: Double, range: ClosedRange<Double>) -> Double {
        guard let rawValue = value(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Double(rawValue) else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func boolValue(for key: String, default defaultValue: Bool) -> Bool {
        guard let rawValue = value(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawValue.isEmpty else {
            return defaultValue
        }
        switch rawValue {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }

    private func environmentValue(for key: String) -> String? {
        environmentEntries.first(where: { $0.key == key })?.value
            ?? snapshot.environmentEntries.first(where: { $0.key == key })?.value
    }

    private func environmentValue(forAny keys: [String]) -> String? {
        keys.lazy
            .compactMap(environmentValue(for:))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func providerAPIKeyPath(for providerName: String) -> String {
        "models.providers.\(providerName).apiKey"
    }

    private func apiKey(for providerName: String) -> String {
        value(for: providerAPIKeyPath(for: providerName)) ?? ""
    }

    private func upsertAPIKey(for providerName: String, value: String) {
        upsertJSONSetting(
            key: providerAPIKeyPath(for: providerName),
            value: value,
            isSecret: true
        )
        if providerName == "openai" {
            upsertEnvironmentSetting(key: "OPENAI_API_KEY", value: value, isSecret: true)
        }
    }

    private func upsertEnvironmentAliases(keys: [String], value: String, isSecret: Bool = true) {
        for key in keys {
            upsertEnvironmentSetting(key: key, value: value, isSecret: isSecret)
        }
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
        isSecret: Bool = false
    ) {
        if let index = environmentEntries.firstIndex(where: { $0.key == key }) {
            environmentEntries[index] = OpenClawEditableSetting(
                key: key,
                source: .environment,
                kind: .string,
                isSecret: isSecret || key.range(of: #"(?i)(token|secret|key|password)"#, options: .regularExpression) != nil,
                value: value
            )
            return
        }

        environmentEntries.append(
            OpenClawEditableSetting(
                key: key,
                source: .environment,
                kind: .string,
                isSecret: isSecret || key.range(of: #"(?i)(token|secret|key|password)"#, options: .regularExpression) != nil,
                value: value
            )
        )
    }

    private func syncOpenAIProviderModelParameters() {
        let jsonString = value(for: "models.providers.openai.models")
            ?? OpenClawLLMConfiguration.providers.first(where: { $0.name == "openai" })?.modelsJSON
            ?? "[]"
        guard let data = jsonString.data(using: .utf8),
              var models = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              !models.isEmpty else {
            return
        }

        var firstModel = models[0]
        var params = firstModel["params"] as? [String: Any] ?? [:]
        params["temperature"] = openAITemperature
        params["top_p"] = openAITopP
        firstModel["params"] = params
        models[0] = firstModel

        guard JSONSerialization.isValidJSONObject(models),
              let updatedData = try? JSONSerialization.data(withJSONObject: models, options: [.sortedKeys]),
              let updatedString = String(data: updatedData, encoding: .utf8) else {
            return
        }

        upsertJSONSetting(
            key: "models.providers.openai.models",
            value: updatedString,
            isSecret: false,
            kind: .array
        )
    }

    private func ensureProviderDefaults() {
        for provider in OpenClawLLMConfiguration.providers {
            ensureProviderDefaults(provider)
        }
        ensureCommonBrainDefaults()
    }

    private func ensureCommonBrainDefaults() {
        ensureJSONSetting(
            key: "agents.defaults.model.primary",
            value: OpenClawLLMConfiguration.defaultModelRef,
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
        ensureJSONSetting(
            key: "agents.defaults.localPrompt.openAIChat.temperature",
            value: "0.35",
            isSecret: false,
            kind: .double
        )
        ensureJSONSetting(
            key: "agents.defaults.localPrompt.openAIChat.topP",
            value: "0.85",
            isSecret: false,
            kind: .double
        )
        ensureJSONSetting(
            key: "agents.defaults.localPrompt.openAIChat.maxTokens",
            value: "512",
            isSecret: false,
            kind: .int
        )
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
        if let auth = provider.auth {
            ensureJSONSetting(
                key: provider.authPath,
                value: auth,
                isSecret: false
            )
        }
        if let authHeader = provider.authHeader {
            ensureJSONSetting(
                key: provider.authHeaderPath,
                value: authHeader ? "true" : "false",
                isSecret: false,
                kind: .bool
            )
        }
    }

    private func migrateLegacyLocalDefaultIfNeeded() {
        let currentModel = currentPrimaryModelRef()
        guard OpenClawLLMConfiguration.isLegacyLocalDefault(currentModel) else {
            return
        }

        if let provider = OpenClawLLMConfiguration.provider(forModelRef: OpenClawLLMConfiguration.defaultModelRef) {
            ensureProviderDefaults(provider)
        }
        upsertJSONSetting(
            key: primaryModelKey(),
            value: OpenClawLLMConfiguration.defaultModelRef,
            isSecret: false
        )
        clearModelFallbacks()
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

    private func sanitizedModelRef(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return OpenClawLLMConfiguration.defaultModelRef
        }
        if trimmed.lowercased().hasPrefix("openai/") {
            return trimmed
        }
        return OpenClawLLMConfiguration.defaultModelRef
    }

}

enum BrainPreset: String, CaseIterable, Identifiable {
    case openAIGPT54Mini = "openai/gpt-5.4-mini"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAIGPT54Mini:
            return "OpenAI GPT-5.4 Mini"
        case .custom:
            return "Custom"
        }
    }

    var modelRef: String {
        switch self {
        case .openAIGPT54Mini:
            return OpenClawLLMConfiguration.openAIModelRef
        case .custom:
            return ""
        }
    }
}

private enum BrainPersonaMode: String, CaseIterable, Identifiable {
    case personaCompact = "persona_compact"
    case deepPersona = "deep_persona"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personaCompact:
            return "persona_compact"
        case .deepPersona:
            return "deep_persona"
        }
    }
}

private enum BrainReasoningMode: String, CaseIterable, Identifiable {
    case off
    case on

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "Reasoning off"
        case .on:
            return "Reasoning on"
        }
    }
}

private struct RecorderSettingsSection: View {
    @ObservedObject var viewModel: AudioRecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recorder", systemImage: "mic")

            VStack(alignment: .leading, spacing: 12) {
                SettingsLabeledField("Input device") {
                    Picker("Input device", selection: $viewModel.selectedInputDeviceID) {
                        ForEach(viewModel.inputDevices) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(viewModel.isRecording || viewModel.isTranscribing)
                }

                Button {
                    viewModel.refreshInputDevices()
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

private struct VoicePipelineSettingsEditorView: View {
    private struct RecognitionModelOption: Identifiable {
        let id: String
        let title: String
        let detail: String

        var label: String {
            detail.isEmpty ? title : "\(title) (\(detail))"
        }
    }

    private static let recognitionModelOptions: [RecognitionModelOption] = [
        RecognitionModelOption(id: "tiny", title: "tiny", detail: "fastest"),
        RecognitionModelOption(id: "base", title: "base", detail: "balanced"),
        RecognitionModelOption(id: "small", title: "small", detail: "better accuracy"),
        RecognitionModelOption(id: "medium", title: "medium", detail: "high accuracy"),
        RecognitionModelOption(id: "large-v3", title: "large-v3", detail: "best accuracy"),
        RecognitionModelOption(id: "large-v3-turbo", title: "large-v3-turbo", detail: "recommended"),
        RecognitionModelOption(id: "distil-large-v3", title: "distil-large-v3", detail: "smaller large")
    ]

    @ObservedObject var viewModel: AudioRecorderViewModel
    @State private var draft = VoicePipelineSettings()
    @State private var statusText = "Ready to edit voice settings."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Voice Pipeline", systemImage: "waveform")

            VStack(alignment: .leading, spacing: 14) {
                SettingsLabeledField("Recognition model") {
                    Picker("Recognition model", selection: $draft.whisperModelName) {
                        ForEach(Self.recognitionModelOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsLabeledField("Recognition language") {
                    TextField("Recognition language", text: $draft.whisperLanguageCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Text("The selected speech model is downloaded automatically when you save and use voice transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsLabeledField("Speech backend") {
                    Picker("Speech backend", selection: $draft.speechSynthesisBackend) {
                        ForEach(SpeechSynthesisBackend.allCases, id: \.self) { backend in
                            Text(label(for: backend)).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Toggle("Speak recognized text", isOn: $draft.speakRecognizedText)

                Text("After transcription, Gracula can speak the recognized text back through the selected system voice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsLabeledField("System voice") {
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
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

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

            Text("Voice settings file")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(VoicePipelineSettingsStore.defaultFileURL().path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            reloadDraft()
        }
    }

    private func reloadDraft() {
        draft = viewModel.currentVoiceSettings()
        if draft.whisperLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.whisperLanguageCode = "ru"
        }
        statusText = "Loaded voice settings."
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
                .font(.caption)
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

private func settingsSectionCard<Content: View>(
    @ViewBuilder content: () -> Content
) -> some View {
    content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
}

private struct SettingsLabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}
