import Application
import Foundation

public struct BotSettingsSnapshot: Sendable, Equatable {
    public let plannerMode: String
    public let llmEndpoint: String
    public let llmModel: String
    public let llmEndpointEnvironmentKey: String
    public let llmModelEnvironmentKey: String
    public let reversibleAllowlistedTools: [String]
    public let approvedDirectories: [String]
    public let tools: [ToolDescriptor]

    public init(
        plannerMode: String,
        llmEndpoint: String,
        llmModel: String,
        llmEndpointEnvironmentKey: String = "GRACULA_LLM_ENDPOINT",
        llmModelEnvironmentKey: String = "GRACULA_LLM_MODEL",
        reversibleAllowlistedTools: [String],
        approvedDirectories: [URL],
        tools: [ToolDescriptor]
    ) {
        self.plannerMode = plannerMode
        self.llmEndpoint = llmEndpoint
        self.llmModel = llmModel
        self.llmEndpointEnvironmentKey = llmEndpointEnvironmentKey
        self.llmModelEnvironmentKey = llmModelEnvironmentKey
        self.reversibleAllowlistedTools = reversibleAllowlistedTools.sorted()
        self.approvedDirectories = approvedDirectories
            .map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
            .sorted()
        self.tools = tools.sorted { $0.name < $1.name }
    }
}
