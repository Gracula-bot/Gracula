import Application
import Domain

struct FakePlanner: Planning {
    let plan: AgentPlan

    func makePlan(userText: String, context: ConversationContext) async throws -> AgentPlan {
        plan
    }
}

struct FakePolicyChecker: PolicyChecking {
    let decision: PolicyDecision

    func evaluate(_ plan: AgentPlan) async throws -> PolicyDecision {
        decision
    }
}

struct FakeTool: AgentTool {
    let name: String
    let result: ToolResult
    let riskLevel: ToolRiskLevel

    init(name: String = "fake_tool", result: ToolResult, riskLevel: ToolRiskLevel = .safe) {
        self.name = name
        self.result = result
        self.riskLevel = riskLevel
    }

    var description: String {
        "Fake test tool"
    }

    func run(_ call: ToolCall) async throws -> ToolResult {
        result
    }
}

actor FakeToolExecutor: ToolExecuting {
    private let results: [ToolResult]
    private(set) var executionCount = 0

    init(results: [ToolResult]) {
        self.results = results
    }

    func execute(_ plan: AgentPlan) async throws -> [ToolResult] {
        executionCount += 1
        return results
    }
}

