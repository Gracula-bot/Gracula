import SwiftUI

public struct AgentView: View {
    @StateObject private var viewModel: AgentViewModel

    public init(viewModel: AgentViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
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

                if let botSettings = viewModel.botSettings {
                    BotSettingsView(settings: botSettings)
                }

                AuditLogPreviewView(entries: viewModel.auditEntries)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 620)
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

private struct BotSettingsView: View {
    let settings: BotSettingsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bot Settings and Permissions")
                .font(.headline)

            settingsGrid
            permissions
            tools
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            settingsRow("Planner", settings.plannerMode)
            settingsRow(settings.llmEndpointEnvironmentKey, settings.llmEndpoint)
            settingsRow(settings.llmModelEnvironmentKey, settings.llmModel)
        }
        .font(.callout)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.subheadline.weight(.semibold))

            settingsLine("Auto-allowed reversible tools", settings.reversibleAllowlistedTools)
            settingsLine("Approved file directories", settings.approvedDirectories)
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Registered Tools")
                .font(.subheadline.weight(.semibold))

            ForEach(settings.tools, id: \.name) { tool in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(tool.name)
                            .font(.system(.callout, design: .monospaced))
                        Text(tool.riskLevel.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func settingsRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func settingsLine(_ label: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
    }
}
