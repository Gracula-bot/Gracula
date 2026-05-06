@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Persistence

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

struct RecordingStopResult {
    let url: URL
    let packetCount: Int64
    let byteSize: Int64
    let stopStatus: OSStatus
    let disposeStatus: OSStatus
    let closeStatus: OSStatus
}

@MainActor
final class DiskAudioRecorder {
    private static let startRetryDelaysNanos: [UInt64] = [
        150_000_000,
        350_000_000
    ]

    private var recorder: AudioQueueDiskRecorder?
    private var lastStartedDeviceID: String?
    private var lastStartFallbackMessage: String?

    func availableInputDevices() -> [AudioInputDevice] {
        CoreAudioInputDevices.devices()
    }

    func defaultInputDevice() -> AudioInputDevice? {
        CoreAudioInputDevices.defaultInputDevice()
    }

    func resolvedInputDeviceID() -> String? {
        lastStartedDeviceID
    }

    func fallbackStartMessage() -> String? {
        lastStartFallbackMessage
    }

    func start(deviceID: String?) async throws -> URL {
        let startedAt = PerformanceLog.checkpoint()
        try await requestMicrophonePermission()
        guard recorder == nil else {
            throw AudioRecordingError.alreadyRecording
        }

        let availableDevices = availableInputDevices()
        let defaultDeviceID = defaultInputDevice()?.id
        let preferredDeviceID = deviceID ?? defaultDeviceID
        let candidateDeviceIDs = prioritizedInputDeviceIDs(
            preferredDeviceID: preferredDeviceID,
            defaultDeviceID: defaultDeviceID,
            availableDevices: availableDevices
        )
        guard !candidateDeviceIDs.isEmpty else {
            throw AudioRecordingError.inputDeviceUnavailable
        }

        let url = try makeRecordingURL()
        let deviceNames = Dictionary(uniqueKeysWithValues: availableDevices.map { ($0.id, $0.name) })
        lastStartedDeviceID = nil
        lastStartFallbackMessage = nil

        var firstError: Error?
        for candidateDeviceID in candidateDeviceIDs {
            var candidateError: Error?

            for (attemptIndex, retryDelay) in Self.startRetryDelaysNanos.enumeratedWithTrailingAttempt() {
                let recorder = AudioQueueDiskRecorder(deviceUID: candidateDeviceID, fileURL: url)
                do {
                    try recorder.start()
                    self.recorder = recorder
                    lastStartedDeviceID = candidateDeviceID
                    if let preferredDeviceID,
                       candidateDeviceID != preferredDeviceID {
                        let previousName = deviceNames[preferredDeviceID] ?? "Selected Input"
                        let fallbackName = deviceNames[candidateDeviceID] ?? "Default Input"
                        lastStartFallbackMessage = "Selected microphone \(previousName) failed to start. Switched to \(fallbackName)."
                    }
                    log.debug("DiskAudioRecorder.start completed in \(PerformanceLog.elapsedDescription(since: startedAt)); deviceID=\(candidateDeviceID); file=\(url.lastPathComponent)")
                    return url
                } catch {
                    recorder.abortStart()
                    candidateError = error

                    guard shouldRetryStart(after: error, attemptIndex: attemptIndex) else {
                        break
                    }

                    let retryAttemptNumber = attemptIndex + 2
                    log.warning(
                        "Retrying AudioQueue start after transient failure; deviceID=\(candidateDeviceID); nextAttempt=\(retryAttemptNumber); error=\(error.localizedDescription)"
                    )
                    try? await Task.sleep(nanoseconds: retryDelay)
                }
            }

            if firstError == nil {
                firstError = candidateError
            }
            if let candidateError, !shouldTryNextInputDevice(after: candidateError) {
                throw candidateError
            }
        }

        try? FileManager.default.removeItem(at: url)
        throw firstError ?? AudioRecordingError.inputDeviceUnavailable
    }

    func stop() throws -> RecordingStopResult {
        let startedAt = PerformanceLog.checkpoint()
        guard let recorder else {
            throw AudioRecordingError.notRecording
        }

        self.recorder = nil
        let result = try recorder.stop()
        log.debug("DiskAudioRecorder.stop completed in \(PerformanceLog.elapsedDescription(since: startedAt)); packets=\(result.packetCount); bytes=\(result.byteSize)")
        return result
    }

    private func prioritizedInputDeviceIDs(
        preferredDeviceID: String?,
        defaultDeviceID: String?,
        availableDevices: [AudioInputDevice]
    ) -> [String] {
        var orderedIDs: [String] = []
        let appendIfNeeded: (String?) -> Void = { candidateID in
            guard let candidateID, !candidateID.isEmpty, !orderedIDs.contains(candidateID) else {
                return
            }
            orderedIDs.append(candidateID)
        }

        appendIfNeeded(preferredDeviceID)
        appendIfNeeded(defaultDeviceID)
        for device in availableDevices {
            appendIfNeeded(device.id)
        }
        return orderedIDs
    }

    private func shouldRetryStart(after error: Error, attemptIndex: Int) -> Bool {
        guard attemptIndex < Self.startRetryDelaysNanos.count else {
            return false
        }
        guard let recordingError = error as? AudioRecordingError else {
            return false
        }
        return recordingError.isTransientStartFailure
    }

    private func shouldTryNextInputDevice(after error: Error) -> Bool {
        guard let recordingError = error as? AudioRecordingError else {
            return false
        }
        return recordingError.isAudioQueueError
    }

    func savedRecordings() throws -> [URL] {
        let startedAt = PerformanceLog.checkpoint()
        let directory = try recordingsDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let recordings = urls
            .filter { $0.pathExtension == "caf" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
        log.debug("savedRecordings enumerated \(recordings.count) file(s) in \(PerformanceLog.elapsedDescription(since: startedAt))")
        return recordings
    }

    private func requestMicrophonePermission() async throws {
        let startedAt = PerformanceLog.checkpoint()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            log.debug("Microphone permission already authorized; check completed in \(PerformanceLog.elapsedDescription(since: startedAt))")
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                log.warning("Microphone permission denied after request in \(PerformanceLog.elapsedDescription(since: startedAt))")
                throw AudioRecordingError.microphonePermissionDenied
            }
            log.debug("Microphone permission granted in \(PerformanceLog.elapsedDescription(since: startedAt))")
        case .denied, .restricted:
            log.warning("Microphone permission unavailable in \(PerformanceLog.elapsedDescription(since: startedAt))")
            throw AudioRecordingError.microphonePermissionDenied
        @unknown default:
            log.warning("Microphone permission unknown-state failure in \(PerformanceLog.elapsedDescription(since: startedAt))")
            throw AudioRecordingError.microphonePermissionDenied
        }
    }

    private func makeRecordingURL() throws -> URL {
        let directory = try recordingsDirectory()
        return directory.appendingPathComponent("\(Self.timestamp()).caf")
    }

    private func recordingsDirectory() throws -> URL {
        let directory = ProjectRuntimeLayout.resolveDefault().runtimeDirectoryURL
            .appendingPathComponent("recordings", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

enum AudioRecordingError: LocalizedError {
    case alreadyRecording
    case microphonePermissionDenied
    case inputDeviceUnavailable
    case audioQueueError(operation: String, status: OSStatus)
    case notRecording

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already active."
        case .microphonePermissionDenied:
            return "Microphone permission was denied."
        case .inputDeviceUnavailable:
            return "Selected microphone is unavailable."
        case .audioQueueError(let operation, let status):
            return "\(operation) failed: \(Self.describe(status: status))"
        case .notRecording:
            return "No recording is active."
        }
    }

    private static func describe(status: OSStatus) -> String {
        if status == 2003329396 {
            return "The selected microphone could not start (`what`). It may be busy, disconnected, muted by the system, or in an invalid state. Try another input source."
        }
        return "OSStatus \(status). Choose a different microphone input source."
    }

    var isAudioQueueError: Bool {
        if case .audioQueueError = self {
            return true
        }
        return false
    }

    var isTransientStartFailure: Bool {
        if case .audioQueueError(let operation, let status) = self {
            return operation == "AudioQueueStart" && status == 2003329396
        }
        return false
    }
}

private enum CoreAudioInputDevices {
    static func devices() -> [AudioInputDevice] {
        allAudioDeviceIDs()
            .filter { inputChannelCount(for: $0) > 0 }
            .filter { isUsableMicrophone(deviceID: $0) }
            .compactMap { deviceID in
                guard let uid = stringProperty(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyDeviceUID,
                    scope: kAudioObjectPropertyScopeGlobal
                ) else {
                    return nil
                }

                let name = stringProperty(
                    objectID: deviceID,
                    selector: kAudioObjectPropertyName,
                    scope: kAudioObjectPropertyScopeGlobal
                ) ?? uid

                return AudioInputDevice(id: uid, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    static func defaultInputDevice() -> AudioInputDevice? {
        var deviceID = AudioDeviceID()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, inputChannelCount(for: deviceID) > 0 else {
            return nil
        }

        guard isUsableMicrophone(deviceID: deviceID) else {
            return devices().first
        }

        guard let uid = stringProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        ) else {
            return nil
        }

        let name = stringProperty(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? uid

        return AudioInputDevice(id: uid, name: name)
    }

    private static func isUsableMicrophone(deviceID: AudioDeviceID) -> Bool {
        let name = stringProperty(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        )?.lowercased() ?? ""

        let uid = stringProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )?.lowercased() ?? ""

        let text = "\(name) \(uid)"
        let blockedTokens = [
            "display audio",
            "hdmi",
            "displayport",
            "airplay",
            "receiver",
            "speaker",
            "output"
        ]

        return !blockedTokens.contains { text.contains($0) }
    }

    private static func allAudioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else {
            return []
        }
        return devices
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return 0
        }

        let byteCount = Int(dataSize)
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            buffer.deallocate()
        }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, buffer) == noErr else {
            return 0
        }

        let audioBufferList = buffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(audioBufferList)
            .reduce(0) { $0 + $1.mNumberChannels }
    }

    private static func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { valuePointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &dataSize,
                valuePointer
            )
        }
        guard status == noErr else {
            return nil
        }
        return value as String
    }
}

private final class AudioQueueDiskRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let deviceUID: String
    private let fileURL: URL
    private var format: AudioStreamBasicDescription
    private var queue: AudioQueueRef?
    private var fileID: AudioFileID?
    private var currentPacket: Int64 = 0
    private var isRunning = false
    private var pendingError: Error?

    init(deviceUID: String, fileURL: URL) {
        self.deviceUID = deviceUID
        self.fileURL = fileURL
        self.format = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
    }

    func start() throws {
        let startedAt = PerformanceLog.checkpoint()
        var createdQueue: AudioQueueRef?
        var status = AudioQueueNewInput(
            &format,
            audioQueueInputCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil,
            0,
            &createdQueue
        )
        try check(status, operation: "AudioQueueNewInput")

        guard let createdQueue else {
            throw AudioRecordingError.audioQueueError(operation: "AudioQueueNewInput", status: -1)
        }
        queue = createdQueue

        var selectedDeviceUID = deviceUID as CFString
        status = withUnsafePointer(to: &selectedDeviceUID) { pointer in
            AudioQueueSetProperty(
                createdQueue,
                kAudioQueueProperty_CurrentDevice,
                pointer,
                UInt32(MemoryLayout<CFString>.size)
            )
        }
        try check(status, operation: "AudioQueueSetProperty(CurrentDevice)")

        status = AudioFileCreateWithURL(
            fileURL as CFURL,
            kAudioFileCAFType,
            &format,
            .eraseFile,
            &fileID
        )
        try check(status, operation: "AudioFileCreateWithURL")

        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            status = AudioQueueAllocateBuffer(createdQueue, 16_384, &buffer)
            try check(status, operation: "AudioQueueAllocateBuffer")
            if let buffer {
                status = AudioQueueEnqueueBuffer(createdQueue, buffer, 0, nil)
                try check(status, operation: "AudioQueueEnqueueBuffer")
            }
        }

        lock.lock()
        isRunning = true
        lock.unlock()

        status = AudioQueueStart(createdQueue, nil)
        do {
            try check(status, operation: "AudioQueueStart")
        } catch {
            lock.lock()
            isRunning = false
            lock.unlock()
            throw error
        }
        log.debug("AudioQueueDiskRecorder.start completed in \(PerformanceLog.elapsedDescription(since: startedAt)); file=\(self.fileURL.lastPathComponent)")
    }

    func abortStart() {
        lock.lock()
        isRunning = false
        pendingError = nil
        lock.unlock()

        if let queue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            self.queue = nil
        }

        if let fileID {
            AudioFileClose(fileID)
            self.fileID = nil
        }
    }

    func stop() throws -> RecordingStopResult {
        let startedAt = PerformanceLog.checkpoint()
        lock.lock()
        isRunning = false
        pendingError = nil
        lock.unlock()

        var stopStatus: OSStatus = noErr
        var disposeStatus: OSStatus = noErr
        var closeStatus: OSStatus = noErr

        if let queue {
            // Prefer fast non-blocking teardown, but fall back to synchronous cleanup
            // if CoreAudio reports that the queue is still mid-reconfiguration.
            stopStatus = AudioQueueStop(queue, false)
            if stopStatus != noErr {
                stopStatus = AudioQueueStop(queue, true)
            }
            disposeStatus = AudioQueueDispose(queue, false)
            if disposeStatus != noErr {
                disposeStatus = AudioQueueDispose(queue, true)
            }
            self.queue = nil
        }

        if let fileID {
            closeStatus = AudioFileClose(fileID)
            self.fileID = nil
        }

        if let pendingError, currentPacket == 0 {
            throw pendingError
        }

        let byteSize = (try? FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0

        let result = RecordingStopResult(
            url: fileURL,
            packetCount: currentPacket,
            byteSize: byteSize,
            stopStatus: stopStatus,
            disposeStatus: disposeStatus,
            closeStatus: closeStatus
        )
        log.debug("AudioQueueDiskRecorder.stop completed in \(PerformanceLog.elapsedDescription(since: startedAt)); packets=\(result.packetCount); bytes=\(result.byteSize)")
        return result
    }

    fileprivate func handleInputBuffer(
        queue: AudioQueueRef,
        buffer: AudioQueueBufferRef,
        packetCount: UInt32,
        packetDescriptions: UnsafePointer<AudioStreamPacketDescription>?
    ) {
        lock.lock()
        let shouldContinue = isRunning
        lock.unlock()

        guard shouldContinue, pendingError == nil else {
            return
        }

        var packetsToWrite = packetCount
        if packetsToWrite == 0 {
            packetsToWrite = buffer.pointee.mAudioDataByteSize / format.mBytesPerPacket
        }

        if packetsToWrite > 0, let fileID {
            var mutablePacketCount = packetsToWrite
            let status = AudioFileWritePackets(
                fileID,
                false,
                buffer.pointee.mAudioDataByteSize,
                packetDescriptions,
                currentPacket,
                &mutablePacketCount,
                buffer.pointee.mAudioData
            )

            if status == noErr {
                currentPacket += Int64(mutablePacketCount)
            } else {
                pendingError = AudioRecordingError.audioQueueError(
                    operation: "AudioFileWritePackets",
                    status: status
                )
            }
        }

        if pendingError == nil {
            let status = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            if status != noErr {
                pendingError = AudioRecordingError.audioQueueError(
                    operation: "AudioQueueEnqueueBuffer",
                    status: status
                )
            }
        }
    }

    private func check(_ status: OSStatus, operation: String) throws {
        if status != noErr {
            throw AudioRecordingError.audioQueueError(operation: operation, status: status)
        }
    }
}

private extension Array where Element == UInt64 {
    func enumeratedWithTrailingAttempt() -> [(Int, UInt64)] {
        map { $0 }.enumerated().map { ($0.offset, $0.element) } + [(count, 0)]
    }
}

private func audioQueueInputCallback(
    userData: UnsafeMutableRawPointer?,
    queue: AudioQueueRef,
    buffer: AudioQueueBufferRef,
    startTime: UnsafePointer<AudioTimeStamp>,
    packetCount: UInt32,
    packetDescriptions: UnsafePointer<AudioStreamPacketDescription>?
) {
    guard let userData else {
        return
    }

    let recorder = Unmanaged<AudioQueueDiskRecorder>
        .fromOpaque(userData)
        .takeUnretainedValue()
    recorder.handleInputBuffer(
        queue: queue,
        buffer: buffer,
        packetCount: packetCount,
        packetDescriptions: packetDescriptions
    )
}
