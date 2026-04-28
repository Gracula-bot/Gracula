import Foundation

@MainActor
public final class AgentViewModel: ObservableObject {
    @Published public private(set) var statusText: String

    public init(statusText: String = "Base architecture ready") {
        self.statusText = statusText
    }
}

