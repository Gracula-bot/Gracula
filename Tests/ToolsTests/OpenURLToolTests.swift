import Automation
import Domain
import Foundation
import Testing
import Tools

@Test
func openURLToolCallsURLOpeningClient() async throws {
    let opener = RecordingURLOpener()
    let tool = OpenURLTool(urlOpening: opener)

    let result = try await tool.run(
        ToolCall(name: "open_url", arguments: ["url": .string("https://apple.com")], riskLevel: .safe)
    )

    #expect(result == .success("Opened URL: https://apple.com"))
    #expect(await opener.openedURLs == [URL(string: "https://apple.com")!])
}

@Test
func openURLToolRejectsNonWebURL() async {
    let tool = OpenURLTool(urlOpening: RecordingURLOpener())

    do {
        _ = try await tool.run(
            ToolCall(name: "open_url", arguments: ["url": .string("file:///etc/passwd")], riskLevel: .safe)
        )
        Issue.record("Expected invalid URL")
    } catch ToolError.invalidArgument(let key) {
        #expect(key == "url")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private actor RecordingURLOpener: URLOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) async throws {
        openedURLs.append(url)
    }
}
