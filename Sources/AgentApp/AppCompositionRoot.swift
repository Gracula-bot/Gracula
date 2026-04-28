import AppShell

struct AppCompositionRoot {
    @MainActor
    func makeAgentView() -> AgentView {
        AgentView(viewModel: AgentViewModel())
    }
}
