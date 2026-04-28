import AgentSecurity
import Domain
import Foundation
import Persistence
import Testing
import Tools

@Test
func readAllowedFileToolReadsApprovedFile() async throws {
    let fileSystem = FakeFileSystem(files: ["/tmp/gracula/note.txt": "hello"])
    let tool = ReadAllowedFileTool(
        allowlist: PathAllowlist(approvedDirectories: [URL(fileURLWithPath: "/tmp/gracula")]),
        fileSystem: fileSystem
    )

    let result = try await tool.run(
        ToolCall(
            name: "read_allowed_file",
            arguments: ["path": .string("/tmp/gracula/note.txt")],
            riskLevel: .reversible
        )
    )

    #expect(result == .success("hello"))
}

@Test
func readAllowedFileToolRejectsDisallowedPath() async {
    let tool = ReadAllowedFileTool(
        allowlist: PathAllowlist(approvedDirectories: [URL(fileURLWithPath: "/tmp/gracula")]),
        fileSystem: FakeFileSystem(files: [:])
    )

    do {
        _ = try await tool.run(
            ToolCall(
                name: "read_allowed_file",
                arguments: ["path": .string("/tmp/other/note.txt")],
                riskLevel: .reversible
            )
        )
        Issue.record("Expected path rejection")
    } catch SecurityError.pathNotAllowed(let path) {
        #expect(path == "/tmp/other/note.txt")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
