# TDD Integration Roadmap

Tracks testing/TDD integration across the fastedge-plugin skills.

Start here when working on anything testing-related. Check "Planned" items before starting new
testing work — pick up where a previous agent left off.

---

## Status: Completed

- [x] `/gcore-fastedge:test` skill — `plugins/gcore-fastedge/skills/test/SKILL.md`
  - Mode detection (generate / scaffold / run)
  - Steps: detect app type, check setup, verify install, generate/scaffold tests, create test-config.json, add npm scripts, run tests, summarise
  - Covers both CDN (proxy-wasm) and HTTP-WASM app types

- [x] `skills/test/reference/testing-api.md` — full `@gcoredev/fastedge-test` API reference
  - All assertion helpers from `assertions.ts`
  - `defineTestSuite`, `runAndExit`, `runFlow`, `loadConfigFile` from `suite-runner.ts`
  - `FlowOptions`, `FullFlowResult`, `HookResult` type reference
  - CDN vs HTTP-WASM comparison table
  - Complete examples

- [x] `skills/test/reference/test-config.md` — `test-config.json` schema reference
  - All fields documented
  - CDN property list
  - Visual debugger usage
  - Programmatic loading with `loadConfigFile`
  - Best practices

- [x] `skills/fastedge-docs/reference/best-practices.md` — testing checklist updated
  - Replaced stub checklist with CDN + HTTP-WASM specific checks
  - References `/gcore-fastedge:test` for setup

- [x] Deploy skill — pre-deploy test step (Step 1.5)
  - `plugins/gcore-fastedge/skills/deploy/SKILL.md`
  - Checks for test files: `tests/*.test.ts`, `tests/*.test.js`, `src/*.test.ts`
  - Runs `npm test` if found; blocks deployment on failure
  - Warns but continues if no tests exist
  - Added in original skill authoring (was listed as "Planned" in previous roadmap version — updated April 2026)

- [x] Scaffold skill — post-scaffold test setup offer
  - `plugins/gcore-fastedge/skills/scaffold/SKILL.md` (lines 235+)
  - Asks "Would you like to set up tests?" after scaffold completes
  - Invokes `/gcore-fastedge:test` in scaffold mode if accepted
  - Documented but not yet tested end-to-end

- [x] Scaffold skill — post-scaffold debug fixtures offer (April 2026)
  - Added alongside test offer as independent choice
  - Asks "Would you like to set up debug fixtures?"
  - Invokes `/gcore-fastedge:debug` if accepted
  - Tests and fixtures are independent — developer can accept both, one, or neither

- [x] `/gcore-fastedge:debug` skill — `plugins/gcore-fastedge/skills/debug/SKILL.md` (April 2026)
  - Generates `fixtures/` directory with scenario-specific `.test.json` files
  - Generates `fixtures/.env` with `FASTEDGE_VAR_ENV_*` / `FASTEDGE_VAR_SECRET_*` prefixed test values
  - CDN fixtures: `appType: "proxy-wasm"`, `request.url`, `response`, `properties`
  - HTTP fixtures: `appType: "http-wasm"`, `request.path`, geo via headers
  - Adds `"debug": "npx @gcoredev/fastedge-test"` script to package.json
  - Follows pattern from `FastEdge-sdk-rust/examples/*/fixtures/`

---

## Status: Planned

### Deploy skill — `--skip-tests` override flag

**File**: `plugins/gcore-fastedge/skills/deploy/SKILL.md`

The deploy skill's Step 1.5 blocks deployment on test failure. Add an explicit override:

```
If tests fail:
  - Abort and show results
  - Offer override: "Run `/gcore-fastedge:deploy --skip-tests` to deploy anyway"
```

**Why**: Sometimes developers need to deploy urgently despite test failures (hotfix, known flaky test).

---

### fastedge-docs — testing/debugging FAQ entry

**File**: `plugins/gcore-fastedge/skills/fastedge-docs/reference/best-practices.md`

Add FAQ entries:
- "How do I test my FastEdge app?" → `/gcore-fastedge:test`
- "How do I debug locally?" → `/gcore-fastedge:debug` + `npm run debug`

---

## Two Testing Concerns (Independent)

| Concern | Skill | Output | Runner | Purpose |
|---------|-------|--------|--------|---------|
| CI/CD tests | `/test` | `tests/*.test.ts` | `npm test` (headless, pass/fail) | Automated assertions, pre-deploy gate |
| Debug fixtures | `/debug` | `fixtures/*.test.json` + `.env` | `npm run debug` (visual UI) | Manual scenario exploration |

These are independent. A developer may want one, both, or neither. The scaffold skill offers both separately after project creation.

---

## Key Dependencies

| Dependency | Notes |
|------------|-------|
| `@gcoredev/fastedge-test` npm package | Published from the `fastedge-test` repo |
| `plugins/gcore-fastedge/skills/test/SKILL.md` | The test skill itself |
| `plugins/gcore-fastedge/skills/debug/SKILL.md` | The debug fixture skill |
| `plugins/gcore-fastedge/skills/test/reference/testing-api.md` | API reference (shared) |
| `plugins/gcore-fastedge/skills/test/reference/test-config.md` | Config schema (shared by test and debug) |
| `plugins/gcore-fastedge/skills/test/reference/vscode-debugger.md` | Debugger guide (shared by test and debug) |
