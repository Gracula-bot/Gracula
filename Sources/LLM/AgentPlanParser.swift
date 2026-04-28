import Application
import Domain
import Foundation

public struct AgentPlanParser: Sendable {
    private let availableToolNames: Set<String>

    public init(availableTools: [ToolDescriptor]) {
        self.availableToolNames = Set(availableTools.map(\.name))
    }

    public func parse(userText: String, data: Data) throws -> AgentPlan {
        do {
            let response = try JSONDecoder().decode(PlannerJSONResponse.self, from: data)
            return try response.toAgentPlan(userText: userText, availableToolNames: availableToolNames)
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.invalidPlannerOutput("Invalid JSON: \(error)")
        }
    }

    public func parse(userText: String, text: String) throws -> AgentPlan {
        guard let data = text.data(using: .utf8) else {
            throw LLMError.invalidPlannerOutput("Planner output is not UTF-8")
        }
        return try parse(userText: userText, data: data)
    }
}

private struct PlannerJSONResponse: Decodable {
    let summary: String
    let toolCalls: [PlannerToolCall]

    func toAgentPlan(userText: String, availableToolNames: Set<String>) throws -> AgentPlan {
        let calls = try toolCalls.map { try $0.toToolCall(availableToolNames: availableToolNames) }
        return AgentPlan(userText: userText, summary: summary, toolCalls: calls)
    }
}

private struct PlannerToolCall: Decodable {
    let name: String
    let riskLevel: String
    let arguments: [String: PlannerToolArgument]

    func toToolCall(availableToolNames: Set<String>) throws -> ToolCall {
        guard availableToolNames.contains(name) else {
            throw LLMError.unknownTool(name)
        }

        guard let risk = ToolRiskLevel(rawValue: riskLevel) else {
            throw LLMError.invalidRiskLevel(riskLevel)
        }

        return ToolCall(
            name: name,
            arguments: arguments.mapValues(\.toolArgument),
            riskLevel: risk
        )
    }
}

private enum PlannerToolArgument: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringArray([String])

    var toolArgument: ToolArgument {
        switch self {
        case .string(let value):
            .string(value)
        case .int(let value):
            .int(value)
        case .double(let value):
            .double(value)
        case .bool(let value):
            .bool(value)
        case .stringArray(let value):
            .stringArray(value)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case string
        case int
        case double
        case bool
        case stringArray
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presentKeys = container.allKeys
        guard presentKeys.count == 1, let key = presentKeys.first else {
            throw LLMError.invalidPlannerOutput("Tool arguments must have exactly one typed value")
        }

        switch key {
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .int))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .double))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .bool))
        case .stringArray:
            self = .stringArray(try container.decode([String].self, forKey: .stringArray))
        }
    }
}

