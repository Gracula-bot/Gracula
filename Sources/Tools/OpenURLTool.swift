import Automation
import Application
import Domain
import Foundation

public struct OpenURLTool: AgentTool {
    private let urlOpening: any URLOpening

    public init(urlOpening: any URLOpening) {
        self.urlOpening = urlOpening
    }

    public let name = "open_url"
    public let description = "Open a URL in the default browser."
    public let riskLevel = ToolRiskLevel.safe

    public func run(_ call: ToolCall) async throws -> ToolResult {
        let rawURL = try call.requiredStringArgument("url")
        guard let url = URL(string: rawURL), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw ToolError.invalidArgument("url")
        }

        try await urlOpening.open(url)
        return .success("Opened URL: \(url.absoluteString)")
    }
}
