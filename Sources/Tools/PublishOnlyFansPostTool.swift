import Application
import Automation
import Domain
import Foundation

public struct PublishOnlyFansPostTool: AgentTool {
    private let poster: any OnlyFansPosting

    public init(poster: any OnlyFansPosting) {
        self.poster = poster
    }

    public let name = "publish_onlyfans_post"
    public let description = "Publish the provided text as an OnlyFans post in the browser. Use only when the user explicitly asks to publish/send/post to OnlyFans."
    public let riskLevel = ToolRiskLevel.externalCommunication

    public func run(_ call: ToolCall) async throws -> ToolResult {
        let text = try call.requiredStringArgument("text")
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ToolError.invalidArgument("text")
        }

        try await poster.publishPost(text: trimmedText)
        return .success("Published OnlyFans post.")
    }
}
