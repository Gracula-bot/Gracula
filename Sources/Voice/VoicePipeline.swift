import Application
import Domain

public actor VoicePipeline {
    private let audioCapture: any AudioCapturing
    private let speechRecognizer: any SpeechRecognizing
    private let speechSynthesizer: any SpeechSynthesizing
    private let orchestrator: AgentOrchestrator
    private var activeTask: Task<Void, Never>?

    public init(
        audioCapture: any AudioCapturing,
        speechRecognizer: any SpeechRecognizing,
        speechSynthesizer: any SpeechSynthesizing,
        orchestrator: AgentOrchestrator
    ) {
        self.audioCapture = audioCapture
        self.speechRecognizer = speechRecognizer
        self.speechSynthesizer = speechSynthesizer
        self.orchestrator = orchestrator
    }

    public func start() async throws -> AsyncStream<VoicePipelineEvent> {
        guard activeTask == nil else {
            throw VoiceError.pipelineAlreadyRunning
        }

        let (stream, continuation) = AsyncStream.makeStream(of: VoicePipelineEvent.self)
        let task = Task {
            await run(continuation: continuation)
        }
        activeTask = task
        return stream
    }

    public func stop() async {
        activeTask?.cancel()
        activeTask = nil
        await speechSynthesizer.stop()
    }

    private func run(continuation: AsyncStream<VoicePipelineEvent>.Continuation) async {
        continuation.yield(.listening)
        defer {
            continuation.finish()
            activeTask = nil
        }

        do {
            let audio = try await audioCapture.frames()
            let transcripts = try await speechRecognizer.transcribe(audio)

            for try await transcript in transcripts {
                continuation.yield(.transcript(transcript))

                guard transcript.kind == .final else {
                    continue
                }

                continuation.yield(.thinking)
                let outcome = try await orchestrator.handleFinalUserText(transcript.text)
                continuation.yield(.orchestratorOutcome(outcome))

                if let spokenText = speechText(for: outcome) {
                    try await speechSynthesizer.speak(spokenText)
                }
            }
        } catch is CancellationError {
            continuation.yield(.stopped)
        } catch {
            continuation.yield(.failed(String(describing: error)))
        }
    }

    private func speechText(for outcome: AgentOrchestratorOutcome) -> String? {
        switch outcome {
        case .executed(_, let results):
            return results.map { result in
                switch result {
                case .success(let message):
                    message
                case .requiresUserInput(let message):
                    message
                case .failed(let message):
                    message
                }
            }
            .joined(separator: "\n")

        case .requiresConfirmation(_, let challenge):
            return challenge.summary

        case .denied(_, let reason):
            return reason
        }
    }
}

public enum VoicePipelineEvent: Sendable, Equatable {
    case listening
    case transcript(TranscriptEvent)
    case thinking
    case orchestratorOutcome(AgentOrchestratorOutcome)
    case stopped
    case failed(String)
}
