import Foundation

public struct TelegramBusinessSettings: Sendable, Equatable {
    public let enabled: Bool
    public let botToken: String
    public let businessConnectionId: String

    public init(
        enabled: Bool = false,
        botToken: String = "",
        businessConnectionId: String = ""
    ) {
        self.enabled = enabled
        self.botToken = botToken
        self.businessConnectionId = businessConnectionId
    }
}
