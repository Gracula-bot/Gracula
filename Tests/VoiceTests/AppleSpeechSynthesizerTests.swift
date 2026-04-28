@testable import Voice
import Testing

@Test
func appleSpeechSynthesizerIgnoresBlankText() async throws {
    let driver = RecordingSpeechDriver()
    let synthesizer = AppleSpeechSynthesizer(driver: driver)

    try await synthesizer.speak("   ")

    #expect(await driver.spokenTexts.isEmpty)
    #expect(await driver.stopCount == 0)
}

@Test
func appleSpeechSynthesizerStopsBeforeSpeakingText() async throws {
    let driver = RecordingSpeechDriver()
    let synthesizer = AppleSpeechSynthesizer(driver: driver)

    try await synthesizer.speak("Hello")

    #expect(await driver.spokenTexts == ["Hello"])
    #expect(await driver.stopCount == 1)
}

@Test
func appleSpeechSynthesizerStopDelegatesToDriver() async {
    let driver = RecordingSpeechDriver()
    let synthesizer = AppleSpeechSynthesizer(driver: driver)

    await synthesizer.stop()

    #expect(await driver.stopCount == 1)
}

private actor RecordingSpeechDriver: SpeechSynthesizerDriving {
    private(set) var spokenTexts: [String] = []
    private(set) var stopCount = 0

    func speak(_ text: String, configuration: SpeechSynthesisConfiguration) async {
        spokenTexts.append(text)
    }

    func stop() async {
        stopCount += 1
    }
}
