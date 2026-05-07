import Application
import LLM
import Shared
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

                if let pendingReply = viewModel.pendingTelegramReply {
                    TelegramReplyPanel(
                        reply: pendingReply,
                        onSend: {
                            Task {
                                await viewModel.sendPendingTelegramReply()
                            }
                        },
                        onCancel: {
                            Task {
                                await viewModel.cancelPendingTelegramReply()
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
                    BotSettingsView(
                        settings: botSettings,
                        llmMetrics: viewModel.llmMetrics,
                        llmRequestLog: viewModel.llmRequestLog,
                        llmResponseLog: viewModel.llmResponseLog
                    )
                }

                TraceLogPreviewView(
                    traceID: viewModel.latestTraceID,
                    events: viewModel.traceEvents
                )

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

private struct TelegramReplyPanel: View {
    let reply: PendingTelegramReply
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Telegram Reply Draft", systemImage: "paperplane")
                    .font(.headline)
                Spacer()
                Text(reply.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Chat")
                        .foregroundStyle(.secondary)
                    Text(reply.chatName)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Reply")
                        .foregroundStyle(.secondary)
                    Text(reply.messageText)
                        .textSelection(.enabled)
                }
            }
            .font(.callout)

            HStack {
                Button {
                    onSend()
                } label: {
                    Label("Отправить", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onCancel()
                } label: {
                    Label("Отменить", systemImage: "xmark.circle")
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BotSettingsView: View {
    let settings: BotSettingsSnapshot
    let llmMetrics: LLMRequestMetrics?
    let llmRequestLog: LoggedLLMRequest?
    let llmResponseLog: LoggedLLMResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bot Settings and Permissions")
                .font(.headline)

            settingsGrid
            llmRequest
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
            settingsRow("Temperature", String(settings.llmTemperature))
        }
        .font(.callout)
    }

    private var llmRequest: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last LLM Request")
                .font(.subheadline.weight(.semibold))

            if let llmMetrics {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    settingsRow("Provider", llmMetrics.provider)
                    settingsRow("Resolved model", llmMetrics.model)
                    settingsRow("Temperature", String(llmMetrics.temperature))
                    settingsRow("Prompt tokens", tokenValue(llmMetrics.promptTokens))
                    settingsRow("Cached prompt tokens", tokenValue(llmMetrics.cachedPromptTokens))
                    settingsRow("Completion tokens", tokenValue(llmMetrics.completionTokens))
                    settingsRow("Total tokens", tokenValue(llmMetrics.totalTokens))
                    settingsRow("Latency (ms)", tokenValue(llmMetrics.latencyMilliseconds))
                    settingsRow("Finish reason", llmMetrics.finishReason ?? "Not available")
                    settingsRow("Cost (USD)", costValue(llmMetrics.costUSD))
                }
                .font(.callout)

                if let llmRequestLog {
                    VStack(alignment: .leading, spacing: 6) {
                        settingsRow("Endpoint", llmRequestLog.endpoint)

                        Text("Payload")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView([.horizontal, .vertical]) {
                            Text(llmRequestLog.body)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 180, maxHeight: 280)
                        .padding(8)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                if let llmResponseLog {
                    VStack(alignment: .leading, spacing: 6) {
                        settingsRow("Response model", llmResponseLog.model)
                        settingsRow("Response finish reason", llmResponseLog.finishReason ?? "Not available")
                        settingsRow("Response latency (ms)", tokenValue(llmResponseLog.latencyMilliseconds))

                        Text("Response body")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView([.horizontal, .vertical]) {
                            Text(llmResponseLog.body)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                        .padding(8)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                Text("No LLM request has been recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    private func tokenValue(_ value: Int?) -> String {
        value.map(String.init) ?? "Not available"
    }

    private func costValue(_ value: Double?) -> String {
        guard let value else {
            return "Not available"
        }
        return String(format: "%.6f", value)
    }
}

private struct TraceLogPreviewView: View {
    let traceID: String?
    let events: [TraceEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Request Trace")
                .font(.headline)

            if let traceID {
                Text("trace_id: \(traceID)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            if events.isEmpty {
                Text("No trace events captured for the latest request.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(event.event)
                                        .font(.system(.caption, design: .monospaced))
                                    Text(event.level.rawValue.uppercased())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(event.component)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(prettyPayload(event.payload))
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 360)
            }
        }
    }

    private func prettyPayload(_ payload: [String: TraceLogValue]) -> String {
        let event = TraceLogValue.object(payload)
        guard let data = try? JSONEncoder().encode(event),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return "{}"
        }
        return String(decoding: prettyData, as: UTF8.self)
    }
}
