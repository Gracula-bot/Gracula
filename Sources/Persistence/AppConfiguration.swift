import Foundation

public struct AppConfiguration: Codable, Sendable, Equatable {
    public struct APIKeys: Codable, Sendable, Equatable {
        public var openAI: String
        public var brave: String
        public var gemini: String
        public var xAI: String
        public var perplexity: String
        public var moonshot: String
        public var firecrawl: String

        public init(
            openAI: String = "",
            brave: String = "",
            gemini: String = "",
            xAI: String = "",
            perplexity: String = "",
            moonshot: String = "",
            firecrawl: String = ""
        ) {
            self.openAI = openAI
            self.brave = brave
            self.gemini = gemini
            self.xAI = xAI
            self.perplexity = perplexity
            self.moonshot = moonshot
            self.firecrawl = firecrawl
        }
    }

    public struct LLM: Codable, Sendable, Equatable {
        public var directLocalModeEnabled: Bool
        public var primaryModelRef: String
        public var gatewayEnabled: Bool
        public var gatewayPort: Int
        public var bridgePort: Int
        public var streamBridgePort: Int
        public var openAIBaseURL: String
        public var openAITemperature: Double
        public var openAITopP: Double
        public var openAIMaxTokens: Int
        public var personaMode: String
        public var reasoningMode: String
        public var notificationRuntimeContextWindow: Int
        public var notificationMaxOutputTokens: Int
        public var notificationReserveTokens: Int
        public var simpleRuntimeContextWindow: Int
        public var simpleMaxOutputTokens: Int
        public var simpleReserveTokens: Int
        public var deepRuntimeContextWindow: Int
        public var deepMaxOutputTokens: Int
        public var deepReserveTokens: Int

        public init(
            directLocalModeEnabled: Bool,
            primaryModelRef: String,
            gatewayEnabled: Bool,
            gatewayPort: Int,
            bridgePort: Int,
            streamBridgePort: Int,
            openAIBaseURL: String,
            openAITemperature: Double,
            openAITopP: Double,
            openAIMaxTokens: Int,
            personaMode: String,
            reasoningMode: String,
            notificationRuntimeContextWindow: Int,
            notificationMaxOutputTokens: Int,
            notificationReserveTokens: Int,
            simpleRuntimeContextWindow: Int,
            simpleMaxOutputTokens: Int,
            simpleReserveTokens: Int,
            deepRuntimeContextWindow: Int,
            deepMaxOutputTokens: Int,
            deepReserveTokens: Int
        ) {
            self.directLocalModeEnabled = directLocalModeEnabled
            self.primaryModelRef = primaryModelRef
            self.gatewayEnabled = gatewayEnabled
            self.gatewayPort = gatewayPort
            self.bridgePort = bridgePort
            self.streamBridgePort = streamBridgePort
            self.openAIBaseURL = openAIBaseURL
            self.openAITemperature = openAITemperature
            self.openAITopP = openAITopP
            self.openAIMaxTokens = openAIMaxTokens
            self.personaMode = personaMode
            self.reasoningMode = reasoningMode
            self.notificationRuntimeContextWindow = notificationRuntimeContextWindow
            self.notificationMaxOutputTokens = notificationMaxOutputTokens
            self.notificationReserveTokens = notificationReserveTokens
            self.simpleRuntimeContextWindow = simpleRuntimeContextWindow
            self.simpleMaxOutputTokens = simpleMaxOutputTokens
            self.simpleReserveTokens = simpleReserveTokens
            self.deepRuntimeContextWindow = deepRuntimeContextWindow
            self.deepMaxOutputTokens = deepMaxOutputTokens
            self.deepReserveTokens = deepReserveTokens
        }
    }

    public struct RuntimePaths: Codable, Sendable, Equatable {
        public var projectRootPath: String
        public var runtimeRootPath: String
        public var canonicalPlistPath: String
        public var binPath: String
        public var workspacePath: String
        public var logsPath: String
        public var modelCachePath: String
        public var downloadsPath: String
        public var recoveryPath: String

        public init(
            projectRootPath: String,
            runtimeRootPath: String,
            canonicalPlistPath: String,
            binPath: String,
            workspacePath: String,
            logsPath: String,
            modelCachePath: String,
            downloadsPath: String,
            recoveryPath: String
        ) {
            self.projectRootPath = projectRootPath
            self.runtimeRootPath = runtimeRootPath
            self.canonicalPlistPath = canonicalPlistPath
            self.binPath = binPath
            self.workspacePath = workspacePath
            self.logsPath = logsPath
            self.modelCachePath = modelCachePath
            self.downloadsPath = downloadsPath
            self.recoveryPath = recoveryPath
        }
    }

    public struct Python: Codable, Sendable, Equatable {
        public var bootstrapExecutablePath: String
        public var executablePath: String
        public var pipExecutablePath: String
        public var venvPath: String
        public var packagesPath: String
        public var speechRequirementsPath: String
        public var ffmpegExecutablePath: String

        public init(
            bootstrapExecutablePath: String,
            executablePath: String,
            pipExecutablePath: String,
            venvPath: String,
            packagesPath: String,
            speechRequirementsPath: String,
            ffmpegExecutablePath: String
        ) {
            self.bootstrapExecutablePath = bootstrapExecutablePath
            self.executablePath = executablePath
            self.pipExecutablePath = pipExecutablePath
            self.venvPath = venvPath
            self.packagesPath = packagesPath
            self.speechRequirementsPath = speechRequirementsPath
            self.ffmpegExecutablePath = ffmpegExecutablePath
        }
    }

    public struct Whisper: Codable, Sendable, Equatable {
        public var modelIdentifier: String
        public var languageCode: String
        public var modelDirectoryPath: String
        public var workerScriptPath: String

        public init(modelIdentifier: String, languageCode: String, modelDirectoryPath: String, workerScriptPath: String) {
            self.modelIdentifier = modelIdentifier
            self.languageCode = languageCode
            self.modelDirectoryPath = modelDirectoryPath
            self.workerScriptPath = workerScriptPath
        }
    }

    public struct Qdrant: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var baseURL: String
        public var binaryPath: String
        public var storagePath: String
        public var apiKey: String
        public var collectionName: String

        public init(
            enabled: Bool,
            baseURL: String,
            binaryPath: String,
            storagePath: String,
            apiKey: String,
            collectionName: String
        ) {
            self.enabled = enabled
            self.baseURL = baseURL
            self.binaryPath = binaryPath
            self.storagePath = storagePath
            self.apiKey = apiKey
            self.collectionName = collectionName
        }
    }

    public struct LocalService: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var baseURL: String
        public var modelName: String
        public var runtimePath: String
        public var dataPath: String

        public init(enabled: Bool, baseURL: String, modelName: String, runtimePath: String, dataPath: String) {
            self.enabled = enabled
            self.baseURL = baseURL
            self.modelName = modelName
            self.runtimePath = runtimePath
            self.dataPath = dataPath
        }
    }

    public struct Gateway: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var repositoryPath: String
        public var entrypointPath: String

        public init(enabled: Bool, repositoryPath: String, entrypointPath: String) {
            self.enabled = enabled
            self.repositoryPath = repositoryPath
            self.entrypointPath = entrypointPath
        }
    }

    public struct Telegram: Codable, Sendable, Equatable {
        public var businessEnabled: Bool
        public var businessBotToken: String
        public var businessConnectionID: String
        public var businessAutoReplyEnabled: Bool
        public var businessMarkReadEnabled: Bool
        public var businessPollIntervalSeconds: Int
        public var userEnabled: Bool
        public var userAPIID: String
        public var userAPIHash: String
        public var userPhone: String
        public var userTDLibPath: String
        public var userDatabaseDirectory: String
        public var userFilesDirectory: String
        public var userEncryptionKey: String
        public var userChatAllowlist: String

        public init(
            businessEnabled: Bool,
            businessBotToken: String,
            businessConnectionID: String,
            businessAutoReplyEnabled: Bool,
            businessMarkReadEnabled: Bool,
            businessPollIntervalSeconds: Int,
            userEnabled: Bool,
            userAPIID: String,
            userAPIHash: String,
            userPhone: String,
            userTDLibPath: String,
            userDatabaseDirectory: String,
            userFilesDirectory: String,
            userEncryptionKey: String,
            userChatAllowlist: String
        ) {
            self.businessEnabled = businessEnabled
            self.businessBotToken = businessBotToken
            self.businessConnectionID = businessConnectionID
            self.businessAutoReplyEnabled = businessAutoReplyEnabled
            self.businessMarkReadEnabled = businessMarkReadEnabled
            self.businessPollIntervalSeconds = businessPollIntervalSeconds
            self.userEnabled = userEnabled
            self.userAPIID = userAPIID
            self.userAPIHash = userAPIHash
            self.userPhone = userPhone
            self.userTDLibPath = userTDLibPath
            self.userDatabaseDirectory = userDatabaseDirectory
            self.userFilesDirectory = userFilesDirectory
            self.userEncryptionKey = userEncryptionKey
            self.userChatAllowlist = userChatAllowlist
        }
    }

    public struct Voice: Codable, Sendable, Equatable {
        public var speechRecognitionBackend: String
        public var whisperModelName: String
        public var whisperLanguageCode: String
        public var parakeetModelName: String
        public var parakeetLanguageCode: String
        public var speechSynthesisBackend: String
        public var speakRecognizedText: Bool
        public var appleSystemVoiceLanguageCode: String
        public var appleSystemVoiceIdentifier: String?
        public var appleSystemSpeechRate: Float
        public var appleSystemSpeechPitch: Float
        public var announceLocalNotifications: Bool
        public var localNotificationPollIntervalSeconds: Double
        public var includeNotificationAppName: Bool

        public init(
            speechRecognitionBackend: String,
            whisperModelName: String,
            whisperLanguageCode: String,
            parakeetModelName: String,
            parakeetLanguageCode: String,
            speechSynthesisBackend: String,
            speakRecognizedText: Bool,
            appleSystemVoiceLanguageCode: String,
            appleSystemVoiceIdentifier: String?,
            appleSystemSpeechRate: Float,
            appleSystemSpeechPitch: Float,
            announceLocalNotifications: Bool,
            localNotificationPollIntervalSeconds: Double,
            includeNotificationAppName: Bool
        ) {
            self.speechRecognitionBackend = speechRecognitionBackend
            self.whisperModelName = whisperModelName
            self.whisperLanguageCode = whisperLanguageCode
            self.parakeetModelName = parakeetModelName
            self.parakeetLanguageCode = parakeetLanguageCode
            self.speechSynthesisBackend = speechSynthesisBackend
            self.speakRecognizedText = speakRecognizedText
            self.appleSystemVoiceLanguageCode = appleSystemVoiceLanguageCode
            self.appleSystemVoiceIdentifier = appleSystemVoiceIdentifier
            self.appleSystemSpeechRate = appleSystemSpeechRate
            self.appleSystemSpeechPitch = appleSystemSpeechPitch
            self.announceLocalNotifications = announceLocalNotifications
            self.localNotificationPollIntervalSeconds = localNotificationPollIntervalSeconds
            self.includeNotificationAppName = includeNotificationAppName
        }
    }

    public struct ToolRuntimeFlags: Codable, Sendable, Equatable {
        public var browserCommand: String
        public var trackOnlyGroups: Bool
        public var trackAutoLinks: Bool

        public init(browserCommand: String, trackOnlyGroups: Bool, trackAutoLinks: Bool) {
            self.browserCommand = browserCommand
            self.trackOnlyGroups = trackOnlyGroups
            self.trackAutoLinks = trackAutoLinks
        }
    }

    public var schemaVersion: Int
    public var runtimePaths: RuntimePaths
    public var apiKeys: APIKeys
    public var llm: LLM
    public var python: Python
    public var whisper: Whisper
    public var qdrant: Qdrant
    public var gateway: Gateway
    public var telegram: Telegram
    public var voice: Voice
    public var toolRuntimeFlags: ToolRuntimeFlags
}

public enum AppConfigurationDefaults {
    public static func make(layout: ProjectRuntimeLayout) -> AppConfiguration {
        AppConfiguration(
            schemaVersion: 1,
            runtimePaths: .init(
                projectRootPath: layout.projectRootURL.path,
                runtimeRootPath: layout.runtimeRootURL.path,
                canonicalPlistPath: layout.configurationFileURL.path,
                binPath: layout.binDirectoryURL.path,
                workspacePath: layout.workspaceDirectoryURL.path,
                logsPath: layout.logsDirectoryURL.path,
                modelCachePath: layout.modelsDirectoryURL.path,
                downloadsPath: layout.downloadsDirectoryURL.path,
                recoveryPath: layout.recoveryDirectoryURL.path
            ),
            apiKeys: .init(),
            llm: .init(
                directLocalModeEnabled: true,
                primaryModelRef: "openai/gpt-5.4-mini",
                gatewayEnabled: false,
                gatewayPort: 18789,
                bridgePort: 18790,
                streamBridgePort: 7071,
                openAIBaseURL: "https://api.openai.com/v1",
                openAITemperature: 0.35,
                openAITopP: 0.85,
                openAIMaxTokens: 512,
                personaMode: "deep_persona",
                reasoningMode: "on",
                notificationRuntimeContextWindow: 4096,
                notificationMaxOutputTokens: 128,
                notificationReserveTokens: 512,
                simpleRuntimeContextWindow: 8192,
                simpleMaxOutputTokens: 512,
                simpleReserveTokens: 1024,
                deepRuntimeContextWindow: 16384,
                deepMaxOutputTokens: 2048,
                deepReserveTokens: 4096
            ),
            python: .init(
                bootstrapExecutablePath: "/usr/bin/python3",
                executablePath: layout.pythonExecutableURL.path,
                pipExecutablePath: layout.pipExecutableURL.path,
                venvPath: layout.venvDirectoryURL.path,
                packagesPath: layout.venvDirectoryURL.appendingPathComponent("lib", isDirectory: true).path,
                speechRequirementsPath: layout.speechRequirementsURL.path,
                ffmpegExecutablePath: layout.ffmpegExecutableURL.path
            ),
            whisper: .init(
                modelIdentifier: "large-v3-turbo",
                languageCode: "ru",
                modelDirectoryPath: layout.modelsDirectoryURL.appendingPathComponent("whisper", isDirectory: true).path,
                workerScriptPath: layout.pythonDirectoryURL.appendingPathComponent("faster-whisper-worker.py").path
            ),
            qdrant: .init(
                enabled: true,
                baseURL: "http://127.0.0.1:6333",
                binaryPath: layout.qdrantBinaryURL.path,
                storagePath: layout.qdrantStorageDirectoryURL.path,
                apiKey: "",
                collectionName: "gracula_memory"
            ),
            gateway: .init(
                enabled: false,
                repositoryPath: layout.openClawGatewayRootURL.path,
                entrypointPath: layout.openClawGatewayEntrypointURL.path
            ),
            telegram: .init(
                businessEnabled: false,
                businessBotToken: "",
                businessConnectionID: "",
                businessAutoReplyEnabled: true,
                businessMarkReadEnabled: true,
                businessPollIntervalSeconds: 2,
                userEnabled: false,
                userAPIID: "",
                userAPIHash: "",
                userPhone: "",
                userTDLibPath: layout.binDirectoryURL.appendingPathComponent("libtdjson.dylib").path,
                userDatabaseDirectory: layout.runtimeDirectoryURL.appendingPathComponent("telegram-user/database", isDirectory: true).path,
                userFilesDirectory: layout.runtimeDirectoryURL.appendingPathComponent("telegram-user/files", isDirectory: true).path,
                userEncryptionKey: "",
                userChatAllowlist: ""
            ),
            voice: .init(
                speechRecognitionBackend: "whisper",
                whisperModelName: "large-v3-turbo",
                whisperLanguageCode: "ru",
                parakeetModelName: "nvidia/parakeet-tdt-0.6b-v3",
                parakeetLanguageCode: "auto",
                speechSynthesisBackend: "appleSystem",
                speakRecognizedText: true,
                appleSystemVoiceLanguageCode: "ru-RU",
                appleSystemVoiceIdentifier: "com.apple.voice.compact.ru-RU.Milena",
                appleSystemSpeechRate: 0.42,
                appleSystemSpeechPitch: 0.65,
                announceLocalNotifications: true,
                localNotificationPollIntervalSeconds: 2.0,
                includeNotificationAppName: true
            ),
            toolRuntimeFlags: .init(
                browserCommand: "echo",
                trackOnlyGroups: true,
                trackAutoLinks: true
            )
        )
    }
}
