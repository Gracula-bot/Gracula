# Implementation Plan

This plan decomposes Gracula into implementation milestones. Each milestone must update `projectstatus.md` with completed steps, validation results, blockers, and next actions.

## Milestone 1 — Base Architecture

Goal: create a compiling Swift 6 macOS project skeleton with the intended module boundaries.

Steps:

1. Create `Package.swift`.
2. Add executable target `AgentApp`.
3. Add library targets:
   - `AppShell`
   - `Domain`
   - `Application`
   - `Voice`
   - `LLM`
   - `Tools`
   - `Automation`
   - `Persistence`
   - `Security`
   - `Shared`
4. Add matching test targets:
   - `DomainTests`
   - `ApplicationTests`
   - `VoiceTests`
   - `LLMTests`
   - `ToolsTests`
   - `SecurityTests`
5. Enable Swift 6 language mode.
6. Add minimal SwiftUI macOS shell.
7. Add placeholder composition root.
8. Add smoke tests that prove core modules compile and can be imported.
9. Run `swift build`.
10. Run `swift test`.
11. Record all completed steps and validation in `projectstatus.md`.

Definition of done:

- `swift build` passes.
- `swift test` passes.
- `Domain` has no platform framework imports.
- UI contains no business logic.
- All milestone steps are reported in `projectstatus.md`.

## Milestone 2 — Domain Core

Goal: implement pure business models before infrastructure.

Steps:

1. Implement `ToolRiskLevel`.
2. Implement `ToolArgument`.
3. Implement `ToolCall`.
4. Implement `AgentPlan`.
5. Implement `ConfirmationChallenge`.
6. Implement `PolicyDecision`.
7. Implement `ToolResult`.
8. Implement `ConversationContext`, `ConversationMessage`, and `AuditEvent`.
9. Add Codable and Equatable tests.
10. Add tests for `AgentPlan.highestRiskLevel`.
11. Update `projectstatus.md`.

Definition of done:

- Domain model tests pass.
- Domain remains platform independent.
- All public cross-concurrency values are `Sendable`.

## Milestone 3 — Application Ports

Goal: define core use-case protocols and keep the application layer independent of adapters.

Steps:

1. Add `Planning`.
2. Add `PolicyChecking`.
3. Add `AgentTool`.
4. Add `ToolExecuting`.
5. Add `AgentMemory`.
6. Add `AuditLogging`.
7. Add application errors.
8. Add fake test doubles for each protocol.
9. Update `projectstatus.md`.

Definition of done:

- Application depends on `Domain`, not infrastructure.
- Protocols are narrow and `Sendable`.
- Tests can exercise the protocols with fakes.

## Milestone 4 — In-Memory Core Actors

Goal: implement the first safe, testable agent core without macOS, voice, or LLM adapters.

Steps:

1. Implement `ConversationMemory` actor.
2. Implement `InMemoryAuditLog` actor.
3. Implement `DefaultPolicyGate` actor.
4. Implement `ToolRegistry` actor.
5. Implement `ToolExecutor` actor.
6. Implement `AgentOrchestrator` actor.
7. Add fake planner and fake tools.
8. Add tests for allowed, confirmation, denied, unknown tool, and audit flows.
9. Update `projectstatus.md`.

Definition of done:

- Safe actions can execute.
- Risky actions require confirmation.
- Unknown tools fail cleanly.
- Plans and tool results are audit logged.

## Milestone 5 — Manual SwiftUI Shell

Goal: expose the core through a simple local control panel before voice and LLM work.

Steps:

1. Expand `AgentViewModel` as `@MainActor`.
2. Add UI states:
   - idle
   - listening
   - thinking
   - needs confirmation
   - executing
   - error
3. Add manual text input.
4. Add transcript/result panel.
5. Add pending confirmation panel.
6. Add approve/reject controls.
7. Add audit log preview.
8. Wire fake planner and fake tools through `AppCompositionRoot`.
9. Update `projectstatus.md`.

Definition of done:

- User can type a command.
- Fake safe action executes.
- Fake risky action asks for confirmation.
- Rejection executes nothing.

## Milestone 6 — Text-to-Speech

Goal: add native TTS behind a protocol.

Steps:

1. Add `SpeechSynthesizing`.
2. Implement `AppleSpeechSynthesizer` with `AVSpeechSynthesizer`.
3. Add stop speaking.
4. Add voice/language/rate settings.
5. Inject through the composition root.
6. Add fake TTS tests where useful.
7. Update `projectstatus.md`.

Definition of done:

- Agent can speak responses.
- TTS can be stopped.
- UI remains responsive.

## Milestone 7 — Speech-to-Text

Goal: capture microphone input and produce final transcripts.

Steps:

1. Add microphone permission flow.
2. Implement `AudioCapturing` with `AVAudioEngine`.
3. Implement `SpeechRecognizing` with Apple Speech.
4. Emit partial and final `TranscriptEvent` values.
5. Implement `VoicePipeline` actor.
6. Process final transcripts first.
7. Keep manual input fallback.
8. Update `projectstatus.md`.

Definition of done:

- User can speak a short command.
- UI shows partial transcript.
- Final transcript reaches `AgentOrchestrator`.
- Agent speaks the result.

## Milestone 8 — LLM Planner

Goal: replace fake planning with local LLM-backed typed planning.

Steps:

1. Add `LLMClient` models.
2. Implement local HTTP client for OpenAI-compatible or Ollama-compatible endpoints.
3. Implement `PromptCompiler`.
4. Include tools, context, safety rules, and JSON schema in prompts.
5. Implement strict JSON parser to `AgentPlan`.
6. Reject invalid JSON safely.
7. Add parser tests.
8. Update `projectstatus.md`.

Definition of done:

- Local LLM can create typed plans.
- Invalid output does not crash the app.
- Policy still controls every execution.

## Milestone 9 — Safe Tools

Goal: implement safe and reversible MVP tools.

Steps:

1. Implement `OpenURLTool`.
2. Implement `OpenAppTool`.
3. Implement `ReadAllowedFileTool`.
4. Implement `WriteNoteTool`.
5. Implement draft creation with fake/in-memory clients.
6. Add approved directory validation.
7. Add tests for allowed and denied paths.
8. Update `projectstatus.md`.

Definition of done:

- Browser and app opening work.
- Notes are written only inside approved folders.
- Disallowed paths are rejected.

## Milestone 10 — Confirmation Flow

Goal: execute risky plans only after explicit approval.

Steps:

1. Add pending plan storage.
2. Add UI approval command.
3. Add UI rejection command.
4. Freeze approved tool arguments.
5. Execute only the frozen approved plan.
6. Log approval and rejection.
7. Add mutation-prevention tests.
8. Update `projectstatus.md`.

Definition of done:

- Sending and dangerous tools cannot run without confirmation.
- Approved arguments cannot be changed by the LLM.
- Rejected actions do nothing.

## Milestone 11 — Communication Drafts

Goal: support mail and messages through draft-first safety.

Steps:

1. Define `MailClient`.
2. Define `MessageClient`.
3. Implement draft-only tools.
4. Implement send tools behind `externalCommunication` policy.
5. Show recipient and final body in confirmation UI.
6. Add tests proving send requires confirmation.
7. Update `projectstatus.md`.

Definition of done:

- Drafts can be created.
- Sending cannot happen without approval.
- Audit log includes recipient and action type.

## Milestone 12 — Limited macOS Automation

Goal: add controlled automation without unrestricted OS control.

Steps:

1. Add Accessibility permission request.
2. Implement `NSWorkspace` app opening.
3. Implement active app/window read.
4. Implement limited keyboard input.
5. Implement limited mouse click API.
6. Keep high-risk automation disabled by default.
7. Audit every automation action.
8. Update `projectstatus.md`.

Definition of done:

- Automation requires permission.
- UI shows when automation mode is active.
- Automation APIs are narrow, typed, and logged.

## Milestone 13 — Payment Intent Only

Goal: prepare payment intents without executing money movement.

Steps:

1. Define `PaymentRequest`.
2. Define `PaymentIntent`.
3. Define `PaymentConfirmation`.
4. Implement `PreparePaymentTool`.
5. Keep execution tools disabled.
6. Require strong confirmation for payment-like actions.
7. Add tests proving payments cannot execute.
8. Update `projectstatus.md`.

Definition of done:

- Agent can summarize a payment request.
- Agent cannot execute payment.
- Strong confirmation challenge is generated.

## Milestone 14 — Hardening

Goal: make the MVP reliable enough for local use.

Steps:

1. Expand unit and integration tests.
2. Verify strict concurrency warnings.
3. Verify every side effect path uses policy gates.
4. Verify audit logging.
5. Verify approved directory checks.
6. Update `README.md`.
7. Add manual test checklist.
8. Update `projectstatus.md`.

Definition of done:

- App builds.
- Tests pass.
- No new concurrency warnings are introduced.
- Risky actions remain gated.
- Audit logging is preserved.

