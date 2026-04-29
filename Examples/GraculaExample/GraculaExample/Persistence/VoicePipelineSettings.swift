import Foundation

enum SpeechRecognitionBackend: String, Codable, CaseIterable, Sendable {
    case parakeet
    case whisper
}

enum SpeechSynthesisBackend: String, Codable, CaseIterable, Sendable {
    case disabled
    case appleSystem
    case voxcpmLocal
    case voxcpmServer
}

struct VoicePipelineSettings: Codable, Sendable {
    enum Defaults {
        static let whisperModelName = "small"
        static let whisperLanguageCode = "ru"
        static let parakeetModelName = "nvidia/parakeet-tdt-0.6b-v3"
        static let parakeetLanguageCode = "auto"
        static let speechSynthesisBackend: SpeechSynthesisBackend = .voxcpmLocal
        static let speakRecognizedText = true
        static let appleSystemVoiceLanguageCode = "ru-RU"
        static let appleSystemVoiceIdentifier: String? = nil
        static let voxcpmServerBaseURL = "http://127.0.0.1:8000"
        static let voxcpmModelName = "openbmb/VoxCPM2"
        static let voxcpmVoiceName = "default"
        static let voxcpmDevice = "cpu"
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
    var voxcpmServerBaseURL: String = Defaults.voxcpmServerBaseURL
    var voxcpmModelName: String = Defaults.voxcpmModelName
    var voxcpmVoiceName: String = Defaults.voxcpmVoiceName
    var voxcpmDevice: String = Defaults.voxcpmDevice

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
        do {
            let data = try Data(contentsOf: VoicePipelineSettingsStore.defaultFileURL())
            return try JSONDecoder().decode(VoicePipelineSettings.self, from: data)
        } catch {
            return VoicePipelineSettings()
        }
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
        case voxcpmServerBaseURL
        case voxcpmModelName
        case voxcpmVoiceName
        case voxcpmDevice
        case recognitionModelName
        case recognitionLanguageCode
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speechRecognitionBackend = try container.decodeIfPresent(SpeechRecognitionBackend.self, forKey: .speechRecognitionBackend) ?? .whisper
        whisperModelName = Self.normalizedWhisperModelName(
            try container.decodeIfPresent(String.self, forKey: .whisperModelName)
            ?? container.decodeIfPresent(String.self, forKey: .recognitionModelName)
            ?? Defaults.whisperModelName
        )
        whisperLanguageCode = try container.decodeIfPresent(String.self, forKey: .whisperLanguageCode)
            ?? container.decodeIfPresent(String.self, forKey: .recognitionLanguageCode)
            ?? Defaults.whisperLanguageCode
        parakeetModelName = try container.decodeIfPresent(String.self, forKey: .parakeetModelName)
            ?? Defaults.parakeetModelName
        parakeetLanguageCode = try container.decodeIfPresent(String.self, forKey: .parakeetLanguageCode)
            ?? Defaults.parakeetLanguageCode
        speechSynthesisBackend = try container.decodeIfPresent(SpeechSynthesisBackend.self, forKey: .speechSynthesisBackend)
            ?? Defaults.speechSynthesisBackend
        speakRecognizedText = try container.decodeIfPresent(Bool.self, forKey: .speakRecognizedText)
            ?? Defaults.speakRecognizedText
        appleSystemVoiceLanguageCode = try container.decodeIfPresent(String.self, forKey: .appleSystemVoiceLanguageCode)
            ?? Defaults.appleSystemVoiceLanguageCode
        appleSystemVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .appleSystemVoiceIdentifier)
            ?? Defaults.appleSystemVoiceIdentifier
        voxcpmServerBaseURL = try container.decodeIfPresent(String.self, forKey: .voxcpmServerBaseURL)
            ?? Defaults.voxcpmServerBaseURL
        voxcpmModelName = try container.decodeIfPresent(String.self, forKey: .voxcpmModelName)
            ?? Defaults.voxcpmModelName
        voxcpmVoiceName = try container.decodeIfPresent(String.self, forKey: .voxcpmVoiceName)
            ?? Defaults.voxcpmVoiceName
        voxcpmDevice = try container.decodeIfPresent(String.self, forKey: .voxcpmDevice)
            ?? Defaults.voxcpmDevice
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speechRecognitionBackend, forKey: .speechRecognitionBackend)
        try container.encode(whisperModelName, forKey: .whisperModelName)
        try container.encode(whisperLanguageCode, forKey: .whisperLanguageCode)
        try container.encode(parakeetModelName, forKey: .parakeetModelName)
        try container.encode(parakeetLanguageCode, forKey: .parakeetLanguageCode)
        try container.encode(speechSynthesisBackend, forKey: .speechSynthesisBackend)
        try container.encode(speakRecognizedText, forKey: .speakRecognizedText)
        try container.encode(appleSystemVoiceLanguageCode, forKey: .appleSystemVoiceLanguageCode)
        try container.encodeIfPresent(appleSystemVoiceIdentifier, forKey: .appleSystemVoiceIdentifier)
        try container.encode(voxcpmServerBaseURL, forKey: .voxcpmServerBaseURL)
        try container.encode(voxcpmModelName, forKey: .voxcpmModelName)
        try container.encode(voxcpmVoiceName, forKey: .voxcpmVoiceName)
        try container.encode(voxcpmDevice, forKey: .voxcpmDevice)
    }

    private static func normalizedWhisperModelName(_ modelName: String) -> String {
        switch modelName {
        case "tiny":
            return Defaults.whisperModelName
        default:
            return modelName
        }
    }
}

actor VoicePipelineSettingsStore {
    static let shared = VoicePipelineSettingsStore()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = VoicePipelineSettingsStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> VoicePipelineSettings {
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(VoicePipelineSettings.self, from: data)
        } catch {
            return VoicePipelineSettings()
        }
    }

    func save(_ settings: VoicePipelineSettings) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            log.warning("Failed to save voice pipeline settings: \(error.localizedDescription)")
        }
    }

    func filePath() -> String {
        fileURL.path
    }

    static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GraculaExample", isDirectory: true)
            .appendingPathComponent("voice-pipeline.json")
    }
}
