import Testing
import Voice

@Test
func speechSynthesisConfigurationDefaultsAreUsableForRussianVoice() {
    let configuration = SpeechSynthesisConfiguration()

    #expect(configuration.languageCode == "ru-RU")
    #expect(configuration.rate > 0)
    #expect(configuration.pitchMultiplier == 1.0)
    #expect(configuration.volume == 1.0)
}

@Test
func speechSynthesisConfigurationSupportsCustomValues() {
    let configuration = SpeechSynthesisConfiguration(
        languageCode: "en-US",
        rate: 0.4,
        pitchMultiplier: 1.1,
        volume: 0.8
    )

    #expect(configuration.languageCode == "en-US")
    #expect(configuration.rate == 0.4)
    #expect(configuration.pitchMultiplier == 1.1)
    #expect(configuration.volume == 0.8)
}

