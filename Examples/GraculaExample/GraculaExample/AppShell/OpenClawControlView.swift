import SwiftUI

struct OpenClawControlView: View {
    @ObservedObject var controller: OpenClawLocalController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenClaw Bot")
                        .font(.headline)
                    Text(controller.statusText)
                        .foregroundStyle(controller.isRunning ? .green : .secondary)
                }

                Spacer()

                Button {
                    Task {
                        await controller.refreshHealth()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    controller.openDashboard()
                } label: {
                    Label("Dashboard", systemImage: "safari")
                }
                .disabled(!controller.isRunning)

                Button {
                    if controller.isRunning {
                        controller.stop()
                    } else {
                        controller.start()
                    }
                } label: {
                    Label(
                        controller.isRunning ? "Stop Bot" : "Start Bot",
                        systemImage: controller.isRunning ? "stop.fill" : "play.fill"
                    )
                    .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                statusRow("Gateway", controller.gatewayStatus)
                statusRow("Stream Bridge", controller.streamBridgeStatus)
                statusRow("Config", controller.configDirectory.path)
                statusRow("Workspace", controller.workspaceDirectory.path)
            }
            .font(.system(.caption, design: .monospaced))

            ScrollView {
                Text(controller.logLines.joined(separator: "\n"))
                    .textSelection(.enabled)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 160)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
