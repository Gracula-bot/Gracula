import AVFoundation

public actor AppleSpeechSynthesizer: SpeechSynthesizing {
    private let configuration: SpeechSynthesisConfiguration
    private let driver: any SpeechSynthesizerDriving

    public init(configuration: SpeechSynthesisConfiguration = .init()) {
        self.configuration = configuration
        self.driver = AVSpeechSynthesizerDriver()
    }

    init(
        configuration: SpeechSynthesisConfiguration = .init(),
        driver: any SpeechSynthesizerDriving
    ) {
        self.configuration = configuration
        self.driver = driver
    }

    public func speak(_ text: String) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        await driver.stop()
        await driver.speak(trimmedText, configuration: configuration)
    }

    public func stop() async {
        await driver.stop()
    }
}

protocol SpeechSynthesizerDriving: Sendable {
    func speak(_ text: String, configuration: SpeechSynthesisConfiguration) async
    func stop() async
}

private final class AVSpeechSynthesizerDriver: NSObject, SpeechSynthesizerDriving, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()

    @MainActor
    func speak(_ text: String, configuration: SpeechSynthesisConfiguration) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: configuration.languageCode)
        utterance.rate = configuration.rate
        utterance.pitchMultiplier = configuration.pitchMultiplier
        utterance.volume = configuration.volume
        synthesizer.speak(utterance)
    }

    @MainActor
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
