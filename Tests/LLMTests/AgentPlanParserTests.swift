import Application
import Domain
import LLM
import Testing

@Test
func agentPlanParserParsesValidPlannerJSON() throws {
    let parser = AgentPlanParser(availableTools: [
        ToolDescriptor(name: "open_url", description: "Open URL", riskLevel: .safe)
    ])

    let plan = try parser.parse(
        userText: "Open apple.com",
        text: """
        {
          "summary": "Open the requested website",
          "toolCalls": [
            {
              "name": "open_url",
              "riskLevel": "safe",
              "arguments": {
                "url": { "string": "https://apple.com" },
                "foreground": { "bool": true }
              }
            }
          ]
        }
        """
    )

    #expect(plan.userText == "Open apple.com")
    #expect(plan.summary == "Open the requested website")
    #expect(plan.toolCalls.count == 1)
    #expect(plan.toolCalls[0].name == "open_url")
    #expect(plan.toolCalls[0].arguments["url"] == .string("https://apple.com"))
    #expect(plan.toolCalls[0].arguments["foreground"] == .bool(true))
    #expect(plan.highestRiskLevel == .safe)
}

@Test
func agentPlanParserRejectsInvalidJSON() {
    let parser = AgentPlanParser(availableTools: [])

    do {
        _ = try parser.parse(userText: "bad", text: "not json")
        Issue.record("Expected invalid planner output")
    } catch LLMError.invalidPlannerOutput {
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func agentPlanParserRejectsUnknownTools() {
    let parser = AgentPlanParser(availableTools: [])

    do {
        _ = try parser.parse(
            userText: "Open",
            text: """
            {
              "summary": "Open",
              "toolCalls": [
                { "name": "open_url", "riskLevel": "safe", "arguments": {} }
              ]
            }
            """
        )
        Issue.record("Expected unknown tool")
    } catch LLMError.unknownTool(let name) {
        #expect(name == "open_url")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func agentPlanParserRejectsInvalidRiskLevel() {
    let parser = AgentPlanParser(availableTools: [
        ToolDescriptor(name: "open_url", description: "Open URL", riskLevel: .safe)
    ])

    do {
        _ = try parser.parse(
            userText: "Open",
            text: """
            {
              "summary": "Open",
              "toolCalls": [
                { "name": "open_url", "riskLevel": "dangerous", "arguments": {} }
              ]
            }
            """
        )
        Issue.record("Expected invalid risk level")
    } catch LLMError.invalidRiskLevel(let riskLevel) {
        #expect(riskLevel == "dangerous")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

