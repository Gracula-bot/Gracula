import Foundation

actor VoicePipeline {
    private let settings: VoicePipelineSettings
    private let synthesizer: SpeechSynthesizing?
    private let allowsSystemFallback: Bool
    private let player: AudioPlaying
    private var voxcpmUnavailable = false

    init(
        settings: VoicePipelineSettings,
        player: AudioPlaying
    ) {
        self.settings = settings
        self.player = player

        switch settings.speechSynthesisBackend {
        case .disabled:
            self.synthesizer = nil
            self.allowsSystemFallback = false
        case .appleSystem:
            self.synthesizer = nil
            self.allowsSystemFallback = true
        case .voxcpmLocal:
            self.synthesizer = VoxCPMLocalSpeechSynthesizer(settings: settings)
            self.allowsSystemFallback = true
        case .voxcpmServer:
            guard let baseURL = URL(string: settings.voxcpmServerBaseURL) else {
                self.synthesizer = nil
                self.allowsSystemFallback = true
                log.warning("Invalid VoxCPM server URL: \(settings.voxcpmServerBaseURL)")
                return
            }

            self.synthesizer = VoxCPMSpeechSynthesizer(
                configuration: VoxCPMSpeechSynthesisConfiguration(
                    baseURL: baseURL,
                    modelName: settings.voxcpmModelName,
                    voiceName: settings.voxcpmVoiceName
                )
            )
            self.allowsSystemFallback = true
        }
    }

    func speakRecognizedText(_ text: String) async -> Bool {
        guard settings.speakRecognizedText else {
            return false
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }

        if let synthesizer, !voxcpmUnavailable {
            do {
                let audioURL = try await synthesizer.synthesizeSpeech(from: trimmedText)
                try await MainActor.run {
                    try player.play(fileURL: audioURL)
                }
                log.info("Spoken recognized text using VoxCPM. file=\(audioURL.lastPathComponent)")
                return true
            } catch {
                voxcpmUnavailable = true
                log.warning("VoxCPM synthesis failed; falling back to macOS voice. \(error.localizedDescription)")
            }
        }

        guard allowsSystemFallback else {
            log.warning("Speech synthesis is disabled or unavailable.")
            return false
        }

        do {
            try await MainActor.run {
                try AppleSystemSpeechSpeaker.shared.speak(
                    trimmedText,
                    languageCode: settings.appleSystemVoiceLanguageCode
                )
            }
            log.info("Spoken recognized text using macOS system voice.")
            return true
        } catch {
            log.warning("macOS voice synthesis failed: \(error.localizedDescription)")
            return false
        }
    }

    func prewarm() async {
        guard let synthesizer, !voxcpmUnavailable else {
            return
        }

        do {
            try await synthesizer.prewarm()
        } catch {
            voxcpmUnavailable = true
            log.warning("VoxCPM prewarm failed; macOS voice fallback will be used. \(error.localizedDescription)")
        }
    }
}
