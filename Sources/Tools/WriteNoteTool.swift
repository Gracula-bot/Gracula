import Application
import Domain
import Foundation
import AgentSecurity
import Persistence

public struct WriteNoteTool: AgentTool {
    private let notesDirectory: URL
    private let allowlist: PathAllowlist
    private let fileSystem: any FileSystemClient

    public init(
        notesDirectory: URL,
        allowlist: PathAllowlist,
        fileSystem: any FileSystemClient
    ) {
        self.notesDirectory = notesDirectory
        self.allowlist = allowlist
        self.fileSystem = fileSystem
    }

    public let name = "write_note"
    public let description = "Write a UTF-8 note inside the approved notes directory."
    public let riskLevel = ToolRiskLevel.reversible

    public func run(_ call: ToolCall) async throws -> ToolResult {
        let text = try call.requiredStringArgument("text")
        let filename = sanitizedFilename(
            try call.optionalStringArgument("filename") ?? "note.txt"
        )
        let url = notesDirectory.appendingPathComponent(filename)
        let approvedURL = try allowlist.validate(url)
        try await fileSystem.writeFile(text, at: approvedURL)
        return .success("Wrote note: \(approvedURL.path)")
    }

    private func sanitizedFilename(_ filename: String) -> String {
        filename
            .split(separator: "/")
            .last
            .map(String.init) ?? "note.txt"
    }
}

private extension ToolCall {
    func optionalStringArgument(_ key: String) throws -> String? {
        guard let argument = arguments[key] else {
            return nil
        }

        guard case .string(let value) = argument else {
            throw ToolError.invalidArgument(key)
        }

        return value
    }
}
