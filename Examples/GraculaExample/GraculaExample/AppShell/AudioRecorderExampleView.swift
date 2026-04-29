import SwiftUI

struct AudioRecorderExampleView: View {
    @StateObject private var viewModel: AudioRecorderViewModel
    @StateObject private var openClawController = OpenClawLocalController()

    init(viewModel: AudioRecorderViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                OpenClawControlView(controller: openClawController)

                OpenClawChatView(controller: openClawController)

                Divider()

                if !viewModel.inputDevices.isEmpty {
                    Picker("Input Source", selection: $viewModel.selectedInputDeviceID) {
                        ForEach(viewModel.inputDevices) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isRecording || viewModel.isTranscribing)
                }

                if !viewModel.systemVoices.isEmpty {
                    Picker("Bot Voice", selection: $viewModel.selectedSystemVoiceID) {
                        ForEach(viewModel.systemVoices) { voice in
                            Text(voice.displayName).tag(voice.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isRecording || viewModel.isTranscribing)
                }

                Button {
                    Task {
                        await viewModel.toggleRecording { message in
                            await openClawController.sendChatMessage(message)
                        }
                    }
                } label: {
                    Label(viewModel.buttonTitle, systemImage: viewModel.buttonSystemImage)
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isTranscribing)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.headline)
                    Text(viewModel.statusText)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recognized Text")
                        .font(.headline)
                    Text(viewModel.recognizedText)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let fileSourceText = viewModel.latestFileSourceText {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("File Source")
                                .font(.headline)
                            Spacer()
                            Link(destination: URL(filePath: fileSourceText)) {
                                Label("Open", systemImage: "play.circle")
                            }
                            Button {
                                viewModel.revealLatestFileInFinder()
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder")
                            }
                        }
                        Text(fileSourceText)
                            .textSelection(.enabled)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !viewModel.recordings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recorded Files")
                            .font(.headline)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(viewModel.recordings, id: \.self) { url in
                                    Text(url.lastPathComponent)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 120)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Diagnostics")
                            .font(.headline)
                        Spacer()
                        Button {
                            viewModel.revealDiagnosticsInFinder()
                        } label: {
                            Label("Reveal Log", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    ScrollView {
                        Text(viewModel.diagnostics.joined(separator: "\n"))
                            .textSelection(.enabled)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 140)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 620, minHeight: 420)
        .task {
            await viewModel.loadRecordings()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Gracula Audio Recorder")
                .font(.title)
            Text("Record a microphone message, save it as a file, and show recognized speech.")
                .foregroundStyle(.secondary)
        }
    }
}
