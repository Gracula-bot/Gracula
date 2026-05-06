# AGENT.md — Codex implementation plan for a native macOS Swift voice agent

## 0. Product goal

Build a native macOS personal voice agent using modern Swift, structured concurrency, modular architecture, SOLID, KISS and DRY.

The agent must:

- listen to the microphone;
- transcribe speech to text;
- reason over commands;
- speak responses;
- open websites and apps;
- read/write files in approved locations;
- prepare messages and emails;
- send messages/emails only after explicit confirmation;
- prepare payment intents only behind strict approval gates;
- maintain audit logs for every planned and executed action.

The implementation must be native Swift. Do not use Docker.

## 1. Non-negotiable engineering rules

### Language and platform

- Use Swift 6 language mode.
- Prefer Swift 6.4 toolchain when available; otherwise use the latest stable Swift 6.x toolchain.
- Target macOS only for the first version.
- Use native Apple APIs where practical.
- Use structured concurrency: `async/await`, `actor`, `AsyncSequence`, `AsyncStream`, `TaskGroup`, `Sendable`.
- Avoid callback-based architecture except at framework boundaries.
- Avoid unstructured `Task.detached` unless explicitly justified.
- Avoid global mutable state.
- Avoid singleton service locators.

### Architecture

Use Clean Architecture / Hexagonal Architecture:

- Domain layer must not import AppKit, SwiftUI, AVFoundation, Speech, CoreGraphics or other platform APIs.
- Application layer coordinates use cases through protocols.
- Infrastructure layer implements real macOS adapters.
- UI layer observes state and sends user intents.
- LLM never directly controls the OS. It may only propose typed `ToolCall` objects.
- Every `ToolCall` must pass through `PolicyGate` before execution.

### Safety

- External communication requires confirmation.
- Financial or critical actions require strong confirmation.
- The agent may create drafts automatically, but must not send emails/messages automatically.
- The agent must not perform payments by free-form GUI clicking.
- The agent must not read unrestricted user files by default.
- The agent must request permissions only when the corresponding feature is used.
- Every action must be audit logged.

### Code style

- Keep modules small.
- Prefer protocols with narrow responsibilities.
- Prefer immutable value types for domain models.
- Use `actor` for mutable shared state.
- Mark cross-concurrency values as `Sendable`.
- Prefer dependency injection through initializers.
- Write tests for Domain and Application before Infrastructure.
- No hidden side effects in initializers.
- No business logic in SwiftUI views.

### Failure handling

- When changing code, do not add fallback paths, backup providers, degraded modes or silent recovery unless a developer instruction explicitly requires them.
- If a required service or dependency is unavailable or returns invalid data, prefer an explicit error over a fallback implementation.
- Do not mask infrastructure, integration or configuration failures behind substitute behavior.

## 2. Repository structure

Create this structure:

```text
VoiceAgent/
├─ VoiceAgent.xcodeproj or VoiceAgent.xcworkspace
├─ Package.swift
├─ AGENT.md
├─ README.md
├─ Sources/
│  ├─ AgentApp/
│  ├─ AppShell/
│  ├─ Domain/
│  ├─ Application/
│  ├─ Voice/
│  ├─ LLM/
│  ├─ Tools/
│  ├─ Automation/
│  ├─ Persistence/
│  ├─ Security/
│  └─ Shared/
└─ Tests/
   ├─ DomainTests/
   ├─ ApplicationTests/
   ├─ VoiceTests/
   ├─ LLMTests/
   ├─ ToolsTests/
   └─ SecurityTests/
```

If using Swift Package Manager with an app target, keep `AgentApp` as the executable/app target and all other modules as library targets.

## 3. Module responsibilities

### AgentApp

Composition root and app entry point.

Responsibilities:

- create dependencies;
- inject dependencies into SwiftUI views;
- define app lifecycle;
- do not contain business logic.

### AppShell

SwiftUI UI, app state, settings and permission prompts.

Responsibilities:

- transcript UI;
- listening state;
- pending confirmation UI;
- approve/reject controls;
- settings screens;
- permission request flows.

### Domain

Pure business model.

Responsibilities:

- `AgentPlan`;
- `ToolCall`;
- `ToolResult`;
- `ToolRiskLevel`;
- `PolicyDecision`;
- `ConfirmationChallenge`;
- domain errors;
- value objects.

Must not import platform frameworks.

### Application

Use cases and orchestration.

Responsibilities:

- `AgentOrchestrator` actor;
- planning protocol;
- policy checking protocol;
- tool execution protocol;
- conversation memory protocol;
- audit logging protocol;
- confirmation flow.

### Voice

Audio input, STT, TTS and voice pipeline.

Responsibilities:

- `AudioCapturing`;
- `SpeechRecognizing`;
- `SpeechSynthesizing`;
- `VoicePipeline` actor;
- Apple Speech adapter;
- AVSpeechSynthesizer adapter.

### LLM

Language model abstraction.

Responsibilities:

- `LLMClient` protocol;
- local HTTP LLM client;
- prompt compiler;
- typed tool-call parsing;
- streaming support.

Do not couple AgentCore to a specific LLM runtime.

### Tools

Typed tools available to the agent.

Responsibilities:

- `AgentTool` protocol;
- `ToolRegistry` actor;
- `ToolExecutor` actor;
- `OpenURLTool`;
- `OpenAppTool`;
- `ReadFileTool`;
- `WriteNoteTool`;
- `DraftEmailTool`;
- `SendEmailTool`;
- `DraftMessageTool`;
- `SendMessageTool`;
- `PreparePaymentTool`.

### Automation

macOS automation adapters.

Responsibilities:

- Accessibility API wrapper;
- Apple Events wrapper;
- screen capture wrapper;
- keyboard/mouse controller;
- browser automation primitives.

### Persistence

Local storage.

Responsibilities:

- audit log store;
- conversation store;
- settings store;
- optional SQLite integration.

### Security

Permissions, secrets and risk controls.

Responsibilities:

- `PermissionManager`;
- `KeychainStore`;
- `RiskEngine`;
- allowlist/denylist rules;
- confirmation phrase generator.

### Shared

Small shared utilities.

Responsibilities:

- common errors;
- logging wrappers;
- JSON helpers;
- test helpers.

Do not let `Shared` become a dumping ground.

## 4. Core domain types

Implement these first.

```swift
public enum ToolRiskLevel: String, Codable, Sendable {
    case safe
    case reversible
    case externalCommunication
    case financialOrCritical
}
```

```swift
public enum ToolArgument: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
}
```

```swift
public struct ToolCall: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let arguments: [String: ToolArgument]
    public let riskLevel: ToolRiskLevel

    public init(
        id: UUID = UUID(),
        name: String,
        arguments: [String: ToolArgument],
        riskLevel: ToolRiskLevel
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.riskLevel = riskLevel
    }
}
```

```swift
public struct AgentPlan: Codable, Sendable, Equatable {
    public let id: UUID
    public let userText: String
    public let summary: String
    public let toolCalls: [ToolCall]

    public var highestRiskLevel: ToolRiskLevel {
        if toolCalls.contains(where: { $0.riskLevel == .financialOrCritical }) {
            return .financialOrCritical
        }
        if toolCalls.contains(where: { $0.riskLevel == .externalCommunication }) {
            return .externalCommunication
        }
        if toolCalls.contains(where: { $0.riskLevel == .reversible }) {
            return .reversible
        }
        return .safe
    }
}
```

```swift
public struct ConfirmationChallenge: Codable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let summary: String
    public let requiredPhrase: String?
}
```

```swift
public enum PolicyDecision: Sendable, Equatable {
    case allow
    case requiresConfirmation(ConfirmationChallenge)
    case deny(String)
}
```

```swift
public enum ToolResult: Sendable, Equatable {
    case success(String)
    case requiresUserInput(String)
    case failed(String)
}
```

## 5. Core protocols

### Planning

```swift
public protocol Planning: Sendable {
    func makePlan(
        userText: String,
        context: ConversationContext
    ) async throws -> AgentPlan
}
```

### Policy

```swift
public protocol PolicyChecking: Sendable {
    func evaluate(_ plan: AgentPlan) async throws -> PolicyDecision
}
```

### Tool execution

```swift
public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var riskLevel: ToolRiskLevel { get }

    func run(_ call: ToolCall) async throws -> ToolResult
}
```

```swift
public protocol ToolExecuting: Sendable {
    func execute(_ plan: AgentPlan) async throws -> [ToolResult]
}
```

### Memory

```swift
public protocol AgentMemory: Sendable {
    func append(_ message: ConversationMessage) async
    func currentContext() async -> ConversationContext
}
```

### Audit logging

```swift
public protocol AuditLogging: Sendable {
    func record(_ event: AuditEvent) async throws
}
```

### Voice

```swift
public struct AudioFrame: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let timestampNanos: UInt64
}
```

```swift
public protocol AudioCapturing: Sendable {
    func frames() async throws -> AsyncThrowingStream<AudioFrame, Error>
}
```

```swift
public enum TranscriptKind: Sendable, Codable {
    case partial
    case final
}
```

```swift
public struct TranscriptEvent: Sendable, Codable {
    public let text: String
    public let kind: TranscriptKind
    public let confidence: Double?
}
```

```swift
public protocol SpeechRecognizing: Sendable {
    func transcribe(
        _ audio: AsyncThrowingStream<AudioFrame, Error>
    ) async throws -> AsyncThrowingStream<TranscriptEvent, Error>
}
```

```swift
public protocol SpeechSynthesizing: Sendable {
    func speak(_ text: String) async throws
    func stop() async
}
```

### LLM

```swift
public protocol LLMClient: Sendable {
    func complete(_ request: LLMRequest) async throws -> LLMResponse
    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMToken, Error>
}
```

## 6. Actors to implement

### AgentOrchestrator

Implement as an `actor`.

Responsibilities:

1. Receive final user text.
2. Read memory context.
3. Ask planner for a typed `AgentPlan`.
4. Write audit log: plan created.
5. Ask `PolicyGate` for decision.
6. If allowed, execute tools.
7. If confirmation required, return confirmation challenge.
8. If denied, return denial.
9. Append final outcome to memory.

Do not put LLM-specific code in this actor.

### ToolRegistry

Implement as an `actor` holding `[String: any AgentTool]`.

Requirements:

- register tools;
- resolve by name;
- list available tool descriptors for prompt compilation;
- fail with typed error for unknown tools.

### ToolExecutor

Implement as an `actor`.

Requirements:

- execute tool calls sequentially by default;
- optionally support parallel execution for explicitly safe independent tools later;
- log each tool start and result;
- never bypass policy.

### ConversationMemory

Implement as an `actor`.

Requirements:

- store last N messages in memory;
- expose a compact context;
- optionally persist to disk later.

### AuditLog

Implement as an `actor`.

Requirements:

- append-only local audit events;
- include timestamp, plan id, tool call id and result;
- never silently drop events.

### VoicePipeline

Implement as an `actor`.

Responsibilities:

1. Start audio capture.
2. Feed audio into STT.
3. Process only final transcripts initially.
4. Send final text to `AgentOrchestrator`.
5. Speak result through TTS.
6. Expose state updates to UI.

## 7. Policy rules

Implement `DefaultPolicyGate`.

Rules:

```text
safe:
  allow automatically

reversible:
  allow automatically only if tool and target are allowlisted
  otherwise require confirmation

externalCommunication:
  always require confirmation

financialOrCritical:
  always require strong confirmation phrase
```

Strong confirmation phrase format:

```text
Подтверждаю действие: <short action summary>
```

Payment-related rules:

- The LLM may prepare a payment intent.
- The LLM must not execute a payment directly.
- The final execution requires a structured `PaymentConfirmation` from the human.
- Do not automate bank websites by unconstrained GUI clicking.

Email/message rules:

- Drafting is reversible.
- Sending is external communication.
- Always show recipient and final text before sending.
- Do not let the model alter the final text after approval.

File rules:

- Read/write only in approved directories for MVP.
- Full disk access is out of scope for MVP.

## 8. MVP implementation milestones

### Milestone 1 — Project skeleton

Goal: compile an empty modular app.

Tasks:

1. Create Swift package/app project.
2. Add modules listed in section 2.
3. Enable Swift 6 language mode.
4. Enable strict concurrency checking.
5. Add basic SwiftUI window.
6. Add placeholder `AppCompositionRoot`.
7. Add CI/local scripts for build and test.

Definition of done:

- `swift test` passes for package targets.
- Xcode build succeeds.
- No concurrency warnings in new code.

### Milestone 2 — Domain and Application core

Goal: implement the typed agent core without macOS integrations.

Tasks:

1. Implement domain types.
2. Implement protocols.
3. Implement `ConversationMemory` actor.
4. Implement `InMemoryAuditLog` actor.
5. Implement `DefaultPolicyGate` actor.
6. Implement `ToolRegistry` actor.
7. Implement `ToolExecutor` actor.
8. Implement `AgentOrchestrator` actor.
9. Add fake planner and fake tools for tests.

Tests:

- safe tool is allowed;
- external communication requires confirmation;
- financial action requires strong confirmation;
- unknown tool fails cleanly;
- audit log records plan and tool result.

Definition of done:

- Domain and Application tests pass.
- No AppKit/SwiftUI imports in Domain/Application.

### Milestone 3 — SwiftUI shell

Goal: provide a usable local control panel.

Tasks:

1. Add `AgentViewModel` marked `@MainActor`.
2. Add state model:
   - idle;
   - listening;
   - thinking;
   - needs confirmation;
   - executing;
   - error.
3. Add transcript panel.
4. Add pending confirmation panel.
5. Add approve/reject buttons.
6. Add audit log preview.

Definition of done:

- User can type text manually into the agent UI.
- Agent can produce a fake plan and run fake tools.
- Confirmation flow works from UI.

### Milestone 4 — TTS

Goal: speak agent responses.

Tasks:

1. Implement `AppleSpeechSynthesizer` using `AVSpeechSynthesizer`.
2. Wrap delegate callbacks if needed for async completion.
3. Add voice/language/rate settings.
4. Add stop speaking command.
5. Inject through `SpeechSynthesizing` protocol.

Definition of done:

- Agent can speak text responses.
- TTS can be stopped.
- UI remains responsive.

### Milestone 5 — STT

Goal: capture speech and produce final transcripts.

Tasks:

1. Add microphone permission flow.
2. Implement audio capture with `AVAudioEngine`.
3. Implement speech recognition adapter using Apple Speech framework.
4. Emit `TranscriptEvent.partial` and `TranscriptEvent.final`.
5. Integrate into `VoicePipeline`.
6. Add manual fallback input for testing.

Definition of done:

- User can speak a short command.
- UI shows partial transcript.
- Final transcript is sent to `AgentOrchestrator`.
- Agent speaks response.

### Milestone 6 — Local LLM client

Goal: replace fake planner with LLM-backed planner.

Tasks:

1. Implement `LLMClient` protocol models.
2. Implement HTTP client for a local OpenAI-compatible or Ollama-compatible endpoint.
3. Implement `PromptCompiler`.
4. Include available tools in the prompt.
5. Require strict JSON response from LLM.
6. Implement typed parser from JSON to `AgentPlan`.
7. Add robust fallback for invalid JSON.

Planner output must be JSON only:

```json
{
  "summary": "Open the requested website",
  "toolCalls": [
    {
      "name": "open_url",
      "riskLevel": "safe",
      "arguments": {
        "url": { "string": "https://example.com" }
      }
    }
  ]
}
```

Definition of done:

- A local LLM can turn simple user commands into typed plans.
- Invalid LLM output does not crash the app.
- The policy gate still controls all execution.

### Milestone 7 — Basic tools

Goal: implement safe and reversible tools.

Implement:

1. `OpenURLTool`
2. `OpenAppTool`
3. `ReadAllowedFileTool`
4. `WriteNoteTool`
5. `CreateDraftTool` with fake/in-memory client first

Definition of done:

- "Открой apple.com" opens browser.
- "Открой Notes" opens app.
- "Запиши заметку ..." writes into approved folder.
- File tools cannot access disallowed paths.

### Milestone 8 — Confirmation flow for real actions

Goal: make risky actions usable and safe.

Tasks:

1. Add pending plan storage.
2. Add approval command from UI.
3. Add rejection command from UI.
4. Add voice approval later; UI approval first.
5. Freeze approved tool arguments.
6. Execute only the frozen approved plan.
7. Log approval/rejection.

Definition of done:

- Sending/dangerous tools cannot execute without confirmation.
- Approved plan cannot be mutated by the LLM after confirmation.

### Milestone 9 — Mail and Messages drafts

Goal: draft-first communication.

Tasks:

1. Define `MailClient` protocol.
2. Define `MessageClient` protocol.
3. Implement draft-only tools first.
4. Implement send tools behind `externalCommunication` policy.
5. Show recipient and final body in confirmation UI.
6. Add tests that sending requires confirmation.

Definition of done:

- Agent can create a draft.
- Agent cannot send without approval.
- Audit log includes recipient and action type.

### Milestone 10 — macOS automation MVP

Goal: controlled OS automation.

Tasks:

1. Add Accessibility permission request.
2. Implement `OpenAppTool` through `NSWorkspace`.
3. Implement active app/window read.
4. Implement limited keyboard input.
5. Implement limited mouse click API.
6. Keep high-risk automation disabled by default.

Definition of done:

- Automation requires permission.
- User can see when automation mode is active.
- All automation actions are logged.

### Milestone 11 — Payment intent only

Goal: safe foundation for payments without executing real money movement.

Tasks:

1. Define `PaymentRequest`.
2. Define `PaymentIntent`.
3. Define `PaymentConfirmation`.
4. Implement `PreparePaymentTool` only.
5. Mark execution tools as disabled until explicit integration exists.
6. Require strong confirmation phrase for any payment-like action.

Definition of done:

- Agent can summarize a payment request.
- Agent cannot execute payment.
- Strong confirmation challenge is generated.

## 9. Prompting contract for planner

The planner must follow this contract:

```text
You are a local planning component for a macOS voice agent.
Return only valid JSON.
Do not execute actions.
Do not claim that an action was completed.
Choose only tools from the provided tool list.
Use the lowest risk level that matches the tool.
For messages/emails/payments, prepare drafts or intents first.
Never send external communication without confirmation.
Never perform payments or purchases directly.
```

The prompt compiler must include:

- user command;
- recent conversation context;
- available tools;
- tool schemas;
- safety rules;
- JSON output schema.

## 10. Testing plan

### Unit tests

Required test categories:

- Domain model encoding/decoding;
- risk level ordering;
- policy decisions;
- planner JSON parsing;
- tool registry resolution;
- tool executor error handling;
- allowed path validation;
- confirmation flow;
- audit logging.

### Integration tests

Use fakes/mocks for:

- LLM client;
- audio capture;
- STT;
- TTS;
- mail client;
- message client;
- payment client.

### Manual tests

Checklist:

1. Launch app.
2. Grant microphone permission.
3. Speak: "Открой apple.com".
4. Confirm browser opens.
5. Speak: "Создай заметку тест".
6. Confirm note file appears in approved folder.
7. Speak: "Отправь сообщение ...".
8. Confirm app asks for approval and does not send automatically.
9. Reject action.
10. Confirm nothing is sent and audit log records rejection.

## 11. Local build commands

Prefer these commands during implementation:

```bash
swift build
swift test
```

For Xcode project builds, add a project-specific command once the project exists, for example:

```bash
xcodebuild -scheme VoiceAgent -destination 'platform=macOS' build
xcodebuild -scheme VoiceAgent -destination 'platform=macOS' test
```

## 12. Definition of done for any PR/change

A change is done only when:

- it compiles;
- tests pass;
- no new concurrency warnings are introduced;
- public APIs are documented when non-obvious;
- risky actions are gated by policy;
- audit logging is preserved;
- no business logic is added to SwiftUI views;
- no platform imports leak into Domain;
- no new global mutable state is introduced.

## 13. Implementation order for Codex

Follow this exact order unless blocked:

1. Create module skeleton.
2. Implement Domain types.
3. Implement Application protocols.
4. Implement in-memory actors.
5. Implement policy tests.
6. Implement fake planner and fake tools.
7. Implement orchestrator tests.
8. Implement SwiftUI shell with manual text input.
9. Implement TTS.
10. Implement STT.
11. Implement LLM client abstraction.
12. Implement local HTTP LLM client.
13. Implement prompt compiler and parser.
14. Implement safe tools.
15. Implement confirmation flow.
16. Implement communication drafts.
17. Implement limited automation.
18. Implement payment intent only.
19. Harden permissions.
20. Expand tests.

## 14. Out of scope for MVP

Do not implement these in the MVP:

- unconstrained full disk access;
- autonomous bank website clicking;
- automatic purchases;
- automatic message/email sending without confirmation;
- autonomous password manager access;
- unrestricted shell execution;
- unrestricted browser automation on arbitrary domains;
- cloud sync;
- multi-device support;
- plugin marketplace.

## 15. Security reminders for Codex

When in doubt, choose the safer implementation.

Never bypass:

- `PolicyGate`;
- `ToolRegistry`;
- confirmation flow;
- audit logging;
- approved directory checks;
- permission checks.

Never add a tool that gives the LLM raw unrestricted power such as:

- `runShell(command:)`;
- `clickAnything()`;
- `typeAnythingAnywhere()`;
- `readAnyFile(path:)`;
- `executePaymentWithoutConfirmation()`.

If a low-level capability is needed, expose a narrow, typed, auditable tool instead.

## 16. Initial MVP success scenario

The first successful demo should be:

1. User launches app.
2. User grants microphone permission.
3. User says: "Открой сайт apple.com".
4. STT transcribes command.
5. Planner creates `open_url` tool call.
6. Policy allows it.
7. Tool opens the URL.
8. Agent says: "Открыл apple.com".
9. Audit log shows the plan and execution result.

The second demo should be:

1. User says: "Отправь сообщение Анне: буду через 10 минут".
2. Planner creates an external communication plan.
3. Policy requires confirmation.
4. UI shows recipient and final text.
5. User rejects.
6. Nothing is sent.
7. Audit log records rejection.

## 17. Project-local skills

Use the project-local skills in `skills/` to keep implementation work aligned with this plan:

- `skills/gracula-swift-foundation/SKILL.md` — project skeleton, Swift Package targets, app entry point, build and test setup.
- `skills/gracula-domain-application-core/SKILL.md` — Domain/Application models, protocols, actors, policy, tool registry, executor, orchestrator, memory, and audit logging.
- `skills/gracula-voice-pipeline/SKILL.md` — microphone capture, Apple Speech transcription, TTS, `VoicePipeline`, and permission prompts.
- `skills/gracula-llm-planner/SKILL.md` — local LLM abstraction, prompt compiler, JSON-only planner output, typed parsing, and invalid-output handling.
- `skills/gracula-tools-security/SKILL.md` — safe tools, file allowlists, confirmation gates, communication drafts, limited automation, payment intents, permissions, and audit logging.

These skills do not replace the rules in this file. If a skill conflicts with `agent.md`, follow `agent.md`.
