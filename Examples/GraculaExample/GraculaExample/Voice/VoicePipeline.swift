import Foundation

actor VoicePipeline {
    private let settings: VoicePipelineSettings
    private let allowsSystemFallback: Bool
    private let player: AudioPlaying

    init(
        settings: VoicePipelineSettings,
        player: AudioPlaying
    ) {
        self.settings = settings
        self.player = player

        switch settings.speechSynthesisBackend {
        case .disabled:
            self.allowsSystemFallback = false
        case .appleSystem:
            self.allowsSystemFallback = true
        }
    }

    func speakRecognizedText(_ text: String) async -> Bool {
        guard settings.speakRecognizedText else {
            log.info("[latency] Speech synthesis disabled by settings.")
            return false
        }

        return await speak(text)
    }

    func speakLocalNotificationText(_ text: String) async -> Bool {
        await speak(text)
    }

    func prewarm() async {
        // Apple system speech does not require explicit warmup, but callers use this hook.
    }

    private func speak(_ text: String) async -> Bool {
        let startedAt = PerformanceLog.checkpoint()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            log.info("[latency] Speech synthesis skipped because text is empty.")
            return false
        }

        log.info("[latency] Speech stop-before-speak starting.")
        await stopSpeaking()
        log.info("[latency] Speech stop-before-speak finished in \(PerformanceLog.elapsedDescription(since: startedAt))")

        guard allowsSystemFallback else {
            log.warning("Speech synthesis is disabled or unavailable.")
            log.info("[latency] Speech synthesis unavailable after \(PerformanceLog.elapsedDescription(since: startedAt))")
            return false
        }

        do {
            log.info("[latency] macOS speech enqueue starting; characters=\(trimmedText.count)")
            try await MainActor.run {
                try AppleSystemSpeechSpeaker.shared.speak(
                    trimmedText,
                    languageCode: settings.appleSystemVoiceLanguageCode,
                    voiceIdentifier: settings.appleSystemVoiceIdentifier,
                    rate: settings.appleSystemSpeechRate,
                    pitch: settings.appleSystemSpeechPitch
                )
            }
            log.info("Spoken recognized text using macOS system voice.")
            log.info("[latency] macOS speech enqueued in \(PerformanceLog.elapsedDescription(since: startedAt)); characters=\(trimmedText.count)")
            return true
        } catch {
            log.warning("macOS voice synthesis failed: \(error.localizedDescription)")
            log.info("[latency] macOS speech failed after \(PerformanceLog.elapsedDescription(since: startedAt))")
            return false
        }
    }

    func stopSpeaking() async {
        await MainActor.run {
            AppleSystemSpeechSpeaker.shared.stop()
            player.stop()
        }
    }
}
