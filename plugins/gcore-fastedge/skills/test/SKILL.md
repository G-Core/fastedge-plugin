---
disable-model-invocation: false
argument-hint: "[project-dir]"
description: Write and run tests for a FastEdge WASM app using @gcoredev/fastedge-test
---

# /gcore-fastedge:test

Write and run automated tests for a FastEdge WASM app.

## TDD Principle — Tests Before Deploy

**FastEdge development follows a test-driven cycle.** Tests must pass locally before any
code is deployed to the edge. This is not optional — it prevents deploying broken WASM binaries
that fail silently at the edge with 53x error codes.

The cycle:
```
Write tests → Build WASM → Run tests → Fix failures → All pass → Deploy
```

If a user asks to deploy without mentioning tests:
- Check whether tests exist (`fastedge-test/app.test.mjs` for the current layout, or legacy
  `tests/*.test.*` files at root).
- If no tests exist, prompt: "Before deploying, let's write tests for this app.
  Run `/gcore-fastedge:test` to generate a test suite, then we'll verify it passes locally."
- If tests exist but haven't been run, run them first.

The visual debugger (`npm run debug`) is the interactive complement to automated tests —
use it to inspect specific requests while fixing failures. Reference: `./reference/vscode-debugger.md`

---

## Mode Detection

Detect the user's intent from phrasing before starting:

| User says | Mode |
|-----------|------|
| "write tests", "generate tests", "create tests" | **Generate** — read source, produce complete test file |
| "set up testing", "help me test", "add testing" | **Scaffold** — create stub file with TODOs |
| "run my tests", "test my app", "run tests" | **Run** — verify setup and execute |

If ambiguous, ask: "Would you like me to generate tests from your source code, or just scaffold a starter file?"

---

## Project Layout (Option B)

The test harness always lives under `fastedge-test/` at the project root:

```
<project-root>/
├── fastedge-config.test.json     ← app-level, read by VSCode debugger + live-test
├── fixtures/                     ← app-level, debug + live-test scenarios
└── fastedge-test/
    └── app.test.mjs              ← the test file (always here)
```

What sits *next to* `app.test.mjs` inside `fastedge-test/` depends on the host language:

- **Rust apps**: `fastedge-test/` is a self-contained Node sandbox — its own `package.json`,
  `package-lock.json`, and `node_modules/`. The Rust crate root stays free of Node artifacts.
- **JS/TS and AssemblyScript apps**: only `app.test.mjs` lives in `fastedge-test/`. The Node
  install (devDeps for `@gcoredev/fastedge-test`) stays in the existing root `package.json`,
  because these apps are already Node projects.

The file is `.mjs` (plain ESM) regardless of language — no TypeScript runtime required, fewer
moving parts in the scaffold.

---

## Step 1 — Detect Project Type

Two axes determine the scaffold:

**Host language** — drives where the Node install lives.

| Marker file at project root | Language |
|---|---|
| `Cargo.toml` and **no** `package.json` | rust |
| `package.json` with `src/index.{ts,js,mjs,cjs}` (HTTP app) | js-ts |
| `asconfig.json` (AssemblyScript / proxy-wasm CDN app) | as |

If none match, ask the user to confirm.

**App type** — drives the test patterns used in `app.test.mjs`.

- **CDN / proxy-wasm**: AssemblyScript, or Rust with `proxy-wasm` filter callbacks. Hooks-based
  model (`onRequestHeaders`, `onResponseHeaders`, etc.). Test with `runFlow` + `assertFinal*`.
- **HTTP-WASM**: Standard Hono/fetch handler (JS/TS) or Rust `#[fastedge::http]`. Test with
  `runHttpRequest(runner, { path, method, headers })`.

Reference: `./reference/test-framework.md` for the patterns.

---

## Step 2 — Check Existing Test Setup

Look in this order:

1. **New layout**: `fastedge-test/app.test.mjs` and (Rust only) `fastedge-test/package.json`.
2. **Legacy layout** (existing users): root-level `tests/*.test.*` plus `@gcoredev/fastedge-test`
   in root `devDependencies`.
3. `fastedge-config.test.json` at project root.

**Decision tree:**

- New layout present → **work with it**, don't overwrite. Add new test cases to the existing
  `fastedge-test/app.test.mjs`.
- Legacy layout present → prompt for migration. See `## Migration from Legacy Layout` at the
  end of this skill.
- Neither present → proceed to Step 3 to create from scratch.

If only `fastedge-config.test.json` exists: use it for WASM path and request config when
generating the test file.

---

## Step 3 — Set Up the Node Install

**Rust branch:**

```bash
mkdir -p fastedge-test
cd fastedge-test
npm init -y                              # if package.json doesn't already exist
npm install --save-dev @gcoredev/fastedge-test@latest
```

The skill writes `fastedge-test/package.json` with the appropriate scripts (Step 6). Make sure
`fastedge-test/node_modules/` and `fastedge-test/package-lock.json` are git-ignored — append
to `.gitignore` at project root if not already covered:

```
fastedge-test/node_modules/
```

**JS/TS / AssemblyScript branch:**

Check the root `package.json` `devDependencies` for `@gcoredev/fastedge-test`. If missing:

```bash
npm install --save-dev @gcoredev/fastedge-test@latest
```

Do not proceed until the package is available. The `@latest` tag ensures the user picks up
ESM-bundle and binary-discovery fixes shipped in 0.2.3+.

---

## Step 4 — Generate or Scaffold the Test File

Always write to `fastedge-test/app.test.mjs`. The file resolves `wasmPath` relative to its own
location via `import.meta.url`, which keeps the relative path identical regardless of which
CWD the user runs the test from (root for JS/TS, `fastedge-test/` for Rust).

Reference: `./reference/test-framework.md`

### Pre-generate: Rust Stderr Logging Scan (Rust projects only)

**Skip this scan entirely for JS/TS and AssemblyScript projects.** Both SDKs route logging through stdout by construction (`console-override.cpp` in `@gcoredev/fastedge-sdk-js`; `process.stdout.write` in `@gcoredev/proxy-wasm-sdk-as`'s `runtime.ts`). Test cases that assert on log output will see the lines the source emits at any `console.*` / `log()` level.

**For Rust projects only**, run the stderr scan **before** authoring any test case in Generate mode. The scan exists because the failure mode is uniquely bad here: a test case asserting on a log substring that was emitted via `eprintln!` will silently fail at run-time with "expected log not found" — and the test author has no way to distinguish "log was never written" from "log went to the wrong file descriptor." Worse, if the local runner happens to capture stderr while the FastEdge edge does not, the test could PASS locally and the production app would still drop the same log lines invisibly.

#### Procedure

1. Glob all `.rs` files under `<project>/src/`.
2. Grep each file for stderr-bound patterns:
   - `\beprintln!` / `\beprint!`
   - `std::io::stderr\s*\(\s*\)` / `io::stderr\s*\(\s*\)`
   - `env_logger::(init|Builder::new)` not followed by `Target::Stdout`
   - `with_writer\s*\(\s*std::io::stderr` (tracing-subscriber stderr override)
   - `proxy_wasm::hostcalls::log\s*\(` / `hostcalls::log\s*\(` (proxy-wasm log hostcall; FastEdge does not capture hostcall-level logs — use `println!()` instead)
3. Collect every hit as `(file, line, matched_token, full_line_text)`.

#### When matches are found

Pause Generate mode and print this warning **before** writing `app.test.mjs`:

```
⚠ Stderr-bound logging detected in Rust source — refusing to generate
  log-based test assertions until this is resolved.

  <file>:<line>  <matched_token>
      <full_line_text>
  [...repeat per hit, up to 5; if more, append "(+N additional matches)"]

  FastEdge captures stdout only. Any test case asserting on these messages
  will fail at run-time because the log lines never reach the platform log
  stream. The visual debugger's log pane will also be empty for these calls.

  Choose one:
    [1] Fix the source (recommended) — convert to println!/print! (all Rust
        apps — HTTP and CDN), then re-run /gcore-fastedge:test.
    [2] Continue anyway — generate test cases without log assertions. Tests
        will cover status / headers / body only; logging-related behavior is
        left unverified.
    [3] Cancel.
```

Use `AskUserQuestion` with the three options above (single-select; `[1]` first as the recommended default).

- **[1] Fix the source**: exit the skill cleanly with the message "Re-run /gcore-fastedge:test once the source is fixed." Do not auto-rewrite — Generate-mode source mutations are out of scope; the scaffold skill's Step 4e is the only auto-rewrite layer (it owns code it authored). User-owned source belongs to the user.
- **[2] Continue anyway**: proceed to authoring, but **omit any test case whose assertion depends on a log substring derived from a flagged line**. Add a single comment to `app.test.mjs` above the suite definition recording which lines were skipped, e.g.:
  ```js
  // Note: stderr-bound logging detected at src/lib.rs:7 (eprintln!).
  // Log-based assertions skipped — see /gcore-fastedge:debug for guidance.
  ```
- **[3] Cancel**: exit without writing anything.

When matches are found and option [2] is chosen, also surface the diagnostic again in the Step 8 summary so the user sees it after the run completes — they may forget by the time generation finishes.

#### When no matches are found

Proceed silently to Generate Mode. No success message is printed — the absence of a warning is the signal.

### Generate Mode

1. Read the app entry file (`src/index.ts`, `src/main.rs`, or `assembly/index.ts`).
2. Identify all routes/handlers/hooks.
3. Create `fastedge-test/app.test.mjs` with one test case per route.

**HTTP-WASM template (Rust crate `hello_world`):**

```js
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  defineTestSuite,
  runAndExit,
  runHttpRequest,
  assertHttpStatus,
  assertHttpContentType,
  assertHttpBodyContains,
} from '@gcoredev/fastedge-test/test';

const here = dirname(fileURLToPath(import.meta.url));

await runAndExit(defineTestSuite({
  wasmPath: resolve(here, '../target/wasm32-wasip1/release/hello_world.wasm'),
  tests: [
    {
      name: 'GET / returns 200',
      async run(runner) {
        const response = await runHttpRequest(runner, { path: '/', method: 'GET' });
        assertHttpStatus(response, 200);
        assertHttpContentType(response, 'text/plain');
        assertHttpBodyContains(response, 'Hello');
      },
    },
  ],
}));
```

For JS/TS HTTP apps, swap the `wasmPath` to the project's `fastedge-build` output (typically
`../<app-name>.wasm` resolved against `here`):

```js
wasmPath: resolve(here, '../my-app.wasm'),
```

**CDN / proxy-wasm template (AssemblyScript or Rust):**

```js
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  defineTestSuite,
  runAndExit,
  runFlow,
  assertFinalStatus,
  assertFinalHeader,
} from '@gcoredev/fastedge-test/test';

const here = dirname(fileURLToPath(import.meta.url));

await runAndExit(defineTestSuite({
  // AssemblyScript: '../build/release.wasm'
  // Rust:           '../target/wasm32-wasip1/release/<crate>.wasm'
  wasmPath: resolve(here, '../build/release.wasm'),
  tests: [
    {
      name: 'GET / passes through with X-Custom header',
      async run(runner) {
        const result = await runFlow(runner, {
          url: 'https://example.com/',
          method: 'GET',
        });
        assertFinalStatus(result, 200);
        assertFinalHeader(result, 'x-custom', 'expected');
      },
    },
  ],
}));
```

### Scaffold Mode

Same shape but a single TODO case:

```js
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { defineTestSuite, runAndExit } from '@gcoredev/fastedge-test/test';

const here = dirname(fileURLToPath(import.meta.url));

await runAndExit(defineTestSuite({
  wasmPath: resolve(here, '../path/to/your.wasm'),
  tests: [
    {
      name: 'TODO: describe what this test checks',
      async run(runner) {
        // TODO: implement test
        throw new Error('Not implemented');
      },
    },
  ],
}));
```

---

## Step 5 — Create/Update test-config.json (at project root)

`fastedge-config.test.json` lives at the project root regardless of language — it's app-level
config consumed by the VSCode debugger and the live-test skill. Reference: `./reference/test-config.md`

The `$schema` path differs by language because it points into wherever `@gcoredev/fastedge-test`
is installed:

**Rust:**
```json
{
  "$schema": "./fastedge-test/node_modules/@gcoredev/fastedge-test/schemas/test-config.schema.json"
}
```

**JS/TS / AS:**
```json
{
  "$schema": "./node_modules/@gcoredev/fastedge-test/schemas/test-config.schema.json"
}
```

Use the WASM build output path from the build config. For CDN apps, include representative
`properties`. Full example:

```json
{
  "$schema": "<see above>",
  "description": "Test config for <app-name>",
  "wasm": {
    "path": "target/wasm32-wasip1/release/<crate>.wasm",
    "description": "<app description>"
  },
  "request": {
    "method": "GET",
    "url": "https://example.com/",
    "headers": {},
    "body": ""
  },
  "properties": {
    "request.country": "US",
    "request.city": "New York",
    "request.continent": "NA"
  },
  "logLevel": 0,
  "envVars": {},
  "secrets": {}
}
```

Omit `properties` for HTTP-WASM apps (not applicable).

---

## Step 5.5 — Secrets and Environment Variables Setup

If the app uses `getSecret()` or `getEnv()`, set up the secrets/env vars for local testing.
Reference: `./reference/dotenv.md`

These are **app-level** concerns and live at the project root, alongside `fixtures/` and
`fastedge-config.test.json` — not inside `fastedge-test/`.

**Detect whether secrets are needed:** check the source code for `getSecret(` or `getEnv(`
calls. If found, determine which keys are required and set them up using one of two methods:

### If the values are non-sensitive (safe to commit with placeholders):

Add them to `fastedge-config.test.json`:
```json
{
  "envVars": { "IDP_ENTITY_ID": "https://idp.example.com" },
  "secrets": { "SESSION_SECRET": "local-placeholder" }
}
```

### If the values are sensitive (real secrets, certificates, tokens):

1. Enable dotenv in the test suite by adding `runnerConfig: { dotenvEnabled: true }`:
```js
await runAndExit(defineTestSuite({
  wasmPath: resolve(here, '../target/wasm32-wasip1/release/<crate>.wasm'),
  runnerConfig: { dotenvEnabled: true },
  tests: [ /* ... */ ],
}));
```

2. Create `.env.example` at the project root (committed) showing the required variables:
```bash
# Copy to .env and fill in real values
FASTEDGE_VAR_SECRET_SESSION_SECRET=your-local-secret
FASTEDGE_VAR_SECRET_IDP_CERT=-----BEGIN CERTIFICATE-----...
FASTEDGE_VAR_ENV_IDP_ENTITY_ID=https://your-idp.example.com
```

3. Add `.env` and `.env.secrets` to `.gitignore` — tell the user to do this if not already present.

**For SAML apps specifically:** the IdP certificate and any signing keys must go in `.env`
via `FASTEDGE_VAR_SECRET_` prefix — never commit real certs to `fastedge-config.test.json`.

---

## Step 6 — Add npm Scripts

**Rust branch** — scripts go in `fastedge-test/package.json`:

```json
{
  "name": "<crate-name>-tests",
  "version": "0.0.0",
  "private": true,
  "scripts": {
    "test":  "node app.test.mjs",
    "debug": "npx @gcoredev/fastedge-test --project-dir .."
  },
  "devDependencies": {
    "@gcoredev/fastedge-test": "latest"
  }
}
```

The `--project-dir ..` flag tells the debugger to look for `fastedge-config.test.json` and
`fixtures/` at the project root, not in `fastedge-test/`. Requires `@gcoredev/fastedge-test`
0.2.3+.

**JS/TS / AssemblyScript branch** — scripts go in the root `package.json`:

```json
{
  "scripts": {
    "test":  "node fastedge-test/app.test.mjs",
    "debug": "npx @gcoredev/fastedge-test"
  }
}
```

No `--project-dir` needed; CWD is already the project root.

Do not overwrite existing scripts with different values — only add missing ones, and warn if
an existing script conflicts.

---

## Step 7 — Run Tests (Generate Mode or Run Mode)

Branch on language for the run command:

**Rust:**
```bash
cd fastedge-test && npm test
```

**JS/TS / AS:**
```bash
npm test           # from project root
```

1. Run the appropriate command.
2. Report results: how many passed, how many failed.
3. If failures: analyse the error message and suggest a fix.
   - `WASM not found` → build the app first (`cargo build --release --target wasm32-wasip1`
     for Rust, `npm run build` for JS/TS, `npm run asbuild:release` for AS).
   - `assertFinalStatus` mismatch → inspect the route logic.
   - `Expected request header ... to be set` → check hook implementation.
   - **Log assertion failure on a Rust project** (e.g. "expected log to contain `...`" with no matching capture) → run the Rust stderr-logging scan from Step 4's "Pre-generate" subsection once for the run (cache the result if multiple log assertions failed). If matches are found, attach the stderr diagnostic to every affected failure line in the report and prioritise it over other hypotheses — empty log captures on Rust apps are far more often "wrong file descriptor" than "logic bug." See `plugins/gcore-fastedge/CLAUDE.md` § "Logging — Stdout Only (Rust Hazard)" for the per-pattern fix. Skip this scan for JS/TS/AS — their SDKs route every log level to stdout, so the empty-capture hypothesis is genuinely about logic, not file descriptors.

---

## Step 8 — Summary

Print what was created, with language-aware paths.

**Rust example:**
```
Done:
  ✓ Created fastedge-test/app.test.mjs (3 test cases)
  ✓ Created fastedge-test/package.json with @gcoredev/fastedge-test installed
  ✓ Created fastedge-config.test.json at project root
  ✓ Updated .gitignore: fastedge-test/node_modules/

Next steps:
  cargo build --release --target wasm32-wasip1   # compile crate to WASM
  cd fastedge-test && npm test                   # run tests
  cd fastedge-test && npm run debug              # open visual debugger at http://localhost:5179
  (or) FastEdge: Debug Application               # VSCode command (uses bundled debugger)
```

**JS/TS example:**
```
Done:
  ✓ Created fastedge-test/app.test.mjs (3 test cases)
  ✓ Added @gcoredev/fastedge-test to root devDependencies
  ✓ Added npm scripts: test, debug
  ✓ Created fastedge-config.test.json at project root

Next steps:
  npm run build          # compile app to WASM
  npm test               # run tests
  npm run debug          # open visual debugger at http://localhost:5179
  (or) FastEdge: Debug Application  # VSCode command (uses bundled debugger)
```

---

## Migration from Legacy Layout

If you detect the legacy layout — root-level `tests/*.test.*` plus `@gcoredev/fastedge-test`
in the root `devDependencies` of a project that should be on the new layout — prompt:

> Detected legacy test layout (`tests/` at project root, `@gcoredev/fastedge-test` in root
> devDeps). The current layout puts the test file at `fastedge-test/app.test.mjs`.
>
> For **Rust apps**, this also moves Node artifacts (`package.json`, `node_modules/`) into
> `fastedge-test/` to keep the Cargo crate clean.
>
> Move the setup? [yes / no / skip-and-continue]

If **yes**, perform the move:

**Rust path:**
1. `mkdir -p fastedge-test`.
2. Move `tests/app.test.ts` (or `.mjs`) → `fastedge-test/app.test.mjs`. Strip TypeScript
   annotations if any; rename extension to `.mjs`.
3. Rewrite `wasmPath` in the test file to use the `import.meta.url`-relative form from Step 4.
4. Move `@gcoredev/fastedge-test` from root `devDependencies` to a new
   `fastedge-test/package.json` (Step 6 template).
5. Move root `node_modules/@gcoredev/fastedge-test` and reinstall fresh in `fastedge-test/`
   (`cd fastedge-test && npm install`).
6. Remove root `node_modules/` and `package-lock.json` **only if the root package.json had
   no other purpose** (no other devDeps, no `name`/`version`/build scripts). Otherwise leave
   them — the user has a Node project at root for other reasons.
7. Update root `.gitignore` to add `fastedge-test/node_modules/` if needed.

**JS/TS / AS path:**
1. `mkdir -p fastedge-test`.
2. Move `tests/app.test.ts` (or `.mjs`) → `fastedge-test/app.test.mjs`. Strip TypeScript
   annotations if any.
3. Rewrite `wasmPath` to the `import.meta.url`-relative form.
4. Update root `package.json` `scripts` to point at `fastedge-test/app.test.mjs` (Step 6).
5. Root `node_modules/` and `package.json` stay — they're the app's own Node setup.

If **no**, leave alone and proceed with whatever layout exists.

If **skip-and-continue**, treat the legacy layout as the working layout for this invocation
and follow legacy paths in subsequent steps. Do not write to `fastedge-test/` in this case.

---

## Advising on Local Debugging

Reference: `./reference/vscode-debugger.md`

When a user asks how to debug their app, test a specific request, or investigate unexpected
behaviour locally — read `./reference/vscode-debugger.md` before advising. It covers:
- Starting the visual debugger (VSCode extension commands vs. `npm run debug`)
- `fastedge-config.test.json` integration (auto-loaded on startup)
- What the debugger UI shows (logs, hook results, property accesses)
- Port conflict resolution
- Debugging specific request shapes (e.g. SAML ACS POSTs)

For Rust apps, the debugger CLI invocation includes `--project-dir ..` (see Step 6) so the
debugger anchors on the project root rather than the `fastedge-test/` sandbox.
