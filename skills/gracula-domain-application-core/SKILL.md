---
name: gracula-domain-application-core
description: Use when implementing Gracula Domain and Application layers, domain models, protocols, in-memory actors, PolicyGate, ToolRegistry, ToolExecutor, AgentOrchestrator, memory, and audit logging.
---

# Gracula Domain and Application Core

Use this skill for the typed agent core before adding macOS, voice, or LLM integrations.

## Required Reading

Read `agent.md` sections 3, 4, 5, 6, 7, 10, 12, 13, and 15.

## Implementation Order

1. Implement Domain value types:
   - `ToolRiskLevel`
   - `ToolArgument`
   - `ToolCall`
   - `AgentPlan`
   - `ConfirmationChallenge`
   - `PolicyDecision`
   - `ToolResult`
2. Add narrow `Sendable` protocols:
   - `Planning`
   - `PolicyChecking`
   - `AgentTool`
   - `ToolExecuting`
   - `AgentMemory`
   - `AuditLogging`
3. Implement actors:
   - `ConversationMemory`
   - `InMemoryAuditLog`
   - `DefaultPolicyGate`
   - `ToolRegistry`
   - `ToolExecutor`
   - `AgentOrchestrator`
4. Add fakes for tests before real adapters.

## Policy Rules

- `safe`: allow automatically.
- `reversible`: allow automatically only when tool and target are allowlisted; otherwise require confirmation.
- `externalCommunication`: always require confirmation.
- `financialOrCritical`: always require a strong confirmation phrase.

Strong confirmation phrase:

```text
Подтверждаю действие: <short action summary>
```

## Guardrails

- LLM never controls the OS directly.
- Every `ToolCall` must pass through `PolicyGate`.
- Every planned and executed action must be audit logged.
- Do not put LLM-specific code in `AgentOrchestrator`.
- Do not import platform frameworks in `Domain`.

## Tests

Cover:

- risk ordering and encoding;
- safe plan allowed;
- external communication requires confirmation;
- financial action requires strong confirmation;
- unknown tool fails cleanly;
- audit log records plan and tool result.

