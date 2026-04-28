---
name: gracula-tools-security
description: Use when implementing Gracula tools, macOS automation adapters, communication drafts/sending gates, file allowlists, payment intents, permission checks, risk controls, and audit logging.
---

# Gracula Tools and Security

Use this skill whenever adding or changing tools that can affect the OS, files, communications, automation, or payments.

## Required Reading

Read `agent.md` sections 3, 7, 8, 10, 12, 14, 15, and 16.

## Tool Workflow

1. Define a narrow typed tool.
2. Assign the lowest correct `ToolRiskLevel`.
3. Register the tool through `ToolRegistry`.
4. Ensure execution goes through `ToolExecutor`.
5. Ensure `PolicyGate` is evaluated before execution.
6. Add audit events for start, success, failure, approval, and rejection.
7. Add tests for policy, errors, and audit behavior.

## MVP Tools

Implement in this order:

1. `OpenURLTool`
2. `OpenAppTool`
3. `ReadAllowedFileTool`
4. `WriteNoteTool`
5. `CreateDraftTool`
6. communication send tools behind confirmation only
7. limited automation tools
8. `PreparePaymentTool` only

## Hard Rules

- Do not add unrestricted shell execution.
- Do not add unrestricted file access.
- Do not add unconstrained GUI clicking.
- Do not send messages or emails without explicit confirmation.
- Do not execute payments.
- Do not automate bank websites through free-form GUI actions.
- Do not request broad permissions before they are needed.

## File Access

- Read/write only inside approved directories for MVP.
- Full disk access is out of scope.
- Path validation must be tested.

## Communication

- Drafting is reversible.
- Sending is external communication.
- Always show recipient and final body before sending.
- Freeze approved arguments after confirmation.

## Payments

- The agent may prepare a payment intent.
- Execution is disabled until explicit integration exists.
- Payment-like actions require strong confirmation.

