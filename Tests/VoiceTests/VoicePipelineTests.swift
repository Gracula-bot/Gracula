import Application
import Domain
import Testing
@testable import Voice

@Test
func voicePipelineProcessesOnlyFinalTranscriptThroughOrchestrator() async throws {
    let plan = AgentPlan(
        userText: "Открой apple.com",
        summary: "Open site",
        toolCalls: [ToolCall(name: "open_url", arguments: [:], riskLevel: .safe)]
    )
    let auditLog = InMemoryAuditLog()
    let registry = ToolRegistry(tools: [PipelineFakeTool(name: "open_url", result: .success("Opened"))])
    let executor = ToolExecutor(registry: registry, auditLog: auditLog)
    let synthesizer = PipelineSpeechSynthesizer()
    let pipeline = VoicePipeline(
        audioCapture: PipelineAudioCapture(),
        speechRecognizer: PipelineSpeechRecognizer(
            events: [
                TranscriptEvent(text: "Отк", kind: .partial),
                TranscriptEvent(text: "Открой apple.com", kind: .final)
            ]
        ),
        speechSynthesizer: synthesizer,
        orchestrator: AgentOrchestrator(
            planner: PipelinePlanner(plan: plan),
            policyChecker: DefaultPolicyGate(),
            toolExecutor: executor,
            memory: ConversationMemory(),
            auditLog: auditLog
        )
    )

    let stream = try await pipeline.start()
    var events: [VoicePipelineEvent] = []
    for await event in stream {
        events.append(event)
    }

    #expect(events.contains(.listening))
    #expect(events.contains(.transcript(TranscriptEvent(text: "Отк", kind: .partial))))
    #expect(events.contains(.transcript(TranscriptEvent(text: "Открой apple.com", kind: .final))))
    #expect(events.contains(.thinking))
    #expect(await synthesizer.spokenTexts == ["Opened"])
    #expect(await auditLog.events.map(\.kind) == [.planCreated, .policyAllowed, .toolStarted, .toolFinished])
}

@Test
func voicePipelineRejectsSecondStartWhileRunning() async throws {
    let pipeline = VoicePipeline(
        audioCapture: NeverEndingAudioCapture(),
        speechRecognizer: NeverEndingSpeechRecognizer(),
        speechSynthesizer: PipelineSpeechSynthesizer(),
        orchestrator: AgentOrchestrator(
            planner: PipelinePlanner(
                plan: AgentPlan(userText: "noop", summary: "noop", toolCalls: [])
            ),
            policyChecker: DefaultPolicyGate(),
            toolExecutor: PipelineToolExecutor(),
            memory: ConversationMemory(),
            auditLog: InMemoryAuditLog()
        )
    )

    _ = try await pipeline.start()
    do {
        _ = try await pipeline.start()
        Issue.record("Expected pipelineAlreadyRunning")
    } catch VoiceError.pipelineAlreadyRunning {
        await pipeline.stop()
    }
}

private struct PipelineAudioCapture: AudioCapturing {
    func frames() async throws -> AsyncThrowingStream<AudioFrame, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(AudioFrame(samples: [0.1], sampleRate: 16_000, timestampNanos: 1))
            continuation.finish()
        }
    }
}

private struct PipelineSpeechRecognizer: SpeechRecognizing {
    let events: [TranscriptEvent]

    func transcribe(
        _ audio: AsyncThrowingStream<AudioFrame, any Error>
    ) async throws -> AsyncThrowingStream<TranscriptEvent, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                for try await _ in audio {}
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}

private struct NeverEndingAudioCapture: AudioCapturing {
    func frames() async throws -> AsyncThrowingStream<AudioFrame, any Error> {
        AsyncThrowingStream { _ in }
    }
}

private struct NeverEndingSpeechRecognizer: SpeechRecognizing {
    func transcribe(
        _ audio: AsyncThrowingStream<AudioFrame, any Error>
    ) async throws -> AsyncThrowingStream<TranscriptEvent, any Error> {
        AsyncThrowingStream { _ in }
    }
}

private struct PipelinePlanner: Planning {
    let plan: AgentPlan

    func makePlan(userText: String, context: ConversationContext) async throws -> AgentPlan {
        plan
    }
}

private struct PipelineFakeTool: AgentTool {
    let name: String
    let result: ToolResult

    var description: String {
        "Pipeline fake tool"
    }

    var riskLevel: ToolRiskLevel {
        .safe
    }

    func run(_ call: ToolCall) async throws -> ToolResult {
        result
    }
}

private actor PipelineToolExecutor: ToolExecuting {
    func execute(_ plan: AgentPlan) async throws -> [ToolResult] {
        []
    }
}

private actor PipelineSpeechSynthesizer: SpeechSynthesizing {
    private(set) var spokenTexts: [String] = []

    func speak(_ text: String) async throws {
        spokenTexts.append(text)
    }

    func stop() async {}
}
