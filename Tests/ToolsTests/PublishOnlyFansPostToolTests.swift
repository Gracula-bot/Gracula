import Automation
import Domain
import Testing
import Tools

@Test
func publishOnlyFansPostToolPublishesProvidedText() async throws {
    let poster = RecordingOnlyFansPoster()
    let tool = PublishOnlyFansPostTool(poster: poster)

    let result = try await tool.run(
        ToolCall(
            name: "publish_onlyfans_post",
            arguments: ["text": .string("  Test post  ")],
            riskLevel: .externalCommunication
        )
    )

    #expect(result == .success("Published OnlyFans post."))
    #expect(await poster.publishedPosts == ["Test post"])
}

@Test
func publishOnlyFansPostToolRejectsBlankText() async {
    let tool = PublishOnlyFansPostTool(poster: RecordingOnlyFansPoster())

    do {
        _ = try await tool.run(
            ToolCall(
                name: "publish_onlyfans_post",
                arguments: ["text": .string("   ")],
                riskLevel: .externalCommunication
            )
        )
        Issue.record("Expected invalid text")
    } catch ToolError.invalidArgument(let key) {
        #expect(key == "text")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private actor RecordingOnlyFansPoster: OnlyFansPosting {
    private(set) var publishedPosts: [String] = []

    func publishPost(text: String) async throws {
        publishedPosts.append(text)
    }
}
