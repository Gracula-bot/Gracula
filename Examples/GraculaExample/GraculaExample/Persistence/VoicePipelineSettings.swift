import Foundation
import Persistence

enum SpeechRecognitionBackend: String, Codable, CaseIterable, Sendable {
    case parakeet
    case whisper
}

enum SpeechSynthesisBackend: String, Codable, CaseIterable, Sendable {
    case disabled
    case appleSystem
}

struct VoicePipelineSettings: Codable, Sendable {
    enum Defaults {
        static let whisperModelName = "large-v3-turbo"
        static let whisperLanguageCode = "ru"
        static let parakeetModelName = "nvidia/parakeet-tdt-0.6b-v3"
        static let parakeetLanguageCode = "auto"
        static let speechSynthesisBackend: SpeechSynthesisBackend = .appleSystem
        static let speakRecognizedText = true
        static let appleSystemVoiceLanguageCode = "ru-RU"
        static let appleSystemVoiceIdentifier: String? = "com.apple.voice.compact.ru-RU.Milena"
        static let appleSystemSpeechRate: Float = 0.42
        static let appleSystemSpeechPitch: Float = 0.65
        static let voxcpmServerBaseURL = "http://127.0.0.1:8000"
        static let voxcpmModelName = "openbmb/VoxCPM2"
        static let voxcpmVoiceName = "default"
        static let voxcpmDevice = "cpu"
        static let announceLocalNotifications = true
        static let localNotificationPollIntervalSeconds = 2.0
        static let includeNotificationAppName = true
    }

    var speechRecognitionBackend: SpeechRecognitionBackend = .whisper
    var whisperModelName: String = Defaults.whisperModelName
    var whisperLanguageCode: String = Defaults.whisperLanguageCode
    var parakeetModelName: String = Defaults.parakeetModelName
    var parakeetLanguageCode: String = Defaults.parakeetLanguageCode
    var speechSynthesisBackend: SpeechSynthesisBackend = Defaults.speechSynthesisBackend
    var speakRecognizedText: Bool = Defaults.speakRecognizedText
    var appleSystemVoiceLanguageCode: String = Defaults.appleSystemVoiceLanguageCode
    var appleSystemVoiceIdentifier: String? = Defaults.appleSystemVoiceIdentifier
    var appleSystemSpeechRate: Float = Defaults.appleSystemSpeechRate
    var appleSystemSpeechPitch: Float = Defaults.appleSystemSpeechPitch
    var voxcpmServerBaseURL: String = Defaults.voxcpmServerBaseURL
    var voxcpmModelName: String = Defaults.voxcpmModelName
    var voxcpmVoiceName: String = Defaults.voxcpmVoiceName
    var voxcpmDevice: String = Defaults.voxcpmDevice
    var announceLocalNotifications: Bool = Defaults.announceLocalNotifications
    var localNotificationPollIntervalSeconds: Double = Defaults.localNotificationPollIntervalSeconds
    var includeNotificationAppName: Bool = Defaults.includeNotificationAppName

    var startVoiceAutomatically: Bool {
        get { speakRecognizedText }
        set { speakRecognizedText = newValue }
    }

    var recognitionModelName: String {
        switch speechRecognitionBackend {
        case .whisper:
            return whisperModelName
        case .parakeet:
            return parakeetModelName
        }
    }

    var recognitionLanguageCode: String {
        switch speechRecognitionBackend {
        case .whisper:
            return whisperLanguageCode
        case .parakeet:
            return parakeetLanguageCode
        }
    }

    static func loadFromDisk() -> VoicePipelineSettings {
        VoicePipelineSettingsStore.shared.load()
    }

    enum CodingKeys: String, CodingKey {
        case speechRecognitionBackend
        case whisperModelName
        case whisperLanguageCode
        case parakeetModelName
        case parakeetLanguageCode
        case speechSynthesisBackend
        case speakRecognizedText
        case appleSystemVoiceLanguageCode
        case appleSystemVoiceIdentifier
        case appleSystemSpeechRate
        case appleSystemSpeechPitch
        case voxcpmServerBaseURL
        case voxcpmModelName
        case voxcpmVoiceName
        case voxcpmDevice
        case announceLocalNotifications
        case localNotificationPollIntervalSeconds
        case includeNotificationAppName
        case recognitionModelName
        case recognitionLanguageCode
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speechRecognitionBackend = Self.normalizedSpeechRecognitionBackend(
            try container.decodeIfPresent(String.self, forKey: .speechRecognitionBackend)
        )
        whisperModelName = Self.normalizedWhisperModelName(
            try container.decodeIfPresent(String.self, forKey: .whisperModelName)
            ?? container.decodeIfPresent(String.self, forKey: .recognitionModelName)
            ?? Defaults.whisperModelName
        )
        whisperLanguageCode = Self.normalizedWhisperLanguageCode(
            try container.decodeIfPresent(String.self, forKey: .whisperLanguageCode)
            ?? container.decodeIfPresent(String.self, forKey: .recognitionLanguageCode)
            ?? Defaults.whisperLanguageCode
        )
        parakeetModelName = try container.decodeIfPresent(String.self, forKey: .parakeetModelName)
            ?? Defaults.parakeetModelName
        parakeetLanguageCode = try container.decodeIfPresent(String.self, forKey: .parakeetLanguageCode)
            ?? Defaults.parakeetLanguageCode
        speechSynthesisBackend = Self.normalizedSpeechSynthesisBackend(
            try container.decodeIfPresent(String.self, forKey: .speechSynthesisBackend)
        )
        speakRecognizedText = try container.decodeIfPresent(Bool.self, forKey: .speakRecognizedText)
            ?? Defaults.speakRecognizedText
        appleSystemVoiceLanguageCode = try container.decodeIfPresent(String.self, forKey: .appleSystemVoiceLanguageCode)
            ?? Defaults.appleSystemVoiceLanguageCode
        appleSystemVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .appleSystemVoiceIdentifier)
            ?? Defaults.appleSystemVoiceIdentifier
        appleSystemSpeechRate = try container.decodeIfPresent(Float.self, forKey: .appleSystemSpeechRate)
            ?? Defaults.appleSystemSpeechRate
        appleSystemSpeechPitch = try container.decodeIfPresent(Float.self, forKey: .appleSystemSpeechPitch)
            ?? Defaults.appleSystemSpeechPitch
        voxcpmServerBaseURL = try container.decodeIfPresent(String.self, forKey: .voxcpmServerBaseURL)
            ?? Defaults.voxcpmServerBaseURL
        voxcpmModelName = try container.decodeIfPresent(String.self, forKey: .voxcpmModelName)
            ?? Defaults.voxcpmModelName
        voxcpmVoiceName = try container.decodeIfPresent(String.self, forKey: .voxcpmVoiceName)
            ?? Defaults.voxcpmVoiceName
        voxcpmDevice = try container.decodeIfPresent(String.self, forKey: .voxcpmDevice)
            ?? Defaults.voxcpmDevice
        announceLocalNotifications = try container.decodeIfPresent(Bool.self, forKey: .announceLocalNotifications)
            ?? Defaults.announceLocalNotifications
        localNotificationPollIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .localNotificationPollIntervalSeconds)
            ?? Defaults.localNotificationPollIntervalSeconds
        includeNotificationAppName = try container.decodeIfPresent(Bool.self, forKey: .includeNotificationAppName)
            ?? Defaults.includeNotificationAppName
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speechRecognitionBackend, forKey: .speechRecognitionBackend)
        try container.encode(whisperModelName, forKey: .whisperModelName)
        try container.encode(Self.normalizedWhisperLanguageCode(whisperLanguageCode), forKey: .whisperLanguageCode)
        try container.encode(parakeetModelName, forKey: .parakeetModelName)
        try container.encode(parakeetLanguageCode, forKey: .parakeetLanguageCode)
        try container.encode(speechSynthesisBackend, forKey: .speechSynthesisBackend)
        try container.encode(speakRecognizedText, forKey: .speakRecognizedText)
        try container.encode(appleSystemVoiceLanguageCode, forKey: .appleSystemVoiceLanguageCode)
        try container.encodeIfPresent(appleSystemVoiceIdentifier, forKey: .appleSystemVoiceIdentifier)
        try container.encode(appleSystemSpeechRate, forKey: .appleSystemSpeechRate)
        try container.encode(appleSystemSpeechPitch, forKey: .appleSystemSpeechPitch)
        try container.encode(voxcpmServerBaseURL, forKey: .voxcpmServerBaseURL)
        try container.encode(voxcpmModelName, forKey: .voxcpmModelName)
        try container.encode(voxcpmVoiceName, forKey: .voxcpmVoiceName)
        try container.encode(voxcpmDevice, forKey: .voxcpmDevice)
        try container.encode(announceLocalNotifications, forKey: .announceLocalNotifications)
        try container.encode(localNotificationPollIntervalSeconds, forKey: .localNotificationPollIntervalSeconds)
        try container.encode(includeNotificationAppName, forKey: .includeNotificationAppName)
    }

    private static func normalizedWhisperModelName(_ modelName: String) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "":
            return Defaults.whisperModelName
        case "tiny":
            return Defaults.whisperModelName
        case "small":
            return Defaults.whisperModelName
        case "mlx-community/whisper-large-v3-turbo":
            return Defaults.whisperModelName
        case "openai/whisper-large-v3-turbo":
            return Defaults.whisperModelName
        case "turbo":
            return Defaults.whisperModelName
        default:
            if let normalized = normalizedWhisperRepoID(trimmed) {
                return normalized
            }
            return trimmed
        }
    }

    private static func normalizedWhisperRepoID(_ modelName: String) -> String? {
        let knownMappings: [String: String] = [
            "mlx-community/whisper-large-v3": "large-v3",
            "openai/whisper-large-v3": "large-v3",
            "mlx-community/whisper-large-v3-turbo": "large-v3-turbo",
            "openai/whisper-large-v3-turbo": "large-v3-turbo",
            "mlx-community/whisper-small": "small",
            "openai/whisper-small": "small",
            "mlx-community/whisper-medium": "medium",
            "openai/whisper-medium": "medium"
        ]
        return knownMappings[modelName.lowercased()]
    }

    private static func normalizedWhisperLanguageCode(_ languageCode: String) -> String {
        let trimmed = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? Defaults.whisperLanguageCode : trimmed
    }

    private static func normalizedSpeechRecognitionBackend(_ rawValue: String?) -> SpeechRecognitionBackend {
        guard let rawValue,
              let backend = SpeechRecognitionBackend(rawValue: rawValue) else {
            return .whisper
        }
        return backend
    }

    private static func normalizedSpeechSynthesisBackend(_ rawValue: String?) -> SpeechSynthesisBackend {
        guard let rawValue,
              let backend = SpeechSynthesisBackend(rawValue: rawValue) else {
            return Defaults.speechSynthesisBackend
        }
        return backend
    }
}

final class VoicePipelineSettingsStore: @unchecked Sendable {
    static let shared = VoicePipelineSettingsStore()

    private let store: AppConfigurationStore

    init(store: AppConfigurationStore = AppConfigurationStore(layout: ProjectRuntimeLayout.resolveDefault())) {
        self.store = store
    }

    func load() -> VoicePipelineSettings {
        do {
            let configuration = try store.loadOrCreate()
            return VoicePipelineSettings(configuration: configuration)
        } catch {
            return VoicePipelineSettings()
        }
    }

    func save(_ settings: VoicePipelineSettings) {
        do {
            _ = try store.update { configuration in
                settings.apply(to: &configuration)
            }
        } catch {
            log.warning("Failed to save voice pipeline settings: \(error.localizedDescription)")
        }
    }

    func filePath() -> String {
        store.layout.configurationFileURL.path
    }

    static func defaultFileURL() -> URL {
        ProjectRuntimeLayout.resolveDefault().configurationFileURL
    }
}

private extension VoicePipelineSettings {
    init(configuration: AppConfiguration) {
        speechRecognitionBackend = SpeechRecognitionBackend(rawValue: configuration.voice.speechRecognitionBackend) ?? .whisper
        whisperModelName = Self.normalizedWhisperModelName(configuration.voice.whisperModelName)
        whisperLanguageCode = Self.normalizedWhisperLanguageCode(configuration.voice.whisperLanguageCode)
        parakeetModelName = configuration.voice.parakeetModelName
        parakeetLanguageCode = configuration.voice.parakeetLanguageCode
        speechSynthesisBackend = SpeechSynthesisBackend(rawValue: configuration.voice.speechSynthesisBackend) ?? .appleSystem
        speakRecognizedText = configuration.voice.speakRecognizedText
        appleSystemVoiceLanguageCode = configuration.voice.appleSystemVoiceLanguageCode
        appleSystemVoiceIdentifier = configuration.voice.appleSystemVoiceIdentifier
        appleSystemSpeechRate = configuration.voice.appleSystemSpeechRate
        appleSystemSpeechPitch = configuration.voice.appleSystemSpeechPitch
        announceLocalNotifications = configuration.voice.announceLocalNotifications
        localNotificationPollIntervalSeconds = configuration.voice.localNotificationPollIntervalSeconds
        includeNotificationAppName = configuration.voice.includeNotificationAppName
    }

    func apply(to configuration: inout AppConfiguration) {
        configuration.voice.speechRecognitionBackend = speechRecognitionBackend.rawValue
        configuration.voice.whisperModelName = whisperModelName
        configuration.voice.whisperLanguageCode = whisperLanguageCode
        configuration.voice.parakeetModelName = parakeetModelName
        configuration.voice.parakeetLanguageCode = parakeetLanguageCode
        configuration.voice.speechSynthesisBackend = speechSynthesisBackend.rawValue
        configuration.voice.speakRecognizedText = speakRecognizedText
        configuration.voice.appleSystemVoiceLanguageCode = appleSystemVoiceLanguageCode
        configuration.voice.appleSystemVoiceIdentifier = appleSystemVoiceIdentifier
        configuration.voice.appleSystemSpeechRate = appleSystemSpeechRate
        configuration.voice.appleSystemSpeechPitch = appleSystemSpeechPitch
        configuration.voice.announceLocalNotifications = announceLocalNotifications
        configuration.voice.localNotificationPollIntervalSeconds = localNotificationPollIntervalSeconds
        configuration.voice.includeNotificationAppName = includeNotificationAppName
    }
}
