---
name: gracula-llm-planner
description: Use when implementing Gracula LLM abstraction, local HTTP LLM client, prompt compiler, tool schema prompt, strict JSON planner output, typed parsing, and invalid-output handling.
---

# Gracula LLM Planner

Use this skill when replacing fake planning with LLM-backed typed planning.

## Required Reading

Read `agent.md` sections 5, 6, 7, 8, 9, 10, 12, 13, and 15.

## Workflow

1. Define `LLMClient`, `LLMRequest`, `LLMResponse`, and `LLMToken`.
2. Implement a local HTTP client for an OpenAI-compatible or Ollama-compatible endpoint.
3. Implement `PromptCompiler`.
4. Include in the prompt:
   - user command;
   - recent conversation context;
   - available tools;
   - tool schemas;
   - safety rules;
   - JSON output schema.
5. Require JSON-only output.
6. Parse output into `AgentPlan`.
7. Reject unknown tools or invalid risk levels.
8. Treat invalid JSON as a recoverable planner failure.

## Planner Contract

The planner proposes typed `ToolCall` objects only. It must not execute actions or claim completion.

For messages, emails, and payments, prefer drafts or intents first.

## Guardrails

- Do not couple `Application` to a specific LLM runtime.
- Do not let model output bypass `PolicyGate`.
- Do not let the model mutate approved tool arguments after confirmation.
- Do not add free-form shell, click-anywhere, read-any-file, or execute-payment tools.

## Tests

Cover:

- valid JSON plan parsing;
- invalid JSON failure;
- unknown tool rejection;
- wrong risk level rejection;
- external communication plan still requires confirmation.

