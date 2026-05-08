import Persistence
import SwiftUI

struct OpenClawControlView: View {
    @ObservedObject var controller: OpenClawLocalController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenClaw Bot")
                        .font(.headline)
                    Text(controller.statusText)
                        .foregroundStyle(controller.isRunning ? .green : .secondary)
                    Text(controller.bootstrapStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if controller.isRunning {
                        controller.stop()
                    } else {
                        controller.start()
                    }
                } label: {
                    Label(
                        controller.isRunning
                            ? (controller.isSendingChat ? "Chat Running" : "Stop Bot")
                            : "Start Bot",
                        systemImage: controller.isRunning ? "stop.fill" : "play.fill"
                    )
                    .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isSendingChat)
            }

            if !controller.bootstrapDependencyItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(controller.bootstrapDependencyItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.name)
                                .font(.caption.monospaced())
                            Text(item.status)
                                .font(.caption)
                                .foregroundStyle(item.available ? .green : .secondary)
                            if !item.detail.isEmpty {
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct OpenClawSettingsView: View {
    @ObservedObject var controller: OpenClawLocalController
    @State private var isRuntimeExpanded = true
    @State private var isPermissionsExpanded = true
    @State private var isToolsExpanded = true
    @State private var isEnvironmentExpanded = false
    @State private var isJSONExpanded = false
    @State private var isWorkspaceExpanded = false
    @State private var environmentEntries: [OpenClawEditableSetting] = []
    @State private var jsonEntries: [OpenClawEditableSetting] = []
    @State private var workspaceFiles: [OpenClawWorkspaceFile] = []
    @State private var telegramLoginCode = ""
    @State private var telegramPassword = ""

    private var snapshot: OpenClawSettingsSnapshot {
        controller.settingsSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("OpenClaw Settings, Tools, and Instruments")
                    .font(.headline)
                Spacer()
                Button {
                    controller.reloadSettings()
                    loadEditableEntries()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                Button {
                    controller.applySettings(
                        environmentEntries: environmentEntries,
                        jsonEntries: jsonEntries,
                        workspaceFiles: workspaceFiles
                    )
                    loadEditableEntries()
                } label: {
                    Label("Apply", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await controller.testSelectedModel(
                            environmentEntries: environmentEntries,
                            jsonEntries: jsonEntries,
                            workspaceFiles: workspaceFiles
                        )
                    }
                } label: {
                    Label("Test model", systemImage: "checkmark.seal")
                }
                .buttonStyle(.bordered)
            }

            Text(controller.settingsStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            BrainSettingsSection(
                snapshot: snapshot,
                environmentEntries: $environmentEntries,
                jsonEntries: $jsonEntries,
                canonicalPlistPath: ProjectRuntimeLayout.resolveDefault().configurationFileURL.path,
                applyDraftSettings: applyCurrentDraftSettings
            )

            telegramUserAPIControls
            telegramBusinessAPIControls

            DisclosureGroup("Runtime", isExpanded: $isRuntimeExpanded) {
                settingsRows(snapshot.runtimeRows)
            }
            .disclosureGroupStyle(.automatic)

            DisclosureGroup("Permissions", isExpanded: $isPermissionsExpanded) {
                settingsRows(snapshot.permissionRows)
            }
            .disclosureGroupStyle(.automatic)

            DisclosureGroup("Tools and Instruments", isExpanded: $isToolsExpanded) {
                if snapshot.toolRows.isEmpty {
                    Text("No tools, plugins, hooks, or skills settings found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    settingsRows(snapshot.toolRows)
                }
            }
            .disclosureGroupStyle(.automatic)

            DisclosureGroup("Canonical Environment", isExpanded: $isEnvironmentExpanded) {
                editableSettingsList($environmentEntries)
            }
            .disclosureGroupStyle(.automatic)

            DisclosureGroup("Canonical Settings", isExpanded: $isJSONExpanded) {
                editableSettingsList($jsonEntries)
            }
            .disclosureGroupStyle(.automatic)

            DisclosureGroup("Soul, Agent, and Workspace Files", isExpanded: $isWorkspaceExpanded) {
                EditableWorkspaceFilesView(files: $workspaceFiles)
            }
            .disclosureGroupStyle(.automatic)
        }
        .onAppear(perform: loadEditableEntries)
        .onChange(of: snapshot) { _, _ in
            loadEditableEntries()
        }
    }

    private var telegramUserAPIControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Telegram User API")
                            .font(.headline)
                        ConnectionStatusBadge(
                            title: controller.isTelegramUserConnected ? "Connected" : "Not connected",
                            isConnected: controller.isTelegramUserConnected
                        )
                    }
                    Text(controller.telegramUserStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        await controller.startTelegramUserAPI()
                    }
                } label: {
                    Label("Start TDLib", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.bordered)
                .disabled(controller.isStartingTelegramUserAPI)
                Button {
                    Task {
                        await controller.refreshTelegramUserDialogs()
                    }
                } label: {
                    Label("Refresh dialogs", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                TextField("Login code", text: $telegramLoginCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Button("Submit code") {
                    let code = telegramLoginCode
                    telegramLoginCode = ""
                    Task {
                        await controller.submitTelegramUserCode(code)
                    }
                }
                .disabled(
                    telegramLoginCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || controller.telegramUserAuthorizationState != .waitingForCode
                )
            }

            HStack(spacing: 8) {
                SecureField("2FA password", text: $telegramPassword)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Button("Submit 2FA") {
                    let password = telegramPassword
                    telegramPassword = ""
                    Task {
                        await controller.submitTelegramUserPassword(password)
                    }
                }
                .disabled(
                    telegramPassword.isEmpty
                        || controller.telegramUserAuthorizationState != .waitingForPassword
                )
            }

            if !controller.telegramUserDialogs.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    ForEach(controller.telegramUserDialogs, id: \.id) { dialog in
                        GridRow {
                            Text(dialog.id)
                                .foregroundStyle(.secondary)
                            Text(dialog.title)
                            Text(dialog.type)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(.vertical, 6)
    }

    private var telegramBusinessAPIControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Telegram Business")
                            .font(.headline)
                        ConnectionStatusBadge(
                            title: controller.telegramBusinessConnected ? "Connected" : "Not connected",
                            isConnected: controller.telegramBusinessConnected
                        )
                    }
                    Text(controller.telegramBusinessStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        await controller.testTelegramBusinessConnection()
                    }
                } label: {
                    Label("Test Business", systemImage: "bolt.horizontal.circle")
                }
                .buttonStyle(.bordered)
                .disabled(controller.isTestingTelegramBusiness)
            }
        }
        .padding(.vertical, 6)
    }

    private func applyCurrentDraftSettings() -> String {
        controller.applySettings(
            environmentEntries: environmentEntries,
            jsonEntries: jsonEntries,
            workspaceFiles: workspaceFiles
        )
        loadEditableEntries()
        return controller.settingsStatusText
    }

    private func settingsRows(_ rows: [OpenClawSettingsRow]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.name)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.top, 6)
    }

    private func editableSettingsList(_ entries: Binding<[OpenClawEditableSetting]>) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { $entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.key)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(entry.kind.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if entry.isSecret {
                        SecureField("Value", text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                    } else if entry.kind == .array || entry.kind == .object {
                        TextEditor(text: $entry.value)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: jsonEditorHeight(for: entry.value), maxHeight: 220)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.quaternary)
                            }
                    } else {
                        TextField("Value", text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    private func jsonEditorHeight(for contents: String) -> CGFloat {
        let lineCount = max(4, min(10, contents.split(separator: "\n", omittingEmptySubsequences: false).count))
        return CGFloat(lineCount * 18 + 24)
    }

    private func loadEditableEntries() {
        environmentEntries = snapshot.environmentEntries
        jsonEntries = snapshot.jsonEntries
        workspaceFiles = snapshot.workspaceFiles
    }
}

private struct ConnectionStatusBadge: View {
    let title: String
    let isConnected: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isConnected ? Color.green.opacity(0.18) : Color.secondary.opacity(0.16))
            .foregroundStyle(isConnected ? Color.green : Color.secondary)
            .clipShape(Capsule())
    }
}

private struct EditableWorkspaceFilesView: View {
    @Binding var files: [OpenClawWorkspaceFile]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach($files, id: \.id) { file in
                let workspaceFile = file.wrappedValue
                VStack(alignment: .leading, spacing: 6) {
                    Text(workspaceFile.relativePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(workspaceFileSummary(workspaceFile))
                        .font(.caption2)
                        .foregroundStyle(
                            workspaceFile.existsOnDisk
                                ? AnyShapeStyle(.tertiary)
                                : AnyShapeStyle(Color.orange)
                        )
                        .textSelection(.enabled)
                    Text(workspaceFile.absolutePath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                    TextEditor(text: file.contents)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: editorHeight(for: workspaceFile.contents))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        }
                }
            }
        }
        .padding(.top, 6)
    }

    private func workspaceFileSummary(_ file: OpenClawWorkspaceFile) -> String {
        let status = file.existsOnDisk ? "Loaded" : "Missing placeholder"
        return "\(status) • \(file.byteCount) bytes"
    }

    private func editorHeight(for contents: String) -> CGFloat {
        let lineCount = max(6, min(28, contents.split(separator: "\n", omittingEmptySubsequences: false).count))
        return CGFloat(lineCount * 18 + 24)
    }
}
