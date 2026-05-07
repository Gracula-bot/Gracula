# Gracula Agent Guide

## Project Overview

Gracula is a macOS-only Swift 6 package plus an example macOS app. The package is split into SwiftPM targets that separate domain models, orchestration, voice, LLM planning, tools, security, persistence, automation, and SwiftUI shell code. The packaged executable target is `AgentApp`, and the separate Xcode example app under `Examples/GraculaExample` is a larger local runtime playground that bootstraps `.openclaw`, edits runtime settings, launches local services, and exercises package modules in a more opinionated way.

The architectural center is `AgentOrchestrator` in `Sources/Application/Orchestration/AgentOrchestrator.swift`. It stores conversation context, asks a planner for a typed `AgentPlan`, passes the plan through policy, executes approved `ToolCall`s through the tool registry, and records audit events. The LLM never executes side effects directly; it only returns JSON that is parsed into typed plans.

## Repository Structure

Important top-level paths:

- `Package.swift`: SwiftPM product and target graph. This is the source of truth for module dependencies.
- `Sources/`: reusable package code.
- `Tests/`: Swift Testing suites for package targets.
- `Examples/GraculaExample/`: standalone Xcode app that links the local Swift package from `../..`.
- `ConfigFiles/`: canonical runtime configuration location used by `Persistence`.
- `Resources/WorkspaceTemplates/`: template markdown files copied into `.openclaw/workspace` by bootstrap.
- `Resources/RuntimeTemplates/`: template runtime assets such as speech requirements.
- `README.md`: build and manual test commands.
- `architecture.md`, `implementationplan.md`, `projectstatus.md`, `manualtesting.md`: historical project docs. Useful context, but not the primary architecture source.

Package targets in `Sources/`:

- `AgentApp`: executable target and composition root.
- `AppShell`: reusable SwiftUI shell and `AgentViewModel`.
- `Domain`: pure models and enums.
- `Application`: orchestration, protocol ports, audit, memory, policy, tool registry/executor, Telegram command flow.
- `Voice`: package voice pipeline plus Apple speech/audio adapters.
- `LLM`: prompt compilation, LLM clients, JSON parsing, metrics store.
- `Tools`: concrete tool implementations.
- `Automation`: macOS OS-integration adapters such as URL/app opening and Telegram Desktop automation.
- `Persistence`: runtime layout, canonical config, environment export, bootstrap/dependency verification, filesystem client.
- `Security` as target `AgentSecurity`: path allowlist and security errors.
- `Shared`: currently only `SharedModule.swift`; effectively a marker target.

Tests mirror the package targets:

- `Tests/DomainTests`
- `Tests/ApplicationTests`
- `Tests/VoiceTests`
- `Tests/LLMTests`
- `Tests/ToolsTests`
- `Tests/SecurityTests`
- `Tests/PersistenceTests`

Example app structure:

- `Examples/GraculaExample/GraculaExample/AgentApp/GraculaExampleApp.swift`: example app entry point.
- `Examples/GraculaExample/GraculaExample/AppShell/`: example-only SwiftUI and controller code.
- `Examples/GraculaExample/GraculaExample/Voice/`: example-only local speech/transcription/runtime helpers.
- `Examples/GraculaExample/GraculaExample/Persistence/`: example-only settings bridge code layered on top of package `Persistence`.
- `Examples/GraculaExample/GraculaExample/Shared/`: example-only logging.

## Architecture

### Layering and responsibilities

`Domain` is the innermost reusable layer. It contains `AgentPlan`, `ToolCall`, `ToolArgument`, `ToolResult`, `ToolRiskLevel`, `PolicyDecision`, `ConfirmationChallenge`, `ConversationContext`, `ConversationMessage`, `AuditEvent`, and error enums. It depends only on `Foundation`.

`Application` is the orchestration layer. Its public protocols define seams for planning, tool execution, memory, audit logging, and policy checking. `AgentOrchestrator` is an actor that owns the core flow:

1. append user text into `AgentMemory`;
2. build `ConversationContext`;
3. ask `Planning` for an `AgentPlan`;
4. audit the plan;
5. ask `PolicyChecking` whether it can run;
6. execute via `ToolExecuting` if allowed;
7. append assistant output back to memory.

`Application` also contains concrete but still package-level orchestration for Telegram commands: `TelegramCommandHandler`, `TelegramRoutingService`, `PendingTelegramReplyStore`, `TelegramIntentParser`, TDLib bridge types, and Telegram data models. This means the current `Application` target is not purely abstract use-case code; it also contains transport-specific integration logic.

`LLM` is a planner adapter layer, not a side-effect layer. `PromptCompiler` converts current user text, recent conversation, and `ToolDescriptor`s into a strict prompt that asks for JSON only. `AgentPlanParser` enforces that JSON into valid tool names and typed arguments. `LLMPlanningAdapter` is the `Planning` implementation that combines a concrete `LLMClient`, prompt compiler, parser, and optional `LLMRequestMetricsStore`.

`Tools` contains concrete `AgentTool` implementations such as `OpenURLTool`, `OpenAppTool`, `PublishOnlyFansPostTool`, `ReadAllowedFileTool`, and `WriteNoteTool`. These types do not discover or approve themselves. They are registered into `ToolRegistry`, executed by `ToolExecutor`, and audited from `Application`.

`Automation` contains macOS-facing side effects. `WorkspaceOpeningClient` opens URLs, apps, and performs the OnlyFans posting flow. `TelegramMacAppAutomationService` drives Telegram Desktop through AppKit, pasteboard, CGEvent key presses, Accessibility, and app activation.

`Persistence` owns runtime filesystem layout and canonical configuration. `ProjectRuntimeLayout` resolves the repo root and `.openclaw` layout. `AppConfigurationStore` loads, creates, normalizes, repairs, and saves `ConfigFiles/AppConfiguration.plist`. `AppConfigurationEnvironmentBuilder` exports that config into environment variables consumed by package code and the example app. `AppBootstrapper`, `DependencyVerifier`, and `RuntimeDependencyInstaller` prepare the local runtime and workspace templates.

`AgentSecurity` is currently small and focused. `PathAllowlist` validates that file operations stay inside approved directories. File-reading and file-writing tools compose it with `Persistence.FileSystemClient`.

`Voice` is split in two layers inside the package. At the abstract edge it defines `AudioCapturing`, `SpeechRecognizing`, `SpeechSynthesizing`, `TranscriptEvent`, and `VoiceError`. `VoicePipeline` is an actor that consumes audio frames, streams transcripts, runs the orchestrator only on final transcript events, and optionally speaks the resulting message. Concrete Apple adapters live in the same target: `AppleAudioCapture`, `AppleSpeechRecognizer`, and `AppleSpeechSynthesizer`.

`AppShell` is the package UI layer. `AgentView` is the reusable SwiftUI view. `AgentViewModel` is a `@MainActor` `ObservableObject` that holds UI state, pending confirmation state, pending Telegram reply state, audit preview strings, and LLM metrics. It talks to `AgentOrchestrator`, `OpenClawVoiceCommandRouter`, and `SpeechSynthesizing`; SwiftUI views stay declarative.

`AgentApp` is the package composition root. `GraculaApp.swift` is the executable entry point. `AppCompositionRoot` constructs all concrete dependencies: audit log, filesystem, allowlist, tools, tool registry/executor, planner, Telegram routing, policy gate, memory, and speech synthesizer, then injects them into `AgentViewModel`.

### Dependency direction

The package dependency graph is currently:

- `Domain` and `Shared` have no internal target dependencies.
- `Application`, `Persistence`, and `AgentSecurity` depend on `Domain` and optionally `Shared`.
- `LLM` and `Voice` depend on `Application` plus `Domain` and `Shared`.
- `Automation` depends on `Application` plus `Domain` and `Shared`.
- `Tools` depends on `Application`, `Domain`, `Automation`, `Persistence`, `AgentSecurity`, and `Shared`.
- `AppShell` depends on `Application`, `Domain`, `LLM`, `Voice`, and `Shared`.
- `AgentApp` depends on every reusable module and wires them together.

This is the practical rule: keep new business logic moving inward toward `Domain` and `Application`, and keep OS/framework code moving outward toward `Automation`, `Voice`, `Persistence`, or the example app.

### State ownership

Mutable shared state is actor-based in the package:

- `ConversationMemory` stores recent conversation messages.
- `InMemoryAuditLog` stores audit events.
- `ToolRegistry` stores registered tools.
- `ToolExecutor` serially executes tool calls.
- `AgentOrchestrator` coordinates planning and execution.
- `VoicePipeline` owns the active speech task.
- Telegram services and stores are actors where they hold mutable state.
- `LLMRequestMetricsStore` stores the latest request/metrics for UI inspection.

UI state lives on the main actor:

- `AppShell.AgentViewModel` uses `@Published` properties and is initialized through `StateObject`.
- Example app view models such as `AudioRecorderViewModel` and `OpenClawLocalController` are also main-thread/UI-facing state holders.

### Side effects and integrations

Package side effects are concentrated in a few places:

- `AppCompositionRoot` decides approved directories, planner backend, and Telegram backend selection from canonical config and environment.
- `Persistence` reads/writes plist files, creates directories, and validates local runtime dependencies.
- `Automation` opens apps/URLs and automates Telegram Desktop.
- `Tools` perform actual actions after policy approval.
- `Voice` uses Apple framework adapters for audio/STT/TTS.

The example app adds a second, larger integration layer:

- `GraculaExampleApp` runs `AppBootstrapper.bootstrapFoundation()` on startup.
- `OpenClawLocalController` owns OpenClaw runtime bootstrapping, direct-model and gateway startup, health checks, settings editing, chat state, local notification speech, Telegram user API startup, and manual publishing flows.
- Example-only voice/runtime helpers in `Examples/.../Voice/` are not part of the reusable package.

### Public API and entry points

The public package surface is wider than a single facade. Important public entry points include:

- `AppShell.AgentView`, `AppShell.AgentViewModel`, and `AppShell.BotSettingsSnapshot`.
- `Application.AgentOrchestrator`, `DefaultPolicyGate`, `ToolRegistry`, `ToolExecutor`, `ConversationMemory`, `InMemoryAuditLog`, protocol ports, and Telegram-facing types/services.
- `Domain` models and enums.
- `LLM` clients, prompt/compiler/parser types, and metrics store.
- `Voice` protocol types, `VoicePipeline`, and Apple adapters.
- `Tools` concrete tool types.
- `Persistence` config/layout/bootstrap types.
- `AgentSecurity.PathAllowlist`.

Do not change names, cases, initializer shapes, or semantic behavior of these public types casually. The example app and tests import them directly.

### Example app integration with the package

The example Xcode project links the local Swift package via `XCLocalSwiftPackageReference "../.."`. Its target depends on package products such as `Application`, `Persistence`, `Voice`, `Tools`, `Automation`, and `AppShell`.

The example app does not launch the SwiftPM executable target. Instead it imports package libraries directly and builds its own UI/runtime layer around them. That distinction matters:

- package app path: `Sources/AgentApp` builds the minimal packaged agent UI;
- example app path: `Examples/GraculaExample` builds a richer runtime lab and should remain an example/integration harness, not the place where reusable package APIs are silently hidden.

## Development Rules for Agents

When adding code, keep it in the narrowest module that matches its responsibility.

- Put new domain concepts, enums, and value semantics in `Sources/Domain`.
- Put orchestration, policy, memory, tool execution coordination, and protocol seams in `Sources/Application`.
- Put planner/prompt/LLM transport changes in `Sources/LLM`.
- Put concrete tool implementations in `Sources/Tools`.
- Put OS-level automation or app-launch behavior in `Sources/Automation`.
- Put config/runtime layout/bootstrap/filesystem concerns in `Sources/Persistence`.
- Put file/path security checks in `Sources/Security`.
- Put reusable SwiftUI package UI in `Sources/AppShell`.
- Put package dependency wiring in `Sources/AgentApp/AppCompositionRoot.swift`.
- Put example-only runtime code, direct-model chat experiments, OpenClaw settings editors, and example voice helpers only under `Examples/GraculaExample`.

Avoid these common mistakes:

- Do not add business logic to `AgentView`, `ConfirmationView`, or other SwiftUI view bodies.
- Do not bypass `AgentPlan` / `ToolCall` / `ToolExecutor` by making the LLM or UI call side effects directly.
- Do not place example-only settings, OpenClaw process management, or temporary playground code into `Sources/`.
- Do not turn `Shared` into a dumping ground; it is effectively empty today.
- Do not weaken `PathAllowlist` checks in file tools for convenience.

Preserve current separation of concerns:

- planner output stays typed and validated in `LLM`;
- approval logic stays in `DefaultPolicyGate` or another `PolicyChecking` implementation;
- tool discovery stays in `ToolRegistry`;
- tool execution auditing stays in `ToolExecutor`;
- conversation history stays behind `AgentMemory`;
- UI confirmation state stays in `AppShell.AgentViewModel`, not in tool implementations.

Be conservative with public API changes:

- `Domain` models are used across many targets and test suites.
- `Application` protocols define the main extension seams.
- `AppConfiguration`, `ProjectRuntimeLayout`, and environment keys are consumed by both package code and the example app.
- example-only types may be changed more freely, but only if you also update the example UI/build path that uses them.

When working on the example app:

- treat it as an integration harness for package modules;
- keep package improvements in `Sources/` and use the example only to exercise them;
- keep direct OpenClaw process control, temporary testing UI, and runtime editing utilities inside `Examples/GraculaExample`.

## Swift Conventions

The codebase is in Swift 6 language mode and targets macOS 14.

Naming patterns:

- module names are nouns: `Domain`, `Application`, `Persistence`, `Voice`;
- many protocols use capability names or gerunds: `Planning`, `ToolExecuting`, `SpeechRecognizing`, `AuditLogging`;
- actor and service types are descriptive roles: `AgentOrchestrator`, `ToolRegistry`, `TelegramRoutingService`;
- errors end with `Error`;
- tool names are explicit verbs and map to stable string identifiers such as `open_url`, `read_allowed_file`, `write_note`.

Access control:

- reusable cross-target types are explicitly `public`;
- helper views, helper structs, extensions, and local parsing helpers are usually internal or `private`;
- match the existing minimal-exposure style: only mark a symbol `public` when another target truly imports it.

Concurrency:

- prefer `actor` for mutable shared state and cross-task coordination;
- prefer `@MainActor` for UI view models and UI-bound helpers;
- prefer `async` protocols and functions over callbacks;
- prefer `AsyncStream` / `AsyncThrowingStream` for voice and event streaming;
- preserve `Sendable` conformances and do not paper over concurrency with broad `@unchecked Sendable` unless the file already does so for framework interop.

SwiftUI and AppKit conventions:

- `AppShell` uses SwiftUI with `ObservableObject`, `@Published`, `@StateObject`, and `@ObservedObject`;
- package UI is SwiftUI-first;
- macOS integration code uses AppKit/CoreGraphics where needed;
- there is no UIKit target or UIKit usage in this repo; do not introduce UIKit abstractions into the package without a deliberate platform expansion.

Error handling:

- prefer typed errors (`LLMError`, `ToolError`, `SecurityError`, `TelegramCommandError`, `VoiceError`) at module boundaries;
- UI layers often surface `localizedDescription` or `String(describing: error)`; keep that behavior predictable;
- do not silently swallow failures in core flows unless the existing file already intentionally degrades.

Dependency injection:

- initializers are the default DI mechanism;
- `AppCompositionRoot` is the package composition root;
- the example app has its own composition in `GraculaExampleApp` and `OpenClawLocalController`;
- avoid introducing global service locators or hidden singleton dependencies beyond framework wrappers already present.

Protocol usage:

- add a protocol only when it creates a real seam for testing or platform substitution;
- the current important seams are `Planning`, `PolicyChecking`, `ToolExecuting`, `AgentMemory`, `AuditLogging`, `AgentTool`, `LLMClient`, `FileSystemClient`, `URLOpening`, `AppOpening`, `OnlyFansPosting`, `AudioCapturing`, `SpeechRecognizing`, and `SpeechSynthesizing`.

## Testing Guidance

Tests use Swift Testing, not XCTest. The pattern is `import Testing`, `@Test`, and `#expect(...)`.

Where tests live:

- pure model/value behavior: `Tests/DomainTests`
- orchestration, policy, tool registry/executor, Telegram command flow: `Tests/ApplicationTests`
- voice pipeline behavior and speech helpers: `Tests/VoiceTests`
- prompt compilation and planner parsing: `Tests/LLMTests`
- concrete tool behavior: `Tests/ToolsTests`
- path allowlist/security rules: `Tests/SecurityTests`
- config/bootstrap/layout behavior: `Tests/PersistenceTests`

Primary commands:

- package tests: `swift test`
- package graph inspection: `swift package describe`
- example app build: `xcodebuild -project Examples/GraculaExample/GraculaExample.xcodeproj -scheme GraculaExample -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`

What to test for common changes:

- new domain types: Codable, equality, risk ordering, and value semantics;
- new orchestration logic: planner-to-policy-to-execution flow and audit events;
- new tool: argument validation, risk level, success path, and failure path;
- new persistence behavior: canonical plist creation/repair/normalization and environment export;
- new LLM behavior: prompt contents, parsing, and invalid-output rejection;
- new voice behavior: stream sequencing, final-transcript gating, and speech output;
- new example-only UI/runtime logic: at minimum build the example app and manually exercise the affected flow.

The example app currently has no dedicated automated test target in this repo. Treat example changes as build-plus-manual-verification work unless you also add example tests explicitly.

## Example App Guidance

The example app is the integration sandbox for local runtime behavior that is intentionally broader than the packaged app. Use it to:

- verify package changes against a real macOS UI;
- exercise local speech recording/transcription/synthesis flows;
- verify canonical config editing and bootstrap behavior;
- validate OpenClaw gateway/direct-model interactions;
- manually test Telegram and local automation flows.

Keep the boundary clean:

- reusable code belongs in `Sources/`;
- example-only adapters, settings editors, and local experimentation belong in `Examples/GraculaExample`;
- do not make package APIs depend on example-only settings types like `VoicePipelineSettings` or example-only controller types like `OpenClawLocalController`.

If a package change requires example updates, update the example as a consumer of the package, not as a hidden second implementation of package internals.

## Common Tasks

### Add a new feature

1. Decide whether the feature is domain logic, orchestration, tooling, automation, persistence, voice, LLM, or UI.
2. Add the smallest public surface needed in the appropriate target.
3. Wire dependencies in `AppCompositionRoot` if the packaged app needs the feature.
4. Update the example app only if it should demonstrate or exercise the feature.
5. Add or extend tests in the matching `Tests/*Tests` target.

### Change a public API

1. Search for usages across `Sources/`, `Tests/`, and `Examples/GraculaExample`.
2. Update the package tests first so behavior stays explicit.
3. Update the example app build path and any manual test instructions.
4. Avoid changing stable string identifiers such as tool names unless migration is intentional.
5. Document the change in `README.md` or another relevant root doc when it affects consumers or setup.

### Add a new tool

1. Implement a new `AgentTool` in `Sources/Tools`.
2. Inject any OS or filesystem dependency through protocols from `Automation`, `Persistence`, or `Application`.
3. Register it in `Sources/AgentApp/AppCompositionRoot.swift`.
4. Expose a matching `ToolDescriptor` via the registry automatically.
5. Add `ToolsTests` coverage for arguments, risk level, and side effects.

### Add a new screen or example flow

1. If it is reusable package UI, add it to `Sources/AppShell`.
2. If it is example-only runtime UI, add it under `Examples/GraculaExample/GraculaExample/AppShell`.
3. Keep view models on the main actor and move heavy logic into services/actors.
4. Build the example app and manually exercise the screen.

### Add a new test

1. Prefer the target-local test suite over a cross-target catch-all.
2. Use `@Test` and `#expect`, following existing files.
3. Use fakes/protocol seams where they already exist instead of adding heavyweight integration setup.
4. For actor-backed code, test observable outcomes rather than internal implementation details.

### Update documentation

1. Put repo-level developer guidance in `AGENT.md` or `README.md`.
2. Keep runtime template content changes in `Resources/WorkspaceTemplates` or `Resources/RuntimeTemplates`.
3. Do not confuse repo-level `AGENT.md` with runtime workspace template `Resources/WorkspaceTemplates/AGENTS.md`; they serve different purposes.

## Do / Don’t

Do:

- keep plans typed as `AgentPlan` and tool actions typed as `ToolCall`;
- add new behavior behind existing protocol seams when possible;
- use actors for mutable shared state;
- keep example-only runtime code inside `Examples/GraculaExample`;
- run `swift test` for package changes and build the example app for example changes.

Don’t:

- put OS automation directly into `Domain`, `LLM`, or SwiftUI views;
- bypass policy checks or audit logging;
- add package dependencies from inner layers back into UI or example code;
- break public model or tool identifier semantics casually;
- move reusable package behavior into the example app just because it is faster to prototype there.

## Open Questions

- `Application` currently mixes core orchestration ports with concrete Telegram transport logic, including TDLib and business-bot integrations. Before adding more external integrations, decide whether they continue to belong here or should move into a separate integration target.
- `Shared` is effectively a marker module today. If new shared utilities are needed, decide whether to keep `Shared` intentionally minimal or to formalize what kinds of helpers are allowed there.
- The example app is a major integration surface, but there is no automated example test target yet. If the example becomes a required consumer, consider whether it should gain dedicated tests beyond build/manual coverage.
