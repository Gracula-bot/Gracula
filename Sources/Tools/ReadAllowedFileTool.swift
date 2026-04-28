import Application
import Domain
import Foundation
import AgentSecurity
import Persistence

public struct ReadAllowedFileTool: AgentTool {
    private let allowlist: PathAllowlist
    private let fileSystem: any FileSystemClient

    public init(allowlist: PathAllowlist, fileSystem: any FileSystemClient) {
        self.allowlist = allowlist
        self.fileSystem = fileSystem
    }

    public let name = "read_allowed_file"
    public let description = "Read a UTF-8 text file inside an approved directory."
    public let riskLevel = ToolRiskLevel.reversible

    public func run(_ call: ToolCall) async throws -> ToolResult {
        let path = try call.requiredStringArgument("path")
        let url = try allowlist.validate(URL(fileURLWithPath: path))
        let text = try await fileSystem.readFile(at: url)
        return .success(text)
    }
}
