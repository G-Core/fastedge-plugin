# Synthesis Instructions: runner-internals.md

> For shared cross-referencing rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/test/reference/runner-internals.md`

## Audience
AI agents needing direct runner control beyond what `defineTestSuite` + `runAndExit` provides — e.g., custom test harnesses, programmatic WASM instance management, or advanced debugging workflows.

## Source file
`docs/RUNNER.md` — low-level runner API documentation

## Output goal
A reference for the runner's internal API. Agents use this when the high-level test framework (`defineTestSuite`, `runAndExit`) is insufficient and they need direct control over WASM instance lifecycle.

## Required sections (in this order)

1. **Runner Lifecycle** — how a runner instance is created, how it loads WASM, and how it executes requests. Include the sequence of operations.

2. **WASM Instance Management** — how instances are created, reused, and disposed. Memory limits, timeout behavior.

3. **Direct API** — if the runner exposes methods beyond `execute()` and `runFlow()`, document them here with signatures and return types.

## What to exclude
- High-level test framework API (`defineTestSuite`, `runAndExit`, assertions) — belongs in the test framework reference
- Config file schema — belongs in the test config reference
- Dotenv setup — belongs in the dotenv configuration guide
- Server/debugger details — belongs in the server API reference or VSCode debugger reference

## Quality bar
This is a new file. Generate clean, structured documentation focused on the internal mechanics that are useful for advanced use cases.
