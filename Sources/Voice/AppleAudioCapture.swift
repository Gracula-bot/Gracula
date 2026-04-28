@preconcurrency import AVFoundation
import Foundation

public final class AppleAudioCapture: AudioCapturing, @unchecked Sendable {
    private let engine: AVAudioEngine

    public init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
    }

    public func frames() async throws -> AsyncThrowingStream<AudioFrame, any Error> {
        try await requestMicrophonePermission()

        return AsyncThrowingStream { continuation in
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
                let frame = AudioFrame(
                    samples: Self.samples(from: buffer),
                    sampleRate: format.sampleRate,
                    timestampNanos: UInt64(max(0, time.hostTime))
                )
                continuation.yield(frame)
            }

            do {
                engine.prepare()
                try engine.start()
            } catch {
                continuation.finish(throwing: error)
            }

            continuation.onTermination = { [weak engine] _ in
                engine?.inputNode.removeTap(onBus: 0)
                engine?.stop()
            }
        }
    }

    private func requestMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw VoiceError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw VoiceError.microphonePermissionDenied
        @unknown default:
            throw VoiceError.microphonePermissionDenied
        }
    }

    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return []
        }

        var samples: [Float] = []
        samples.reserveCapacity(frameLength)

        for frameIndex in 0..<frameLength {
            var mixedSample: Float = 0
            for channelIndex in 0..<channelCount {
                mixedSample += channelData[channelIndex][frameIndex]
            }
            samples.append(mixedSample / Float(channelCount))
        }

        return samples
    }
}
