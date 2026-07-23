# Synthesis Instructions: test-framework.md

> For shared cross-referencing rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/test/reference/test-framework.md`

## Audience
AI agents helping developers write and run tests for FastEdge applications.

## Output goal
A concise, decision-dense API cheat-sheet. Not a tutorial. Agents use this to generate correct test code — they do not need background explanation.

## Required sections (in this order)

1. **Installation** — single `npm install` command and the two import paths (`@gcoredev/fastedge-test` and `@gcoredev/fastedge-test/test`)

2. **CDN vs HTTP-WASM** — a brief side-by-side comparison of the two test models (hooks lifecycle vs single execute call) so agents can select the right pattern for the app type

3. **Core functions** — function signature, parameter types, return type, and one-line description for each:
   - `defineTestSuite(config)` — config shape, mention `dotenvEnabled` option with a reference to the dotenv configuration guide (do NOT inline dotenv details)
   - `runAndExit(suite)` — exits 0/1
   - `runTestSuite(suite)` — programmatic, returns `SuiteResult`
   - `runFlow(runner, options)` — CDN only; named options, returns hook results by name
   - `runner.execute(options)` — HTTP-WASM only; request shape, returns response
   - `loadConfigFile(path?)` — reuses fastedge-config.test.json in tests

4. **Assertion helpers** — complete list as a table: function name | applies to | what it asserts. No prose. Include every exported assertion function.

5. **CDN minimal example** — complete runnable test file for a proxy-wasm app (10–15 lines)

6. **HTTP-WASM minimal example** — complete runnable test file for an HTTP-WASM app (10–15 lines)

7. **npm scripts** — the two recommended package.json script entries (`test`, `debug`). The `test` script must invoke the test file via `node` (or `tsx`/`ts-node`), NOT pass arguments to `npx @gcoredev/fastedge-test` — that command starts the visual debugger server only and accepts no file-path or watch arguments. Do NOT include a `test:watch` entry unless the source material explicitly documents a `--watch` flag.

## What to exclude
- Installation prerequisites (Node version, etc.)
- Package history or changelog
- Architecture explanation of how the test runner works internally
- Marketing language or feature highlights
- Anything not directly needed to write a test
- **Dotenv details** — prefix scheme, file options, priority order all belong in the dotenv configuration guide. Only mention `dotenvEnabled` as a boolean option in `defineTestSuite` with a reference to that guide.

## Quality bar
The existing file at `plugins/gcore-fastedge/skills/test/reference/test-framework.md` sets the quality bar. Update it to reflect the current package version and API surface — do not change the structure unless the source has fundamentally changed.
