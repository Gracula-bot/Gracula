@preconcurrency import AVFoundation
@preconcurrency import Speech

public actor AppleSpeechRecognizer: SpeechRecognizing {
    private let locale: Locale

    public init(locale: Locale = Locale(identifier: "ru-RU")) {
        self.locale = locale
    }

    public func transcribe(
        _ audio: AsyncThrowingStream<AudioFrame, any Error>
    ) async throws -> AsyncThrowingStream<TranscriptEvent, any Error> {
        try await requestSpeechPermission()

        return AsyncThrowingStream { continuation in
            let recognizer = SFSpeechRecognizer(locale: locale)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let task = recognizer?.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let result else {
                    return
                }

                continuation.yield(
                    TranscriptEvent(
                        text: result.bestTranscription.formattedString,
                        kind: result.isFinal ? .final : .partial,
                        confidence: nil
                    )
                )

                if result.isFinal {
                    continuation.finish()
                }
            }

            let audioTask = Task {
                do {
                    for try await frame in audio {
                        request.append(Self.buffer(from: frame))
                    }
                    request.endAudio()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                audioTask.cancel()
                task?.cancel()
                request.endAudio()
            }
        }
    }

    private func requestSpeechPermission() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard status == .authorized else {
            throw VoiceError.speechRecognitionPermissionDenied
        }
    }

    private static func buffer(from frame: AudioFrame) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: frame.sampleRate,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frame.samples.count)
        )!
        buffer.frameLength = AVAudioFrameCount(frame.samples.count)

        if let channelData = buffer.floatChannelData {
            frame.samples.withUnsafeBufferPointer { sourceBuffer in
                channelData[0].update(from: sourceBuffer.baseAddress!, count: frame.samples.count)
            }
        }

        return buffer
    }
}
