import AppKit
import AVFoundation
import Foundation

@MainActor
final class AudioRecorderViewModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var statusText = "Ready"
    @Published private(set) var latestFileSourceText: String?
    @Published private(set) var recognizedText = "No recognized speech yet."
    @Published private(set) var recordings: [URL] = []
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var systemVoices: [SystemSpeechVoice] = []
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var notificationMonitorStatus = "Not started"
    @Published private(set) var latestNotificationText = "No local notifications announced yet."
    @Published var selectedInputDeviceID: String?
    @Published var selectedSystemVoiceID: String {
        didSet {
            guard didFinishInitializing else {
                return
            }
            guard !isApplyingVoiceSettings else {
                return
            }
            applySelectedSystemVoice()
        }
    }

    private let recorder: DiskAudioRecorder
    private var transcriber: FileSpeechTranscriber
    private var voicePipeline: VoicePipeline
    private var voiceSettings: VoicePipelineSettings
    private let diagnosticsFileURL: URL
    private let notificationReader = LocalNotificationReader()
    private var notificationMonitorTask: Task<Void, Never>?
    private var localNotificationProcessor: ((LocalNotification, String) async -> String?)?
    private var lastSeenNotificationID: Int64 = 0
    private var didFinishInitializing = false
    private var isApplyingVoiceSettings = false

    init(recorder: DiskAudioRecorder) {
        self.recorder = recorder
        let loadedSettings = VoicePipelineSettings.loadFromDisk()
        self.voiceSettings = loadedSettings
        self.selectedSystemVoiceID = loadedSettings.appleSystemVoiceIdentifier ?? ""
        self.transcriber = FileSpeechTranscriber(settings: loadedSettings)
        self.voicePipeline = VoicePipeline(
            settings: loadedSettings,
            player: SystemAudioPlayer()
        )
        self.diagnosticsFileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GraculaExample", isDirectory: true)
            .appendingPathComponent("recorder-diagnostics.log")
        log.info("AudioRecorderViewModel initialized. appLog=\(log.logFilePath)")
        appendDiagnostic("Voice settings file: \(VoicePipelineSettingsStore.defaultFileURL().path)")
        appendDiagnostic(
            "Speech synthesis: backend=\(loadedSettings.speechSynthesisBackend.rawValue), speakRecognizedText=\(loadedSettings.speakRecognizedText)"
        )
        refreshSystemVoices()
        didFinishInitializing = true
        Task {
            await transcriber.prewarm()
        }
        Task {
            await voicePipeline.prewarm()
        }
        restartNotificationMonitor()
    }

    deinit {
        notificationMonitorTask?.cancel()
    }

    var buttonTitle: String {
        isRecording ? "Stop Recording" : "Record Message"
    }

    var buttonSystemImage: String {
        isRecording ? "stop.fill" : "mic.fill"
    }

    func toggleRecording(
        sendRecognizedText: ((String) async -> String?)? = nil,
        reportError: ((String) -> Void)? = nil
    ) async {
        guard !isTranscribing else {
            return
        }

        if isRecording {
            await stopRecording(sendRecognizedText: sendRecognizedText, reportError: reportError)
        } else {
            await voicePipeline.stopSpeaking()
            await startRecording(reportError: reportError)
        }
    }

    func currentVoiceSettings() -> VoicePipelineSettings {
        voiceSettings
    }

    func reloadVoiceSettings() {
        applyVoiceSettings(VoicePipelineSettings.loadFromDisk(), persist: false)
    }

    func applyVoiceSettings(_ settings: VoicePipelineSettings, persist: Bool = true) {
        let selectedVoiceID = settings.appleSystemVoiceIdentifier ?? ""
        isApplyingVoiceSettings = true
        voiceSettings = settings
        transcriber = FileSpeechTranscriber(settings: settings)
        voicePipeline = VoicePipeline(
            settings: settings,
            player: SystemAudioPlayer()
        )
        selectedSystemVoiceID = selectedVoiceID
        isApplyingVoiceSettings = false

        appendDiagnostic("Voice settings updated.")

        Task {
            if persist {
                await VoicePipelineSettingsStore.shared.save(settings)
            }
            await transcriber.prewarm()
        }
        restartNotificationMonitor()
    }

    func loadRecordings() async {
        let startedAt = PerformanceLog.checkpoint()
        do {
            refreshInputDevices()
            recordings = try recorder.savedRecordings()
            appendDiagnostic("Loaded \(recordings.count) recording file(s).")
            appendDiagnostic("Speech runtime: \(transcriber.runtimeSummary)")
            log.debug("loadRecordings completed in \(PerformanceLog.elapsedDescription(since: startedAt)); recordings=\(self.recordings.count); devices=\(self.inputDevices.count)")
        } catch {
            statusText = "Could not load recordings: \(error.localizedDescription)"
            appendDiagnostic("Load recordings failed: \(error.localizedDescription)")
            log.error("loadRecordings failed after \(PerformanceLog.elapsedDescription(since: startedAt)): \(error.localizedDescription)")
        }
    }

    func refreshInputDevices() {
        let startedAt = PerformanceLog.checkpoint()
        inputDevices = recorder.availableInputDevices()
        if selectedInputDeviceID == nil {
            selectedInputDeviceID = recorder.defaultInputDevice()?.id ?? inputDevices.first?.id
        } else if let selectedInputDeviceID,
                  !inputDevices.contains(where: { $0.id == selectedInputDeviceID }) {
            self.selectedInputDeviceID = recorder.defaultInputDevice()?.id ?? inputDevices.first?.id
        }
        log.debug("refreshInputDevices completed in \(PerformanceLog.elapsedDescription(since: startedAt)); devices=\(self.inputDevices.count); selected=\(self.selectedInputDeviceID ?? "nil")")
    }

    func refreshSystemVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .map(SystemSpeechVoice.init)
            .sorted { first, second in
                if first.languageCode == second.languageCode {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }
                return first.languageCode.localizedCaseInsensitiveCompare(second.languageCode) == .orderedAscending
            }
        systemVoices = voices

        if selectedSystemVoiceID.isEmpty {
            selectedSystemVoiceID = voices.first(where: { $0.languageCode == voiceSettings.appleSystemVoiceLanguageCode })?.id
                ?? voices.first?.id
                ?? ""
        } else if !voices.contains(where: { $0.id == selectedSystemVoiceID }) {
            selectedSystemVoiceID = voices.first(where: { $0.languageCode == voiceSettings.appleSystemVoiceLanguageCode })?.id
                ?? voices.first?.id
                ?? ""
        }
    }

    func revealLatestFileInFinder() {
        guard let latestFileSourceText else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(filePath: latestFileSourceText)
        ])
    }

    func revealDiagnosticsInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([diagnosticsFileURL])
    }

    func setLocalNotificationProcessor(_ processor: @escaping (LocalNotification, String) async -> String?) {
        localNotificationProcessor = processor
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func restartNotificationMonitor() {
        notificationMonitorTask?.cancel()
        notificationMonitorTask = nil

        guard voiceSettings.announceLocalNotifications else {
            notificationMonitorStatus = "Disabled"
            appendDiagnostic("Local notification announcements disabled.")
            return
        }

        notificationMonitorStatus = "Starting..."
        appendDiagnostic("Starting local notification monitor.")
        let pollInterval = max(1.0, voiceSettings.localNotificationPollIntervalSeconds)

        notificationMonitorTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let latestID = try await notificationReader.latestNotificationID()
                await MainActor.run {
                    self.lastSeenNotificationID = latestID
                    self.notificationMonitorStatus = "Watching for new notifications"
                    self.appendDiagnostic("Local notification monitor ready. baselineID=\(latestID)")
                }
            } catch {
                await MainActor.run {
                    self.notificationMonitorStatus = "Needs Full Disk Access"
                    self.appendDiagnostic("Local notification monitor failed to start: \(error.localizedDescription)")
                }
                return
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                guard !Task.isCancelled else {
                    return
                }

                do {
                    let notifications = try await notificationReader.notifications(
                        after: await MainActor.run { self.lastSeenNotificationID },
                        limit: 5
                    )
                    guard !notifications.isEmpty else {
                        continue
                    }

                    for notification in notifications {
                        await MainActor.run {
                            self.lastSeenNotificationID = max(self.lastSeenNotificationID, notification.id)
                        }
                        await self.announce(notification)
                    }
                } catch {
                    await MainActor.run {
                        self.notificationMonitorStatus = "Read failed"
                        self.appendDiagnostic("Local notification monitor read failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func startRecording(reportError: ((String) -> Void)?) async {
        let startedAt = PerformanceLog.checkpoint()
        do {
            refreshInputDevices()
            latestFileSourceText = nil
            recognizedText = "No recognized speech yet."
            let selectedName = selectedInputDeviceName()
            appendDiagnostic("Starting recording. selectedDevice=\(selectedName), id=\(selectedInputDeviceID ?? "nil")")
            let url = try await recorder.start(deviceID: selectedInputDeviceID)
            latestFileSourceText = url.path(percentEncoded: false)
            isRecording = true
            statusText = "Recording from \(selectedName)..."
            appendDiagnostic("Recording file opened: \(url.path(percentEncoded: false))")
            log.debug("startRecording completed in \(PerformanceLog.elapsedDescription(since: startedAt)); device=\(selectedName); file=\(url.lastPathComponent)")
        } catch {
            isRecording = false
            statusText = "Could not start recording: \(error.localizedDescription)"
            appendDiagnostic("Start failed: \(error.localizedDescription)")
            reportError?(error.localizedDescription)
            log.error("startRecording failed after \(PerformanceLog.elapsedDescription(since: startedAt)): \(error.localizedDescription)")
        }
    }

    private func announce(_ notification: LocalNotification) async {
        let text = notificationSpokenText(notification)
        guard !text.isEmpty else {
            await MainActor.run {
                self.lastSeenNotificationID = max(self.lastSeenNotificationID, notification.id)
            }
            return
        }

        await MainActor.run {
            self.latestNotificationText = text
            self.notificationMonitorStatus = "Sending notification to OpenClaw"
            self.appendDiagnostic("Sending local notification to OpenClaw. app=\(notification.appIdentifier), id=\(notification.id)")
        }

        if let localNotificationProcessor,
           let reply = await localNotificationProcessor(notification, text)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reply.isEmpty {
            await MainActor.run {
                self.latestNotificationText = reply
                self.notificationMonitorStatus = "Speaking OpenClaw notification reply"
                self.appendDiagnostic("OpenClaw processed notification. replyCharacters=\(reply.count)")
            }
            let didSpeak = await voicePipeline.speakLocalNotificationText(reply)

            await MainActor.run {
                self.notificationMonitorStatus = didSpeak ? "Watching for new notifications" : "Speech unavailable"
                if !didSpeak {
                    self.appendDiagnostic("Local notification was processed by OpenClaw but speech synthesis did not run.")
                }
            }
        } else {
            await MainActor.run {
                self.notificationMonitorStatus = "OpenClaw unavailable"
                self.appendDiagnostic("OpenClaw did not return a notification reply; notification was not spoken.")
            }
        }
    }

    private func notificationSpokenText(_ notification: LocalNotification) -> String {
        let parts: [String]
        if voiceSettings.includeNotificationAppName {
            parts = [
                "Уведомление",
                notification.spokenText
            ]
        } else {
            parts = [
                notification.title,
                notification.subtitle,
                notification.body
            ]
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private func stopRecording(
        sendRecognizedText: ((String) async -> String?)?,
        reportError: ((String) -> Void)?
    ) async {
        let startedAt = PerformanceLog.checkpoint()
        do {
            appendDiagnostic("Stopping capture.")
            let stopStartedAt = PerformanceLog.checkpoint()
            let result = try recorder.stop()
            let url = result.url
            latestFileSourceText = url.path(percentEncoded: false)
            isRecording = false
            statusText = "Saved audio message."
            appendDiagnostic(
                "Stopped. packets=\(result.packetCount), bytes=\(result.byteSize), stopStatus=\(result.stopStatus), disposeStatus=\(result.disposeStatus), closeStatus=\(result.closeStatus), file=\(url.path(percentEncoded: false))"
            )
            log.debug("recorder.stop completed in \(PerformanceLog.elapsedDescription(since: stopStartedAt)); packets=\(result.packetCount); bytes=\(result.byteSize); stopStatus=\(result.stopStatus); disposeStatus=\(result.disposeStatus); closeStatus=\(result.closeStatus)")
            recordings = try recorder.savedRecordings()

            guard result.packetCount > 0, result.byteSize > 512 else {
                recognizedText = "No audio frames were captured. Try a different input source."
                statusText = "Saved file, but no audio was captured."
                appendDiagnostic("Skipping transcription because recording has no captured packets.")
                log.warning("Skipping speech transcription after \(PerformanceLog.elapsedDescription(since: startedAt)); no packets captured")
                return
            }

            isTranscribing = true
            statusText = "Saved audio message. Transcribing..."
            appendDiagnostic("Starting speech transcription.")
            let transcriptionStartedAt = PerformanceLog.checkpoint()
            recognizedText = try await transcriber.transcribeFile(at: url)
            appendDiagnostic("Speech transcription finished. characters=\(recognizedText.count)")
            log.debug("Speech transcription completed in \(PerformanceLog.elapsedDescription(since: transcriptionStartedAt)); characters=\(self.recognizedText.count)")

            let trimmedRecognizedText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRecognizedText.isEmpty else {
                statusText = "Saved audio message, but no speech was recognized."
                isTranscribing = false
                appendDiagnostic("Skipping OpenClaw because recognized text is empty.")
                return
            }

            let speechText: String
            if let sendRecognizedText {
                statusText = "Saved and transcribed audio message. Asking OpenClaw..."
                appendDiagnostic("Sending recognized text to OpenClaw. characters=\(trimmedRecognizedText.count)")
                let openClawStartedAt = PerformanceLog.checkpoint()
                log.info("[latency] OpenClaw send started; recognizedCharacters=\(trimmedRecognizedText.count)")
                if let reply = await sendRecognizedText(trimmedRecognizedText)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reply.isEmpty {
                    speechText = reply
                    let openClawElapsed = PerformanceLog.elapsedDescription(since: openClawStartedAt)
                    appendDiagnostic("OpenClaw reply received. characters=\(reply.count), elapsed=\(openClawElapsed)")
                    log.info("[latency] OpenClaw reply delivered to recorder pipeline in \(openClawElapsed); replyCharacters=\(reply.count)")
                    statusText = "OpenClaw replied. Speaking..."
                } else {
                    speechText = "OpenClaw did not return a spoken reply."
                    let openClawElapsed = PerformanceLog.elapsedDescription(since: openClawStartedAt)
                    appendDiagnostic("OpenClaw did not return a speakable reply. elapsed=\(openClawElapsed)")
                    log.warning("[latency] OpenClaw returned no speakable reply after \(openClawElapsed)")
                    statusText = "OpenClaw did not return a spoken reply."
                }
            } else {
                speechText = trimmedRecognizedText
                statusText = "Saved and transcribed audio message. Speaking..."
            }

            let speechStartedAt = PerformanceLog.checkpoint()
            appendDiagnostic("Speech synthesis starting. characters=\(speechText.count)")
            log.info("[latency] Speech synthesis requested; characters=\(speechText.count)")
            let didSpeak = await voicePipeline.speakRecognizedText(speechText)
            let speechElapsed = PerformanceLog.elapsedDescription(since: speechStartedAt)
            statusText = didSpeak ? "Saved, transcribed, answered, and spoken." : "Saved and transcribed audio message."
            isTranscribing = false
            if didSpeak {
                appendDiagnostic("Speech synthesis finished. elapsed=\(speechElapsed)")
                log.info("[latency] Speech synthesis completed in \(speechElapsed)")
            } else {
                appendDiagnostic("Speech synthesis skipped or failed. elapsed=\(speechElapsed)")
                log.info("[latency] Speech synthesis skipped/failed in \(speechElapsed)")
            }

            log.info("stopRecording completed in \(PerformanceLog.elapsedDescription(since: startedAt)); totalBytes=\(result.byteSize)")
        } catch {
            isRecording = false
            isTranscribing = false
            statusText = "Could not finish recording: \(error.localizedDescription)"
            appendDiagnostic("Stop/transcribe failed: \(error.localizedDescription)")
            reportError?(error.localizedDescription)
            log.error("stopRecording failed after \(PerformanceLog.elapsedDescription(since: startedAt)): \(error.localizedDescription)")
        }
    }

    private func selectedInputDeviceName() -> String {
        guard let selectedInputDeviceID,
              let device = inputDevices.first(where: { $0.id == selectedInputDeviceID }) else {
            return "Default Input"
        }
        return device.name
    }

    private func applySelectedSystemVoice() {
        guard let selectedVoice = systemVoices.first(where: { $0.id == selectedSystemVoiceID }) else {
            return
        }

        voiceSettings.speechSynthesisBackend = .appleSystem
        voiceSettings.appleSystemVoiceIdentifier = selectedVoice.id
        voiceSettings.appleSystemVoiceLanguageCode = selectedVoice.languageCode
        voicePipeline = VoicePipeline(
            settings: voiceSettings,
            player: SystemAudioPlayer()
        )
        appendDiagnostic("Selected macOS bot voice: \(selectedVoice.name) (\(selectedVoice.languageCode)).")
        Task {
            await VoicePipelineSettingsStore.shared.save(voiceSettings)
        }
    }

    private func appendDiagnostic(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        diagnostics.append(line)
        if diagnostics.count > 80 {
            diagnostics.removeFirst(diagnostics.count - 80)
        }
        persistDiagnostic(line)
        log.debug(message)
    }

    private func persistDiagnostic(_ line: String) {
        do {
            let directory = diagnosticsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let data = Data((line + "\n").utf8)
            if FileManager.default.fileExists(atPath: diagnosticsFileURL.path) {
                let handle = try FileHandle(forWritingTo: diagnosticsFileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: diagnosticsFileURL)
            }
        } catch {
            diagnostics.append("Failed to write diagnostics log: \(error.localizedDescription)")
        }
    }
}

struct SystemSpeechVoice: Identifiable, Equatable {
    let id: String
    let name: String
    let languageCode: String

    init(voice: AVSpeechSynthesisVoice) {
        self.id = voice.identifier
        self.name = voice.name
        self.languageCode = voice.language
    }

    var displayName: String {
        "\(name) (\(languageCode))"
    }
}
