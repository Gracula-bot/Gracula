import Foundation
import Persistence
import Testing

@Test
func appConfigurationStoreCreatesCanonicalPlistAndDirectories() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gracula-persistence-test-\(UUID().uuidString)", isDirectory: true)
    let layout = ProjectRuntimeLayout(projectRootURL: root)
    let store = AppConfigurationStore(layout: layout)

    let configuration = try store.loadOrCreate()

    #expect(FileManager.default.fileExists(atPath: layout.configurationFileURL.path))
    #expect(FileManager.default.fileExists(atPath: layout.workspaceDirectoryURL.path))
    #expect(configuration.runtimePaths.canonicalPlistPath == layout.configurationFileURL.path)
    #expect(configuration.runtimePaths.runtimeRootPath == layout.runtimeRootURL.path)
    #expect(layout.configurationFileURL.path.contains("/ConfigFiles/AppConfiguration.plist"))
}

@Test
func legacyDotEnvAndJSONAreIgnored() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("gracula-persistence-legacy-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try "OPENAI_API_KEY=legacy-key\n".write(
        to: root.appendingPathComponent(".env"),
        atomically: true,
        encoding: .utf8
    )
    let legacyRuntime = root.appendingPathComponent(".openclaw", isDirectory: true)
    try fileManager.createDirectory(at: legacyRuntime, withIntermediateDirectories: true)
    try #"{"models":{"providers":{"openai":{"apiKey":"legacy-json-key"}}}}"#.write(
        to: legacyRuntime.appendingPathComponent("openclaw.json"),
        atomically: true,
        encoding: .utf8
    )

    let layout = ProjectRuntimeLayout(projectRootURL: root)
    let store = AppConfigurationStore(layout: layout)
    let configuration = try store.loadOrCreate()

    #expect(configuration.apiKeys.openAI.isEmpty)
}

@Test
func environmentBuilderUsesCanonicalConfigurationValues() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gracula-persistence-env-\(UUID().uuidString)", isDirectory: true)
    let layout = ProjectRuntimeLayout(projectRootURL: root)
    let store = AppConfigurationStore(layout: layout)
    let configuration = try store.update { configuration in
        configuration.apiKeys.openAI = "test-openai-key"
        configuration.llm.primaryModelRef = "openai/gpt-5.4-mini"
        configuration.qdrant.baseURL = "http://127.0.0.1:9999"
        configuration.tracing.enabled = true
        configuration.tracing.logFullContext = false
        configuration.tracing.logResponseBodies = true
        configuration.tracing.redactSensitiveData = true
        configuration.tracing.logLevel = "debug"
    }

    let environment = AppConfigurationEnvironmentBuilder.build(configuration: configuration, layout: layout)

    #expect(environment["OPENAI_API_KEY"] == "test-openai-key")
    #expect(environment["GRACULA_QDRANT_URL"] == "http://127.0.0.1:9999")
    #expect(environment["GRACULA_CANONICAL_CONFIG_PLIST"] == layout.configurationFileURL.path)
    #expect(environment["GRACULA_TRACE_LOGGING_ENABLED"] == "1")
    #expect(environment["GRACULA_TRACE_LOG_FULL_CONTEXT"] == "0")
    #expect(environment["GRACULA_TRACE_LOG_RESPONSE_BODY"] == "1")
    #expect(environment["GRACULA_TRACE_REDACT_SENSITIVE_DATA"] == "1")
    #expect(environment["GRACULA_TRACE_LOG_LEVEL"] == "debug")
    #expect(environment["GRACULA_TRACE_LOG_PATH"] == layout.logsDirectoryURL.appendingPathComponent("request-trace.jsonl").path)
}

@Test
func bootstrapSeedsWorkspaceTemplatesWithoutBackupFiles() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gracula-bootstrap-\(UUID().uuidString)", isDirectory: true)
    let resources = root.appendingPathComponent("Resources/WorkspaceTemplates", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try "# Identity\n".write(
        to: resources.appendingPathComponent("IDENTITY.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# Soul\n".write(
        to: resources.appendingPathComponent("SOUL.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# Agents\n".write(
        to: resources.appendingPathComponent("AGENTS.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# User\n".write(
        to: resources.appendingPathComponent("USER.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# Tools\n".write(
        to: resources.appendingPathComponent("TOOLS.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# Bootstrap\n".write(
        to: resources.appendingPathComponent("BOOTSTRAP.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# Heartbeat\n".write(
        to: resources.appendingPathComponent("HEARTBEAT.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# Memory\n".write(
        to: resources.appendingPathComponent("MEMORY.md"),
        atomically: true,
        encoding: .utf8
    )
    let runtimeTemplates = root.appendingPathComponent("Resources/RuntimeTemplates", isDirectory: true)
    try FileManager.default.createDirectory(at: runtimeTemplates, withIntermediateDirectories: true)
    try "faster-whisper\n".write(
        to: runtimeTemplates.appendingPathComponent("requirements-speech.txt"),
        atomically: true,
        encoding: .utf8
    )

    let layout = ProjectRuntimeLayout(projectRootURL: root)
    let store = AppConfigurationStore(layout: layout)
    let bootstrapper = AppBootstrapper(
        layout: layout,
        store: store,
        verifier: DependencyVerifier(layout: layout),
        installer: RuntimeDependencyInstaller(layout: layout)
    )

    let result = try bootstrapper.bootstrap()

    #expect(result.diagnostics.status == .degraded || result.diagnostics.status == .ready)
    #expect(FileManager.default.fileExists(atPath: layout.workspaceDirectoryURL.appendingPathComponent("IDENTITY.md").path))
    let noise = try FileManager.default.contentsOfDirectory(at: layout.runtimeRootURL, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.contains(".bak") || $0.lastPathComponent.hasSuffix(".tmp") || $0.lastPathComponent.hasSuffix(".temp") }
    #expect(noise.isEmpty)
}

@Test
func bootstrapFoundationCopiesSpeechRequirementsTemplate() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gracula-bootstrap-foundation-\(UUID().uuidString)", isDirectory: true)
    let workspaceTemplates = root.appendingPathComponent("Resources/WorkspaceTemplates", isDirectory: true)
    let runtimeTemplates = root.appendingPathComponent("Resources/RuntimeTemplates", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceTemplates, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: runtimeTemplates, withIntermediateDirectories: true)
    try "# Identity\n".write(
        to: workspaceTemplates.appendingPathComponent("IDENTITY.md"),
        atomically: true,
        encoding: .utf8
    )
    try "faster-whisper\nctranslate2\n".write(
        to: runtimeTemplates.appendingPathComponent("requirements-speech.txt"),
        atomically: true,
        encoding: .utf8
    )

    let layout = ProjectRuntimeLayout(projectRootURL: root)
    let store = AppConfigurationStore(layout: layout)
    let bootstrapper = AppBootstrapper(
        layout: layout,
        store: store,
        verifier: DependencyVerifier(layout: layout),
        installer: RuntimeDependencyInstaller(layout: layout)
    )

    let configuration = try bootstrapper.bootstrapFoundation()

    #expect(FileManager.default.fileExists(atPath: configuration.python.speechRequirementsPath))
}

@Test
func loadOrCreateCreatesRealPlistFromVisibleExampleTemplate() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("gracula-config-template-\(UUID().uuidString)", isDirectory: true)
    let layout = ProjectRuntimeLayout(projectRootURL: root)
    let store = AppConfigurationStore(layout: layout)
    try store.createManagedDirectoriesIfNeeded()

    let template = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>schemaVersion</key>
    <integer>1</integer>
    <key>apiKeys</key>
    <dict>
        <key>openAI</key>
        <string></string>
    </dict>
    <key>llm</key>
    <dict>
        <key>primaryModelRef</key>
        <string>openai/gpt-5.4-mini</string>
    </dict>
</dict>
</plist>
"""
    try template.write(to: layout.configurationTemplateFileURL, atomically: true, encoding: .utf8)

    let configuration = try store.loadOrCreate()

    #expect(FileManager.default.fileExists(atPath: layout.configurationFileURL.path))
    #expect(configuration.runtimePaths.canonicalPlistPath == layout.configurationFileURL.path)
    #expect(configuration.llm.primaryModelRef == "openai/gpt-5.4-mini")
}

@Test
func dependencyVerifierReportsMissingOptionalRuntimeDependencies() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gracula-deps-\(UUID().uuidString)", isDirectory: true)
    let layout = ProjectRuntimeLayout(projectRootURL: root)
    let store = AppConfigurationStore(layout: layout)
    let configuration = try store.loadOrCreate()

    let report = DependencyVerifier(layout: layout).verify(configuration: configuration)

    let namesByStatus = Dictionary(uniqueKeysWithValues: report.items.map { ($0.name, $0.status) })
    let expectedTDLibStatus = TDLibLibraryLocator.resolveExistingPath(
        preferredPath: configuration.telegram.userTDLibPath
    ) == nil ? "soft-disabled" : "ready"
    #expect(namesByStatus["ffmpeg"] == "missing")
    #expect(namesByStatus["qdrant"] == "soft-disabled")
    #expect(namesByStatus["tdlib"] == expectedTDLibStatus)
    #expect(namesByStatus["gateway-entrypoint"] == "missing-entrypoint")
}

@Test
func loadOrCreateRepairsCanonicalPlistWithMissingNewKeys() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("gracula-config-repair-\(UUID().uuidString)", isDirectory: true)
    let layout = ProjectRuntimeLayout(projectRootURL: root)
    let store = AppConfigurationStore(layout: layout)
    try store.createManagedDirectoriesIfNeeded()

    let legacyLikePlist: [String: Any] = [
        "schemaVersion": 1,
        "runtimePaths": [
            "projectRootPath": layout.projectRootURL.path,
            "runtimeRootPath": layout.runtimeRootURL.path,
            "canonicalPlistPath": layout.configurationFileURL.path,
            "workspacePath": layout.workspaceDirectoryURL.path,
            "logsPath": layout.logsDirectoryURL.path,
            "modelCachePath": layout.modelsDirectoryURL.path,
            "downloadsPath": layout.downloadsDirectoryURL.path,
            "recoveryPath": layout.recoveryDirectoryURL.path
        ],
        "apiKeys": [
            "openAI": "",
            "brave": "",
            "gemini": "",
            "xAI": "",
            "perplexity": "",
            "moonshot": "",
            "firecrawl": ""
        ],
        "llm": [
            "directLocalModeEnabled": true,
            "primaryModelRef": "openai/gpt-5.4-mini",
            "gatewayEnabled": false,
            "gatewayPort": 18789,
            "bridgePort": 18790,
            "streamBridgePort": 7071,
            "openAIBaseURL": "https://api.openai.com/v1",
            "openAITemperature": 0.35,
            "openAITopP": 0.85,
            "reasoningMode": "on",
        ],
        "python": [
            "bootstrapExecutablePath": "/usr/bin/python3",
            "executablePath": layout.pythonExecutableURL.path,
            "venvPath": layout.venvDirectoryURL.path,
            "packagesPath": layout.venvDirectoryURL.appendingPathComponent("lib", isDirectory: true).path,
            "ffmpegExecutablePath": layout.ffmpegExecutableURL.path
        ],
        "whisper": [
            "modelIdentifier": "large-v3-turbo",
            "languageCode": "ru",
            "modelDirectoryPath": layout.modelsDirectoryURL.appendingPathComponent("whisper", isDirectory: true).path,
            "workerScriptPath": layout.pythonDirectoryURL.appendingPathComponent("faster-whisper-worker.py").path
        ],
        "qdrant": [
            "enabled": true,
            "baseURL": "http://127.0.0.1:6333",
            "binaryPath": layout.qdrantBinaryURL.path,
            "storagePath": layout.qdrantStorageDirectoryURL.path,
            "apiKey": "",
            "collectionName": "gracula_memory"
        ],
        "gateway": [
            "enabled": false,
            "repositoryPath": layout.openClawGatewayRootURL.path,
            "entrypointPath": layout.openClawGatewayEntrypointURL.path
        ],
        "telegram": [
            "businessEnabled": false,
            "businessBotToken": "",
            "businessConnectionID": "",
            "businessAutoReplyEnabled": true,
            "businessMarkReadEnabled": true,
            "businessPollIntervalSeconds": 2,
            "userEnabled": false,
            "userAPIID": "",
            "userAPIHash": "",
            "userPhone": "",
            "userTDLibPath": layout.binDirectoryURL.appendingPathComponent("libtdjson.dylib").path,
            "userDatabaseDirectory": layout.runtimeDirectoryURL.appendingPathComponent("telegram-user/database", isDirectory: true).path,
            "userFilesDirectory": layout.runtimeDirectoryURL.appendingPathComponent("telegram-user/files", isDirectory: true).path,
            "userEncryptionKey": "",
            "userChatAllowlist": ""
        ],
        "voice": [
            "speechRecognitionBackend": "whisper",
            "whisperModelName": "large-v3-turbo",
            "whisperLanguageCode": "ru",
            "parakeetModelName": "nvidia/parakeet-tdt-0.6b-v3",
            "parakeetLanguageCode": "auto",
            "speechSynthesisBackend": "appleSystem",
            "speakRecognizedText": true,
            "appleSystemVoiceLanguageCode": "ru-RU",
            "appleSystemVoiceIdentifier": "com.apple.voice.compact.ru-RU.Milena",
            "appleSystemSpeechRate": 0.42,
            "appleSystemSpeechPitch": 0.65,
            "announceLocalNotifications": true,
            "localNotificationPollIntervalSeconds": 2.0,
            "includeNotificationAppName": true
        ],
        "toolRuntimeFlags": [
            "browserCommand": "echo",
            "trackOnlyGroups": true,
            "trackAutoLinks": true
        ]
    ]

    let plistData = try PropertyListSerialization.data(fromPropertyList: legacyLikePlist, format: .xml, options: 0)
    try plistData.write(to: layout.configurationFileURL, options: [.atomic])

    let configuration = try store.loadOrCreate()

    #expect(configuration.python.pipExecutablePath == layout.pipExecutableURL.path)
    #expect(configuration.python.speechRequirementsPath == layout.speechRequirementsURL.path)
    #expect(configuration.runtimePaths.binPath == layout.binDirectoryURL.path)
}

@Test
func loadOrCreateMigratesLegacyHiddenCanonicalPlistToVisibleProjectLocation() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("gracula-config-migrate-\(UUID().uuidString)", isDirectory: true)
    let layout = ProjectRuntimeLayout(projectRootURL: root)
    let store = AppConfigurationStore(layout: layout)
    try store.createManagedDirectoriesIfNeeded()

    let legacyConfiguration = AppConfigurationDefaults.make(layout: layout)
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    let legacyData = try encoder.encode(legacyConfiguration)
    try legacyData.write(to: layout.legacyConfigurationFileURL, options: [.atomic])

    let configuration = try store.loadOrCreate()

    #expect(FileManager.default.fileExists(atPath: layout.configurationFileURL.path))
    #expect(!FileManager.default.fileExists(atPath: layout.legacyConfigurationFileURL.path))
    #expect(configuration.runtimePaths.canonicalPlistPath == layout.configurationFileURL.path)
}
