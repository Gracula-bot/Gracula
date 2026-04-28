import SwiftUI

public struct AgentView: View {
    @StateObject private var viewModel: AgentViewModel

    public init(viewModel: AgentViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gracula")
                .font(.title)

            Text(viewModel.statusText)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 240)
    }
}

