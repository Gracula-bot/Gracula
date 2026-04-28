import SwiftUI

public struct AgentView: View {
    @StateObject private var viewModel: AgentViewModel

    public init(viewModel: AgentViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(spacing: 8) {
                TextField("Enter command", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task {
                            await viewModel.run()
                        }
                    }

                Button("Run") {
                    Task {
                        await viewModel.run()
                    }
                }
                .disabled(!viewModel.canRun)

                Button("Stop Speaking") {
                    Task {
                        await viewModel.stopSpeaking()
                    }
                }
            }

            if let challenge = viewModel.pendingChallenge {
                ConfirmationView(
                    title: challenge.title,
                    summary: challenge.summary,
                    requiredPhrase: challenge.requiredPhrase,
                    confirmationText: $viewModel.confirmationText,
                    onApprove: {
                        Task {
                            await viewModel.approvePendingPlan()
                        }
                    },
                    onReject: {
                        Task {
                            await viewModel.rejectPendingPlan()
                        }
                    }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Result")
                    .font(.headline)
                Text(viewModel.resultText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }

            AuditLogPreviewView(entries: viewModel.auditEntries)
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Gracula")
                .font(.title)

            Text(viewModel.statusText)
                .foregroundStyle(.secondary)
        }
    }
}
