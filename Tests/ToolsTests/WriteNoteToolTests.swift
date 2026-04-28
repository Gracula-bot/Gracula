import AgentSecurity
import Domain
import Foundation
import Persistence
import Testing
import Tools

@Test
func writeNoteToolWritesInsideApprovedNotesDirectory() async throws {
    let fileSystem = FakeFileSystem(files: [:])
    let notesDirectory = URL(fileURLWithPath: "/tmp/gracula/notes")
    let tool = WriteNoteTool(
        notesDirectory: notesDirectory,
        allowlist: PathAllowlist(approvedDirectories: [URL(fileURLWithPath: "/tmp/gracula")]),
        fileSystem: fileSystem
    )

    let result = try await tool.run(
        ToolCall(
            name: "write_note",
            arguments: [
                "text": .string("hello"),
                "filename": .string("today.txt")
            ],
            riskLevel: .reversible
        )
    )

    #expect(result == .success("Wrote note: /tmp/gracula/notes/today.txt"))
    #expect(await fileSystem.files["/tmp/gracula/notes/today.txt"] == "hello")
}

@Test
func writeNoteToolSanitizesFilenamePathComponents() async throws {
    let fileSystem = FakeFileSystem(files: [:])
    let notesDirectory = URL(fileURLWithPath: "/tmp/gracula/notes")
    let tool = WriteNoteTool(
        notesDirectory: notesDirectory,
        allowlist: PathAllowlist(approvedDirectories: [URL(fileURLWithPath: "/tmp/gracula")]),
        fileSystem: fileSystem
    )

    _ = try await tool.run(
        ToolCall(
            name: "write_note",
            arguments: [
                "text": .string("hello"),
                "filename": .string("../../escape.txt")
            ],
            riskLevel: .reversible
        )
    )

    #expect(await fileSystem.files["/tmp/gracula/notes/escape.txt"] == "hello")
}

actor FakeFileSystem: FileSystemClient {
    private(set) var files: [String: String]

    init(files: [String: String]) {
        self.files = files
    }

    func readFile(at url: URL) async throws -> String {
        files[url.path] ?? ""
    }

    func writeFile(_ text: String, at url: URL) async throws {
        files[url.path] = text
    }
}
