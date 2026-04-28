public struct SpeechSynthesisConfiguration: Sendable, Equatable {
    public let languageCode: String
    public let rate: Float
    public let pitchMultiplier: Float
    public let volume: Float

    public init(
        languageCode: String = "ru-RU",
        rate: Float = 0.48,
        pitchMultiplier: Float = 1.0,
        volume: Float = 1.0
    ) {
        self.languageCode = languageCode
        self.rate = rate
        self.pitchMultiplier = pitchMultiplier
        self.volume = volume
    }
}

