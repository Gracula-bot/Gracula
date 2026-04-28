import Foundation

public struct ConfirmationChallenge: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let summary: String
    public let requiredPhrase: String?

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        requiredPhrase: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.requiredPhrase = requiredPhrase
    }
}

