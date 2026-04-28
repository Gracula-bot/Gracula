import AgentSecurity
import Foundation
import Testing

@Test
func pathAllowlistAllowsFilesInsideApprovedDirectory() throws {
    let allowlist = PathAllowlist(approvedDirectories: [URL(fileURLWithPath: "/tmp/gracula")])

    let url = try allowlist.validate(URL(fileURLWithPath: "/tmp/gracula/notes/note.txt"))

    #expect(url.path == "/tmp/gracula/notes/note.txt")
}

@Test
func pathAllowlistRejectsFilesOutsideApprovedDirectory() {
    let allowlist = PathAllowlist(approvedDirectories: [URL(fileURLWithPath: "/tmp/gracula")])

    do {
        _ = try allowlist.validate(URL(fileURLWithPath: "/tmp/other/note.txt"))
        Issue.record("Expected pathNotAllowed")
    } catch SecurityError.pathNotAllowed(let path) {
        #expect(path == "/tmp/other/note.txt")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
