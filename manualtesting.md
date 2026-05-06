# Manual Testing Guide

Use this guide from the repository root:

```bash
cd /Users/gg/Gracula
```

The strongest regression check for every milestone is:

```bash
swift test
```

Expected result today: 53 Swift Testing tests pass.

## Milestone 1 — Base Architecture

Check that the package still builds and the app target links:

```bash
swift build
```

Check that all targets are importable through the full test run:

```bash
swift test
```

Manual app launch:

```bash
swift run Gracula
```

Expected result: a macOS window opens with title `Gracula`, a command text field, `Run`, `Stop Speaking`, result area, and audit preview.

## Milestone 2 — Domain Core

Run the domain tests:

```bash
swift test --filter DomainTests
```

Expected result: tests for `ToolArgument`, `AgentPlan`, `ToolRiskLevel`, conversation models, policy decision, and audit events pass.

Manual source check:

```bash
rg "public (struct|enum).*AgentPlan|public enum ToolRiskLevel|public enum ToolArgument" Sources/Domain
```

Expected result: the core domain types are in `Sources/Domain` and do not depend on AppKit, SwiftUI, Voice, LLM, or Tools.

## Milestone 3 — Application Ports

Run application tests:

```bash
swift test --filter ApplicationTests
```

Expected result: protocol tests for `Planning`, `PolicyChecking`, `AgentTool`, `ToolExecuting`, `AgentMemory`, and `AuditLogging` pass.

Manual source check:

```bash
rg "public protocol" Sources/Application/Protocols
```

Expected result: application use cases depend on protocols, not concrete LLM, UI, or macOS adapters.

## Milestone 4 — In-Memory Core Actors

Run the same application test group:

```bash
swift test --filter ApplicationTests
```

Expected result: tests for `ConversationMemory`, `InMemoryAuditLog`, `DefaultPolicyGate`, `ToolRegistry`, `ToolExecutor`, and `AgentOrchestrator` pass.

Manual behavior to confirm in tests:

- safe plans execute automatically;
- non-allowlisted reversible plans request confirmation;
- external communication requests confirmation;
- financial or critical actions require a strong phrase;
- unknown tools fail cleanly.

## Milestone 5 — Manual SwiftUI Shell

Launch the app:

```bash
swift run Gracula
```

Manual checks:

- type `remember buy milk` and press `Run`;
- status should move through thinking/executed;
- result should say that a note was written;
- audit preview should show plan, policy, and tool events;
- press `Stop Speaking` while speech output is active.

Expected note location:

```bash
ls "$HOME/Library/Application Support/GraculaExample/Notes"
```

## Milestone 6 — Text-To-Speech

Run voice tests:

```bash
swift test --filter VoiceTests
```

Expected result: speech synthesis configuration and synthesizer-driver tests pass.

Manual app check:

```bash
swift run Gracula
```

Type `remember hello from speech test`, press `Run`, and verify that macOS speaks the result. Press `Stop Speaking` to stop playback.

## Milestone 7 — Speech-To-Text Pipeline

Run voice tests:

```bash
swift test --filter VoiceTests
```

Expected result: `VoicePipeline` tests pass and confirm that only final transcript events reach the orchestrator.

Manual runtime note: the low-level Apple audio capture and speech recognizer are implemented, but the current UI does not yet expose a start/stop listening control. Full microphone testing belongs to the next runtime UI milestone.

## Milestone 8 — LLM Planner

Run LLM tests:

```bash
swift test --filter LLMTests
```

Expected result: prompt compiler, strict JSON parser, invalid-output handling, unknown-tool rejection, risk-level validation, and adapter integration tests pass.

Manual OpenAI planner check:

```bash
OPENAI_API_KEY="your-openai-api-key" \
OPENAI_MODEL="gpt-5.4-mini" \
swift run Gracula
```

Expected result: when `OPENAI_API_KEY` is set, Gracula uses `LLMPlanningAdapter` with OpenAI Chat Completions. If `OPENAI_API_KEY` is missing but `GRACULA_LLM_ENDPOINT` is set, Gracula uses the existing local HTTP planner. Without either setting, it uses the built-in demo planner.

## Milestone 9 — Safe Tools

Run tools and security tests:

```bash
swift test --filter ToolsTests
swift test --filter SecurityTests
```

Manual URL check:

```bash
swift run Gracula
```

Type:

```text
https://apple.com
```

Expected result: default browser opens that URL.

Manual app check:

```text
open app Notes
```

Expected result: the macOS Notes app opens.

Manual write-note check:

```text
remember finish milestone 9
```

Expected result: a note is written to:

```bash
"$HOME/Library/Application Support/GraculaExample/Notes/note.txt"
```

Manual allowed-read check:

```bash
mkdir -p "$HOME/Documents/GraculaExample"
printf "hello from allowed file\n" > "$HOME/Documents/GraculaExample/test.txt"
swift run Gracula
```

Then type this command in the app, replacing `$HOME` with the full absolute path:

```text
read /Users/gg/Documents/GraculaExample/test.txt
```

Expected result: the result panel shows `hello from allowed file`.

Manual denied-read check:

```text
read /etc/passwd
```

Expected result: the command is rejected with `pathNotAllowed`; nothing outside the approved directories is read.
