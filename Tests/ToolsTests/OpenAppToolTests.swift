import Automation
import Domain
import Testing
import Tools

@Test
func openAppToolCallsAppOpeningClient() async throws {
    let opener = RecordingAppOpener()
    let tool = OpenAppTool(appOpening: opener)

    let result = try await tool.run(
        ToolCall(name: "open_app", arguments: ["appName": .string("Notes")], riskLevel: .safe)
    )

    #expect(result == .success("Opened app: Notes"))
    #expect(await opener.openedApps == ["Notes"])
}

private actor RecordingAppOpener: AppOpening {
    private(set) var openedApps: [String] = []

    func openApp(named name: String) async throws {
        openedApps.append(name)
    }
}
