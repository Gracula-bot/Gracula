import SwiftUI

struct OpenClawControlView: View {
    @ObservedObject var controller: OpenClawLocalController

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenClaw Bot")
                    .font(.headline)
                Text(controller.statusText)
                    .foregroundStyle(controller.isRunning ? .green : .secondary)
                if controller.isPreparingLocalModel {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(controller.localModelStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                jsonEntries: $jsonEntries
            )

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

            DisclosureGroup("Environment .env", isExpanded: $isEnvironmentExpanded) {
                editableSettingsList($environmentEntries)
            }
            .disclosureGroupStyle(.automatic)

            DisclosureGroup("openclaw.json", isExpanded: $isJSONExpanded) {
                editableSettingsList($jsonEntries)
            }
            .disclosureGroupStyle(.automatic)

            DisclosureGroup("Soul, Agent, and Workspace Files", isExpanded: $isWorkspaceExpanded) {
                editableWorkspaceFiles($workspaceFiles)
            }
            .disclosureGroupStyle(.automatic)
        }
        .onAppear(perform: loadEditableEntries)
        .onChange(of: snapshot) { _, _ in
            loadEditableEntries()
        }
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

    private func editableWorkspaceFiles(_ files: Binding<[OpenClawWorkspaceFile]>) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(files) { $file in
                VStack(alignment: .leading, spacing: 6) {
                    Text(file.relativePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $file.contents)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: editorHeight(for: file.contents))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        }
                }
            }
        }
        .padding(.top, 6)
    }

    private func editorHeight(for contents: String) -> CGFloat {
        let lineCount = max(6, min(28, contents.split(separator: "\n", omittingEmptySubsequences: false).count))
        return CGFloat(lineCount * 18 + 24)
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
