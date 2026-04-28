import Automation
import Application
import Domain

public struct OpenAppTool: AgentTool {
    private let appOpening: any AppOpening

    public init(appOpening: any AppOpening) {
        self.appOpening = appOpening
    }

    public let name = "open_app"
    public let description = "Open a macOS application by name."
    public let riskLevel = ToolRiskLevel.safe

    public func run(_ call: ToolCall) async throws -> ToolResult {
        let appName = try call.requiredStringArgument("appName")
        try await appOpening.openApp(named: appName)
        return .success("Opened app: \(appName)")
    }
}
