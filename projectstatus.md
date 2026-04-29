# Project Status

This file records implementation progress step by step. Every milestone update must include completed work, validation commands, results, blockers, and next actions.

## Current Milestone

Milestone 10 — OpenClaw Voice Chat

Status: completed

## Milestone 1 — Base Architecture Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Create `Package.swift` | Done | Added SwiftPM manifest for the Gracula package. |
| 2. Add executable target `AgentApp` | Done | Added `AgentApp` as executable product target `Gracula`. |
| 3. Add library targets | Done | Added `AppShell`, `Domain`, `Application`, `Voice`, `LLM`, `Tools`, `Automation`, `Persistence`, `Security`, and `Shared`. |
| 4. Add matching test targets | Done | Added smoke test targets for `Domain`, `Application`, `Voice`, `LLM`, `Tools`, and `Security`. |
| 5. Enable Swift 6 language mode | Done | Added `.swiftLanguageMode(.v6)` to all targets. |
| 6. Add minimal SwiftUI macOS shell | Done | Added `GraculaApp`, `AppCompositionRoot`, `AgentView`, and `AgentViewModel`. |
| 7. Add placeholder composition root | Done | Added `AppCompositionRoot.makeAgentView()`. |
| 8. Add smoke tests | Done | Added importability tests for core modules. |
| 9. Run `swift build` | Done | Passed after marking `AppCompositionRoot.makeAgentView()` as `@MainActor`. |
| 10. Run `swift test` | Done | Passed with 6 Swift Testing smoke tests. |
| 11. Record milestone steps | Done | Milestone report and validation log are updated. |

## Validation Log

| Date | Command | Result | Notes |
| --- | --- | --- | --- |
| 2026-04-28 | `swift --version` | Passed | Apple Swift 6.3.1 is available. |
| 2026-04-28 | `swift build` | Sandbox blocked | Default sandbox failed during SwiftPM manifest compilation with `sandbox-exec: sandbox_apply: Operation not permitted`. |
| 2026-04-28 | `swift build` | Failed | Escalated build found a Swift 6 actor isolation error in `AppCompositionRoot`. |
| 2026-04-28 | `swift build` | Passed | Build completed after adding `@MainActor` to `makeAgentView()`. |
| 2026-04-28 | `swift test` | Sandbox blocked | Default sandbox failed during SwiftPM manifest compilation with `sandbox-exec: sandbox_apply: Operation not permitted`. |
| 2026-04-28 | `swift test` | Passed | 6 smoke tests passed. |
| 2026-04-28 | `git pull --ff-only origin develop` | Passed | Pulled remote `develop`; fast-forward included `.gitignore` update. |
| 2026-04-28 | `swift build` | Passed | Domain Core compiled after replacing placeholder module with real domain models. |
| 2026-04-28 | `swift test` | Failed | Initial Milestone 2 test run found missing `Foundation` import in `ToolArgumentTests`. |
| 2026-04-28 | `swift test` | Passed | 14 tests passed after adding the missing import. |
| 2026-04-28 | `swift build` | Passed | Final Milestone 2 build passed. |
| 2026-04-28 | `git commit -m "Implement domain core models"` | Passed | Created commit `7752676` for Milestone 2. |
| 2026-04-28 | `swift build` | Passed | Application ports compiled. |
| 2026-04-28 | `swift test` | Passed | 19 tests passed after adding Application protocol tests. |
| 2026-04-28 | `git commit -m "Add application ports"` | Passed | Created commit `b98d700` for Milestone 3. |
| 2026-04-28 | `swift build` | Passed | In-memory core actors compiled. |
| 2026-04-28 | `swift test` | Passed | 34 tests passed after adding memory, audit, policy, registry, executor, and orchestrator tests. |
| 2026-04-28 | `git commit -m "Implement in-memory application core"` | Passed | Created commit `fa8e5d3` for Milestone 4. |
| 2026-04-28 | `swift build` | Passed | Manual SwiftUI shell compiled. |
| 2026-04-28 | `swift test` | Passed | 34 tests passed after wiring demo UI shell. |
| 2026-04-28 | `git commit -m "Add manual SwiftUI shell"` | Passed | Created commit `2734989` for Milestone 5. |
| 2026-04-28 | `swift build` | Passed | Text-to-speech protocol, Apple adapter, and UI wiring compiled. |
| 2026-04-28 | `swift test` | Passed | 38 tests passed after adding TTS tests. |
| 2026-04-28 | `git commit -m "Add text to speech support"` | Passed | Created commit `83922e8` for Milestone 6. |
| 2026-04-28 | `swift build` | Passed | Speech-to-text protocols, Apple adapters, and `VoicePipeline` compiled. |
| 2026-04-28 | `swift test` | Failed | Initial Milestone 7 test run found missing `Foundation` import in `TranscriptEventTests`. |
| 2026-04-28 | `swift test` | Passed | 41 tests passed after adding the missing import. |
| 2026-04-28 | `swift build` | Passed | Final Milestone 7 build passed. |
| 2026-04-28 | `git commit -m "Add speech to text pipeline"` | Passed | Created commit `d545a44` for Milestone 7. |
| 2026-04-28 | `git commit -m "Ignore SwiftPM workspace metadata"` | Passed | Created commit `ff7f483` to ignore generated `.swiftpm/` workspace metadata. |
| 2026-04-28 | `swift build` | Passed | LLM models, local HTTP client, prompt compiler, parser, and planning adapter compiled. |
| 2026-04-28 | `swift test` | Passed | 46 tests passed after adding LLM planner tests. |
| 2026-04-28 | `swift test` | Passed | 53 tests passed after adding safe tools, path allowlist, file system client, and real app composition wiring. |
| 2026-04-28 | `swift test --filter DomainTests` | Passed | 9 Domain milestone tests passed. |
| 2026-04-29 | `xcodebuild build -project Examples/GraculaExample/GraculaExample.xcodeproj -scheme GraculaExample -destination 'platform=macOS'` | Failed | Code signing was blocked by missing Mac Development certificate for team `5SM7ZEMA29`. |
| 2026-04-29 | `xcodebuild build -project Examples/GraculaExample/GraculaExample.xcodeproj -scheme GraculaExample -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | Passed | GraculaExample compiled after OpenClaw chat, voice-to-bot, bot voice reply, and macOS voice picker changes. |
| 2026-04-29 | `open /Users/gg/Library/Developer/Xcode/DerivedData/GraculaExample-geqncmkzkjgffogcalrscaikgrwl/Build/Products/Debug/GraculaExample.app` | Passed | Relaunched the fresh Debug build after successful validation. |

## Milestone 2 — Domain Core Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Implement `ToolRiskLevel` | Done | Added `safe`, `reversible`, `externalCommunication`, and `financialOrCritical` with comparable ordering. |
| 2. Implement `ToolArgument` | Done | Added Codable/Sendable/Equatable typed argument cases. |
| 3. Implement `ToolCall` | Done | Added typed tool call with ID, name, arguments, and risk level. |
| 4. Implement `AgentPlan` | Done | Added plan model with `highestRiskLevel`. |
| 5. Implement `ConfirmationChallenge` | Done | Added confirmation challenge model with optional required phrase. |
| 6. Implement `PolicyDecision` | Done | Added allow, confirmation, and deny outcomes. |
| 7. Implement `ToolResult` | Done | Added success, user-input, and failure results. |
| 8. Implement conversation and audit models | Done | Added `ConversationContext`, `ConversationMessage`, `ConversationRole`, `AuditEvent`, and `AuditEventKind`. |
| 9. Add Codable and Equatable tests | Done | Added round-trip tests for plan, arguments, conversation context, and audit events. |
| 10. Add risk tests | Done | Added tests for `highestRiskLevel`, risk ordering, and planner raw values. |
| 11. Update `projectstatus.md` | Done | Milestone 2 report and validation log are updated. |

## Milestone 3 — Application Ports Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Add `Planning` | Done | Added async `Planning.makePlan(userText:context:)` protocol. |
| 2. Add `PolicyChecking` | Done | Added async `PolicyChecking.evaluate(_:)` protocol. |
| 3. Add `AgentTool` | Done | Added typed tool protocol with name, description, risk level, and async run method. |
| 4. Add `ToolExecuting` | Done | Added async plan execution protocol returning `[ToolResult]`. |
| 5. Add `AgentMemory` | Done | Added async memory protocol for appending messages and reading context. |
| 6. Add `AuditLogging` | Done | Added async audit logging protocol for `AuditEvent`. |
| 7. Add application errors | Done | Added `ApplicationError` with planning, policy, tool, memory, and audit cases. |
| 8. Add fake test doubles | Done | Added fakes for planner, policy checker, tool, executor, memory, and audit log inside Application tests. |
| 9. Update `projectstatus.md` | Done | Milestone 3 report and validation log are updated. |

## Milestone 4 — In-Memory Core Actors Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Implement `ConversationMemory` actor | Done | Added bounded in-memory conversation history. |
| 2. Implement `InMemoryAuditLog` actor | Done | Added append-only in-memory audit event store. |
| 3. Implement `DefaultPolicyGate` actor | Done | Added safe, reversible allowlist, external communication, and strong confirmation rules. |
| 4. Implement `ToolRegistry` actor | Done | Added registration, resolution, descriptors, and typed unknown-tool failure. |
| 5. Implement `ToolExecutor` actor | Done | Added sequential tool execution with start, finish, and failure audit events. |
| 6. Implement `AgentOrchestrator` actor | Done | Added final-text handling through memory, planner, audit, policy, executor, and outcome mapping. |
| 7. Add fake planner and fake tools | Done | Added reusable fakes for Application tests. |
| 8. Add core flow tests | Done | Added tests for allowed execution, confirmation, denial, unknown tool, audit ordering, and policy decisions. |
| 9. Update `projectstatus.md` | Done | Milestone 4 report and validation log are updated. |

## Milestone 5 — Manual SwiftUI Shell Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Expand `AgentViewModel` as `@MainActor` | Done | Added manual input, status, result, pending challenge, confirmation text, and audit entries. |
| 2. Add UI states | Done | Added visible status transitions for ready, thinking, needs confirmation, executing, executed, rejected, denied, and error states. |
| 3. Add manual text input | Done | Added text field and run button. |
| 4. Add transcript/result panel | Done | Added result display for tool outcomes and policy responses. |
| 5. Add pending confirmation panel | Done | Added `ConfirmationView` with optional strong confirmation phrase input. |
| 6. Add approve/reject controls | Done | Added approval and rejection actions for pending plans. |
| 7. Add audit log preview | Done | Added `AuditLogPreviewView` backed by `InMemoryAuditLog`. |
| 8. Wire fake planner and fake tools | Done | Added demo planner/tools through `AppCompositionRoot` using the real orchestrator, policy gate, registry, executor, memory, and audit log. |
| 9. Update `projectstatus.md` | Done | Milestone 5 report and validation log are updated. |

## Milestone 6 — Text-to-Speech Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Add `SpeechSynthesizing` | Done | Added async TTS protocol in the `Voice` module. |
| 2. Implement `AppleSpeechSynthesizer` | Done | Added actor-backed adapter using `AVSpeechSynthesizer` through a testable driver boundary. |
| 3. Add stop speaking | Done | Added `stop()` to the protocol, adapter, view model, and UI. |
| 4. Add voice/language/rate settings | Done | Added `SpeechSynthesisConfiguration` with language, rate, pitch, and volume. |
| 5. Inject through composition root | Done | Wired `AppleSpeechSynthesizer` into `AgentViewModel` from `AppCompositionRoot`. |
| 6. Add fake TTS tests | Done | Added driver-backed tests for blank text, speak, stop, and configuration values. |
| 7. Update `projectstatus.md` | Done | Milestone 6 report and validation log are updated. |

## Milestone 7 — Speech-to-Text Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Add microphone permission flow | Done | Added permission checks in `AppleAudioCapture`; microphone permission is requested only when capture starts. |
| 2. Implement `AudioCapturing` | Done | Added `AudioFrame`, `AudioCapturing`, and `AppleAudioCapture` using `AVAudioEngine`. |
| 3. Implement `SpeechRecognizing` | Done | Added `TranscriptEvent`, `TranscriptKind`, `SpeechRecognizing`, and `AppleSpeechRecognizer` using Apple Speech. |
| 4. Emit partial and final transcript events | Done | Apple recognizer maps Speech results to partial/final `TranscriptEvent` values. |
| 5. Implement `VoicePipeline` actor | Done | Added pipeline from audio capture to STT to `AgentOrchestrator` to TTS. |
| 6. Process final transcripts first | Done | Pipeline yields partial transcripts but only sends `.final` transcripts to the orchestrator. |
| 7. Keep manual input fallback | Done | Existing manual SwiftUI input remains unchanged. |
| 8. Update `projectstatus.md` | Done | Milestone 7 report and validation log are updated. |

## Milestone 8 — LLM Planner Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Add `LLMClient` models | Done | Added `LLMClient`, `LLMRequest`, `LLMResponse`, and `LLMToken`. |
| 2. Implement local HTTP client | Done | Added `LocalHTTPLLMClient` for local OpenAI/Ollama-compatible response shapes. |
| 3. Implement `PromptCompiler` | Done | Added compiler for system prompt, user command, recent context, available tools, safety rules, and JSON schema. |
| 4. Include tools, context, safety rules, and schema | Done | Prompt tests verify all required sections are included. |
| 5. Implement strict JSON parser | Done | Added `AgentPlanParser` for JSON-only planner output to typed `AgentPlan`. |
| 6. Reject invalid JSON safely | Done | Parser returns `LLMError.invalidPlannerOutput` for invalid JSON. |
| 7. Add parser tests | Done | Added tests for valid JSON, invalid JSON, unknown tools, invalid risk levels, and planning adapter integration. |
| 8. Update `projectstatus.md` | Done | Milestone 8 report and validation log are updated. |

## Milestone 9 — Safe Tools Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Add path allowlist | Done | Added `PathAllowlist` in `AgentSecurity` to resolve paths and reject files outside approved directories. |
| 2. Add file system client | Done | Added `FileSystemClient` and `LocalFileSystemClient` for UTF-8 reads and writes. |
| 3. Implement `OpenURLTool` | Done | Added web-only URL validation and delegated opening through `URLOpening`. |
| 4. Implement `OpenAppTool` | Done | Added typed app-opening tool delegated through `AppOpening`. |
| 5. Implement `ReadAllowedFileTool` | Done | Added approved-directory file reads. |
| 6. Implement `WriteNoteTool` | Done | Added approved notes-directory writes with filename path component sanitization. |
| 7. Add macOS opening adapter | Done | Added `WorkspaceOpeningClient` in `Automation` using `NSWorkspace` for URLs and applications. |
| 8. Wire real safe tools in app composition | Done | `AppCompositionRoot` now registers real safe tools, shared allowlist, local file system, and optional local LLM planner through `GRACULA_LLM_ENDPOINT`. |
| 9. Add tests | Done | Added focused tests for URL/app tools, allowed and denied file paths, note writes, filename sanitization, and allowlist behavior. |
| 10. Add manual testing guide | Done | Added `manualtesting.md` with commands and manual checks for every milestone. |

## Milestone 10 — OpenClaw Voice Chat Report

| Step | Status | Report |
| --- | --- | --- |
| 1. Add local OpenClaw controller | Done | Added a local Node-based controller for starting the OpenClaw gateway/stream bridge and sending local agent turns. |
| 2. Add OpenClaw controls and chat UI | Done | Added status, logs, dashboard controls, chat transcript, send, and reset controls. |
| 3. Resolve configured gateway port | Done | Controller reads `OPENCLAW_GATEWAY_PORT` or `~/.openclaw/openclaw.json` and avoids stale hardcoded gateway checks. |
| 4. Parse and recover OpenClaw replies | Done | Chat handles root/result payloads and recovers latest assistant text from OpenClaw session transcripts when CLI payloads are empty. |
| 5. Route voice messages to OpenClaw | Done | Microphone recordings are transcribed, sent to OpenClaw, appended to chat, and bot replies are spoken. |
| 6. Add macOS bot voice selection | Done | Added a `Bot Voice` picker backed by `AVSpeechSynthesisVoice`, persisted selected voice identifier, and routed system TTS through it. |
| 7. Add local STT/TTS runtime tuning | Done | Kept faster-whisper worker prewarm and VoxCPM/system-voice fallback paths; documented faster macOS voices as the low-latency TTS path. |
| 8. Validate Xcode build | Done | `xcodebuild ... CODE_SIGNING_ALLOWED=NO` passed; normal signing remains blocked by local certificate setup. |
| 9. Update `projectstatus.md` | Done | Milestone 10 report and validation log are updated. |

## Blockers

- SwiftPM commands need to run outside the default sandbox in this environment because manifest compilation fails with `sandbox-exec`.
- GraculaExample normal Xcode signing requires a Mac Development certificate for team `5SM7ZEMA29`; validation currently uses `CODE_SIGNING_ALLOWED=NO`.

## Next Actions

1. Profile voice round-trip latency across STT, OpenClaw, and TTS.
2. Add streaming/VAD STT so transcription starts before recording stops.
3. Add UI controls for STT backend/model and TTS rate/pitch if more latency or voice tuning is needed.
