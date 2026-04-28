import Foundation

enum SpeechRecognitionBackend: String, Codable, CaseIterable, Sendable {
    case parakeet
    case whisper
}

struct VoicePipelineSettings: Codable, Sendable {
    var speechRecognitionBackend: SpeechRecognitionBackend = .whisper
    var whisperModelName: String = "tiny"
    var whisperLanguageCode: String = "ru"
    var parakeetModelName: String = "nvidia/parakeet-tdt-0.6b-v3"
    var parakeetLanguageCode: String = "auto"

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
        case recognitionModelName
        case recognitionLanguageCode
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speechRecognitionBackend = try container.decodeIfPresent(SpeechRecognitionBackend.self, forKey: .speechRecognitionBackend) ?? .whisper
        whisperModelName = try container.decodeIfPresent(String.self, forKey: .whisperModelName)
            ?? container.decodeIfPresent(String.self, forKey: .recognitionModelName)
            ?? "tiny"
        whisperLanguageCode = try container.decodeIfPresent(String.self, forKey: .whisperLanguageCode)
            ?? container.decodeIfPresent(String.self, forKey: .recognitionLanguageCode)
            ?? "ru"
        parakeetModelName = try container.decodeIfPresent(String.self, forKey: .parakeetModelName)
            ?? "nvidia/parakeet-tdt-0.6b-v3"
        parakeetLanguageCode = try container.decodeIfPresent(String.self, forKey: .parakeetLanguageCode)
            ?? "auto"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speechRecognitionBackend, forKey: .speechRecognitionBackend)
        try container.encode(whisperModelName, forKey: .whisperModelName)
        try container.encode(whisperLanguageCode, forKey: .whisperLanguageCode)
        try container.encode(parakeetModelName, forKey: .parakeetModelName)
        try container.encode(parakeetLanguageCode, forKey: .parakeetLanguageCode)
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
