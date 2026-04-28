---
name: gracula-swift-foundation
description: Use when creating or changing the Gracula Swift 6 macOS project skeleton, Package.swift targets, module boundaries, build settings, or local build/test commands.
---

# Gracula Swift Foundation

Use this skill before editing project structure, package manifests, app entry points, or build/test setup.

## Workflow

1. Read `agent.md` sections 1, 2, 8, 11, 12, and 13.
2. Keep the first version macOS-only.
3. Prefer Swift Package Manager with `AgentApp` as the executable/app target.
4. Create these library targets before implementation work spreads:
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
5. Add matching test targets under `Tests/`.
6. Enable Swift 6 language mode and strict concurrency checking.
7. Keep `AgentApp` as the composition root and lifecycle entry point.

## Guardrails

- Do not use Docker.
- Do not add business logic to `AgentApp`.
- Do not introduce singleton service locators or global mutable state.
- Do not let platform imports leak into `Domain`.

## Validation

Run:

```bash
swift build
swift test
```

For Xcode projects, add a project-specific `xcodebuild` command once a scheme exists.

