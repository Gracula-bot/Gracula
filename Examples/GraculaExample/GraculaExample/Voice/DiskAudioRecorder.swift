@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

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
    private var recorder: AudioQueueDiskRecorder?

    func availableInputDevices() -> [AudioInputDevice] {
        CoreAudioInputDevices.devices()
    }

    func defaultInputDevice() -> AudioInputDevice? {
        CoreAudioInputDevices.defaultInputDevice()
    }

    func start(deviceID: String?) async throws -> URL {
        let startedAt = PerformanceLog.checkpoint()
        try await requestMicrophonePermission()
        guard recorder == nil else {
            throw AudioRecordingError.alreadyRecording
        }

        let deviceID = deviceID ?? CoreAudioInputDevices.defaultInputDevice()?.id
        guard let deviceID else {
            throw AudioRecordingError.inputDeviceUnavailable
        }

        let url = try makeRecordingURL()
        let recorder = AudioQueueDiskRecorder(deviceUID: deviceID, fileURL: url)
        try recorder.start()
        self.recorder = recorder
        log.debug("DiskAudioRecorder.start completed in \(PerformanceLog.elapsedDescription(since: startedAt)); deviceID=\(deviceID); file=\(url.lastPathComponent)")
        return url
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
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GraculaExample", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)

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
            return "\(operation) failed with OSStatus \(status). Choose a different microphone input source."
        case .notRecording:
            return "No recording is active."
        }
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

    func stop() throws -> RecordingStopResult {
        let startedAt = PerformanceLog.checkpoint()
        lock.lock()
        isRunning = false
        lock.unlock()

        var stopStatus: OSStatus = noErr
        var disposeStatus: OSStatus = noErr
        var closeStatus: OSStatus = noErr

        if let queue {
            // Use non-blocking stop/dispose. Some devices report "reconfig pending"
            // and can hang or crash inside synchronous HAL teardown.
            stopStatus = AudioQueueStop(queue, false)
            disposeStatus = AudioQueueDispose(queue, false)
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
