# Gracula Architecture

Gracula is a native macOS Swift 6 voice agent. The architecture uses Clean/Hexagonal Architecture: the domain model is pure Swift, application use cases depend on protocols, and macOS integrations live behind adapters.

The central safety rule is simple: the LLM may only propose typed `ToolCall` values. It never executes OS actions directly. Every tool call must pass through `PolicyGate`, `ToolRegistry`, `ToolExecutor`, confirmation rules, permission checks, and audit logging.

## Proposed Repository Structure

```text
Gracula/
├─ Package.swift
├─ README.md
├─ agent.md
├─ implementationplan.md
├─ architecture.md
├─ skills/
│  ├─ gracula-swift-foundation/
│  ├─ gracula-domain-application-core/
│  ├─ gracula-voice-pipeline/
│  ├─ gracula-llm-planner/
│  └─ gracula-tools-security/
├─ Sources/
│  ├─ AgentApp/
│  │  ├─ GraculaApp.swift
│  │  └─ AppCompositionRoot.swift
│  ├─ AppShell/
│  │  ├─ AgentView.swift
│  │  ├─ AgentViewModel.swift
│  │  ├─ ConfirmationView.swift
│  │  ├─ AuditLogPreviewView.swift
│  │  └─ SettingsView.swift
│  ├─ Domain/
│  │  ├─ AgentPlan.swift
│  │  ├─ ToolCall.swift
│  │  ├─ ToolArgument.swift
│  │  ├─ ToolRiskLevel.swift
│  │  ├─ ToolResult.swift
│  │  ├─ PolicyDecision.swift
│  │  ├─ ConfirmationChallenge.swift
│  │  ├─ ConversationModels.swift
│  │  ├─ AuditEvent.swift
│  │  └─ DomainError.swift
│  ├─ Application/
│  │  ├─ Protocols/
│  │  │  ├─ Planning.swift
│  │  │  ├─ PolicyChecking.swift
│  │  │  ├─ ToolExecuting.swift
│  │  │  ├─ AgentMemory.swift
│  │  │  └─ AuditLogging.swift
│  │  ├─ Orchestration/
│  │  │  └─ AgentOrchestrator.swift
│  │  ├─ Memory/
│  │  │  └─ ConversationMemory.swift
│  │  ├─ Audit/
│  │  │  └─ InMemoryAuditLog.swift
│  │  └─ Policy/
│  │     └─ DefaultPolicyGate.swift
│  ├─ Voice/
│  │  ├─ AudioCapturing.swift
│  │  ├─ SpeechRecognizing.swift
│  │  ├─ SpeechSynthesizing.swift
│  │  ├─ VoicePipeline.swift
│  │  ├─ AppleAudioCapture.swift
│  │  ├─ AppleSpeechRecognizer.swift
│  │  └─ AppleSpeechSynthesizer.swift
│  ├─ LLM/
│  │  ├─ LLMClient.swift
│  │  ├─ LLMModels.swift
│  │  ├─ LocalHTTPLLMClient.swift
│  │  ├─ PromptCompiler.swift
│  │  └─ AgentPlanParser.swift
│  ├─ Tools/
│  │  ├─ AgentTool.swift
│  │  ├─ ToolDescriptor.swift
│  │  ├─ ToolRegistry.swift
│  │  ├─ ToolExecutor.swift
│  │  ├─ OpenURLTool.swift
│  │  ├─ OpenAppTool.swift
│  │  ├─ ReadAllowedFileTool.swift
│  │  ├─ WriteNoteTool.swift
│  │  ├─ DraftEmailTool.swift
│  │  ├─ DraftMessageTool.swift
│  │  └─ PreparePaymentTool.swift
│  ├─ Automation/
│  │  ├─ AccessibilityPermissionClient.swift
│  │  ├─ WorkspaceOpeningClient.swift
│  │  ├─ ActiveWindowReader.swift
│  │  └─ LimitedInputController.swift
│  ├─ Persistence/
│  │  ├─ AuditLogStore.swift
│  │  ├─ ConversationStore.swift
│  │  ├─ SettingsStore.swift
│  │  └─ FileSystemPaths.swift
│  ├─ Security/
│  │  ├─ PermissionManager.swift
│  │  ├─ KeychainStore.swift
│  │  ├─ RiskEngine.swift
│  │  ├─ PathAllowlist.swift
│  │  └─ ConfirmationPhraseGenerator.swift
│  └─ Shared/
│     ├─ AppLogger.swift
│     ├─ JSONCoding.swift
│     └─ Clock.swift
└─ Tests/
   ├─ DomainTests/
   ├─ ApplicationTests/
   ├─ VoiceTests/
   ├─ LLMTests/
   ├─ ToolsTests/
   └─ SecurityTests/
```

## Module Responsibilities

### AgentApp

`AgentApp` is the composition root and macOS app entry point.

Responsibilities:

- create concrete dependencies;
- wire protocols to implementations;
- inject dependencies into `AppShell`;
- define app lifecycle.

It must not contain business logic.

### AppShell

`AppShell` contains SwiftUI views and main-actor UI state.

Responsibilities:

- transcript UI;
- manual text input;
- listening/thinking/executing/error states;
- pending confirmation UI;
- approval and rejection controls;
- settings and permission prompts;
- audit log preview.

The view model may call application use cases, but SwiftUI views should remain declarative.

### Domain

`Domain` is pure business model code.

Allowed dependencies:

- Swift standard library;
- Foundation when needed for `UUID`, `Date`, and Codable models.

Forbidden dependencies:

- AppKit;
- SwiftUI;
- AVFoundation;
- Speech;
- CoreGraphics;
- automation APIs;
- networking clients.

Core types:

- `AgentPlan`
- `ToolCall`
- `ToolArgument`
- `ToolRiskLevel`
- `PolicyDecision`
- `ConfirmationChallenge`
- `ToolResult`
- `ConversationContext`
- `ConversationMessage`
- `AuditEvent`

### Application

`Application` coordinates use cases through protocols.

Responsibilities:

- `AgentOrchestrator`;
- planning port;
- policy checking port;
- tool execution port;
- memory port;
- audit logging port;
- confirmation flow;
- in-memory MVP implementations.

Application code may depend on `Domain`, but not on macOS frameworks or concrete LLM implementations.

### Voice

`Voice` owns audio, STT, TTS, and voice orchestration.

Responsibilities:

- `AudioCapturing`;
- `SpeechRecognizing`;
- `SpeechSynthesizing`;
- `VoicePipeline`;
- `AVAudioEngine` adapter;
- Apple Speech adapter;
- `AVSpeechSynthesizer` adapter.

Adapters can import Apple frameworks. Protocol-facing models should stay small and `Sendable`.

### LLM

`LLM` turns user text and context into typed plans.

Responsibilities:

- `LLMClient`;
- local HTTP client;
- prompt compiler;
- strict JSON output contract;
- parser from JSON to `AgentPlan`;
- invalid-output recovery.

The LLM module must not execute tools or directly call macOS APIs.

### Tools

`Tools` contains typed agent capabilities.

Responsibilities:

- `AgentTool`;
- `ToolRegistry`;
- `ToolExecutor`;
- tool descriptors for prompting;
- safe/reversible/external/critical tool implementations.

The executor runs tool calls only after policy approval.

### Automation

`Automation` wraps macOS automation primitives.

Responsibilities:

- Accessibility permission checks;
- Apple Events wrapper if needed;
- `NSWorkspace` app opening;
- active app/window read;
- limited keyboard/mouse primitives.

Automation must expose narrow typed APIs, not free-form GUI control.

### Persistence

`Persistence` owns local storage.

Responsibilities:

- append-only audit log store;
- conversation store;
- settings store;
- approved file paths;
- optional SQLite later.

For MVP, in-memory stores can exist in `Application`; durable stores can be added here once behavior is proven.

### Security

`Security` owns permissions and risk controls.

Responsibilities:

- permission manager;
- keychain access;
- allowlist/denylist rules;
- path allowlist validation;
- risk engine;
- confirmation phrase generation.

Security rules must be testable without UI.

### Shared

`Shared` contains small cross-cutting utilities.

Allowed:

- logging wrappers;
- JSON helpers;
- clock abstraction;
- common test helpers.

Do not let `Shared` become a dumping ground for business logic.

## Dependency Direction

Dependencies must point inward:

```text
AgentApp
  -> AppShell
  -> Application
  -> Domain

Voice       -> Application, Domain
LLM         -> Application, Domain
Tools       -> Application, Domain, Automation, Persistence, Security
Automation  -> Domain only when typed values are needed
Persistence -> Domain
Security    -> Domain
Shared      -> no business dependency
```

Rules:

- `Domain` depends on nothing project-specific.
- `Application` depends on `Domain`.
- `AppShell` depends on `Application` and `Domain`.
- Infrastructure modules implement protocols and are injected from `AgentApp`.
- No module should reach across layers to instantiate hidden dependencies.

## Runtime Flow

### Safe Action Flow

```text
User speech/text
-> AppShell or VoicePipeline
-> AgentOrchestrator
-> AgentMemory.currentContext()
-> Planning.makePlan()
-> AuditLogging.record(planCreated)
-> PolicyGate.evaluate(plan)
-> ToolExecutor.execute(plan)
-> AuditLogging.record(toolStarted/toolFinished)
-> AgentMemory.append(outcome)
-> AppShell renders result
-> SpeechSynthesizing.speak(result)
```

### Confirmation Flow

```text
User speech/text
-> Planner creates risky AgentPlan
-> PolicyGate returns requiresConfirmation
-> AppShell shows ConfirmationChallenge
-> User approves or rejects
-> approval/rejection is audit logged
-> approved plan is executed with frozen arguments
```

Important: the LLM is not called again to modify an approved plan. Approval applies only to the exact frozen tool arguments shown to the user.

## Safety Architecture

Every action with side effects must pass these gates:

1. Typed `ToolCall`
2. Known tool in `ToolRegistry`
3. `PolicyGate` decision
4. Permission check when required
5. Confirmation challenge when required
6. Frozen approved arguments
7. `ToolExecutor`
8. Audit log event

Risk handling:

- `safe`: allow automatically.
- `reversible`: allow only if tool and target are allowlisted; otherwise require confirmation.
- `externalCommunication`: always require confirmation.
- `financialOrCritical`: always require strong confirmation phrase.

Strong confirmation phrase:

```text
Подтверждаю действие: <short action summary>
```

## Concurrency Model

Use Swift structured concurrency throughout.

Actors:

- `AgentOrchestrator`
- `ConversationMemory`
- `InMemoryAuditLog`
- `DefaultPolicyGate`
- `ToolRegistry`
- `ToolExecutor`
- `VoicePipeline`

Rules:

- Cross-concurrency values must be `Sendable`.
- UI-facing view models are `@MainActor`.
- Avoid `Task.detached` unless there is a clear reason.
- Do not hide side effects in initializers.
- Prefer initializer dependency injection.

## Testing Strategy

### Domain Tests

- Codable round trips;
- risk level behavior;
- `AgentPlan.highestRiskLevel`;
- domain error behavior.

### Application Tests

- safe plan is allowed;
- external communication requires confirmation;
- financial action requires strong confirmation;
- unknown tool fails cleanly;
- orchestrator records audit events;
- confirmation approval executes frozen plan;
- rejection executes nothing.

### LLM Tests

- valid planner JSON parses into `AgentPlan`;
- invalid JSON fails safely;
- unknown tool is rejected;
- invalid risk level is rejected;
- planner never bypasses policy.

### Tools and Security Tests

- allowed path validation;
- disallowed path rejection;
- communication send tools require confirmation;
- payment tools prepare intent only;
- automation actions require permission.

### Voice Tests

Use fakes for:

- audio capture;
- speech recognition;
- speech synthesis.

Do not require real microphone access for unit tests.

## Build and Validation Commands

Initial commands:

```bash
swift build
swift test
```

Add Xcode commands after a scheme exists:

```bash
xcodebuild -scheme VoiceAgent -destination 'platform=macOS' build
xcodebuild -scheme VoiceAgent -destination 'platform=macOS' test
```

## MVP Delivery Order

1. Swift package and module skeleton.
2. Domain models.
3. Application protocols.
4. In-memory actors.
5. Policy tests.
6. Fake planner and fake tools.
7. Orchestrator tests.
8. SwiftUI shell with manual text input.
9. TTS.
10. STT.
11. LLM abstraction and local HTTP client.
12. Prompt compiler and JSON parser.
13. Safe tools.
14. Confirmation flow.
15. Communication drafts.
16. Limited automation.
17. Payment intent only.
18. Permission hardening.
19. Expanded tests.

