---
name: test
disable-model-invocation: false
argument-hint: "[project-dir]"
description: Generate or run local FastEdge WASM tests using @gcoredev/fastedge-test
---

# FastEdge Test (Codex)

Write and run automated local tests before deployment.

## TDD Gate

Follow this sequence:

1. write/generate tests
2. build wasm
3. run tests
4. fix failures
5. deploy

If deploy is requested without test context, recommend running this skill first.

The visual debugger (`npm run debug`) is the interactive complement to automated tests — see `plugins/gcore-fastedge-codex/skills/test/reference/vscode-debugger.md`.

## Project Layout (Option B)

The test harness always lives under `fastedge-test/` at the project root. The test file path is the same regardless of language; what surrounds it differs.

```
<project-root>/
├── fastedge-config.test.json     ← app-level (VSCode debugger + live-test consume it)
├── fixtures/                     ← app-level (debug + live-test scenarios)
└── fastedge-test/
    └── app.test.mjs              ← always here
```

| Host language | Node install location | Run command |
|---|---|---|
| Rust            | `fastedge-test/package.json` + `node_modules/` (sandboxed) | `cd fastedge-test && npm test` |
| JS/TS (HTTP)    | root `package.json` (existing project) | `npm test` from root |
| AssemblyScript  | root `package.json` (existing project) | `npm test` from root |

Test file extension is `.mjs` (plain ESM) for all languages — no TypeScript runtime needed.

## Mode Detection

Infer mode from user phrasing:

- Generate: create full test suite from source behavior
- Scaffold: create starter test file with TODOs
- Run: execute existing tests and report failures

If ambiguous between scaffold and generate, ask exactly:

> Would you like me to generate tests from your source code, or just scaffold a starter file?

## Step 1 — Project Type Detection

Two axes. **Language** drives where the Node install lives; **app type** drives the test patterns.

**Language**:

| Marker file at project root | Language |
|---|---|
| `Cargo.toml` and **no** `package.json` | rust |
| `package.json` with `src/index.{ts,js,mjs,cjs}` | js-ts |
| `asconfig.json` | as |

If none match, ask the user to confirm.

**App type** (from `componentize.config.js`, build scripts, or imports):

- **CDN / proxy-wasm**: hooks-based (`onRequestHeaders`, etc.) — use `runFlow` + `assertFinalStatus`/`assertFinalHeader`
- **HTTP-WASM**: standard request/response — use `runHttpRequest(runner, { path, method, headers })`

See `plugins/gcore-fastedge-codex/skills/test/reference/test-framework.md` for the patterns.

## Step 2 — Pre-flight Detection (Three Outcomes)

Before writing any test files, check for:

- **New layout**: `fastedge-test/app.test.mjs` (plus `fastedge-test/package.json` on Rust).
- **Legacy layout**: root `tests/*.test.*` plus `@gcoredev/fastedge-test` in root devDeps.
- `fastedge-config.test.json` at the project root.

Apply this decision logic:

| State | Action |
|-------|--------|
| New layout present (with or without `fastedge-config.test.json`) | Work with it. Add new cases to the existing `fastedge-test/app.test.mjs`. Do not overwrite. |
| Legacy layout present | Prompt for migration. See `## Migration from Legacy Layout` below. |
| Only `fastedge-config.test.json` exists | Full scaffold path (Steps 3–6), reusing its `wasm.path` and baseline request. |
| Nothing exists | Full scaffold path. |

## Step 3 — Install Check + Set Up (HARD GATE)

Branch on language. Until `@gcoredev/fastedge-test` is installed in the right place, **do not write tests, do not create configs, do not run anything.**

**Rust**:

```bash
mkdir -p fastedge-test
cd fastedge-test
npm init -y                       # only if package.json doesn't exist yet
npm install --save-dev @gcoredev/fastedge-test@latest
```

Append to project-root `.gitignore` if not already covered:

```
fastedge-test/node_modules/
```

**JS/TS / AssemblyScript**:

Check root `package.json` `devDependencies` for `@gcoredev/fastedge-test`. If missing:

```bash
npm install --save-dev @gcoredev/fastedge-test@latest
```

The `@latest` tag ensures ESM-bundle and binary-discovery fixes from 0.2.3+ are picked up.

## Step 4 — Generate or Scaffold Tests

Always write `fastedge-test/app.test.mjs`. Resolve `wasmPath` via `import.meta.url` so it works regardless of CWD.

Reference: `plugins/gcore-fastedge-codex/skills/test/reference/test-framework.md` for full templates.

### Pre-generate: Rust Stderr Logging Scan (Rust projects only)

**Skip entirely for JS/TS and AssemblyScript.** Their SDKs route every logging API to stdout by construction (`console-override.cpp` → `fprintf(stdout, ...)`; `runtime.ts` → `process.stdout.write`). Log-based assertions on those projects depend only on logic.

**Rust only.** FastEdge captures stdout only — stderr writes are silently dropped. A test asserting on a log substring emitted via `eprintln!` will fail at run-time with no signal distinguishing "wrong logic" from "wrong file descriptor." Worse: local capture may differ from the edge, so a test could PASS locally while production drops the same lines invisibly.

Procedure:

1. Glob `<project>/src/**/*.rs`.
2. Grep for: `\beprintln!`, `\beprint!`, `std::io::stderr\(\)`, `io::stderr\(\)`, `env_logger::(init|Builder::new)` without `Target::Stdout`, `with_writer\(\s*std::io::stderr`.
3. If matches found, halt Generate mode and ask the user:

   ```
   ⚠ Stderr-bound logging detected in Rust source — refusing to generate
     log-based test assertions until resolved.

     <file>:<line>  <matched_token>
         <full_line_text>
     [...up to 5; if more, append "(+N additional matches)"]

     FastEdge captures stdout only. Tests asserting on these messages will
     fail at run-time because the log lines never reach the platform log
     stream.

     [1] Fix source (recommended) — convert to println!/print! (HTTP Rust)
         or log::info!/warn!/error! (CDN Rust via proxy-wasm), then re-run.
     [2] Continue without log assertions — generate status/headers/body
         coverage only; note skipped lines in app.test.mjs.
     [3] Cancel.
   ```

4. Action by choice:
   - `[1]` → exit with "Re-run /gcore-fastedge:test once source is fixed." Do **not** auto-rewrite — user-owned source belongs to the user; only scaffold's Rust Logging Self-Check auto-rewrites because it authored the code.
   - `[2]` → proceed to Generate Mode but omit any assertion derived from a flagged line. Add a comment above the suite definition recording skipped lines, e.g. `// Note: stderr-bound logging at src/lib.rs:7 — log-based assertions skipped.`
   - `[3]` → exit without writing.

5. If no matches, proceed silently. The absence of a warning is the signal.

See `skills/scaffold/reference/http/base-rust.md` § Logging Convention and `skills/scaffold/reference/cdn/base-rust.md` § Logging Convention for the ruleset.

### Generate Mode

1. Read app entrypoint (`src/index.ts`, `src/main.rs`, or `assembly/index.ts`).
2. Identify all routes/handlers/hooks.
3. Write `fastedge-test/app.test.mjs` with one meaningful test per route/hook/branch.
4. Prefer deterministic assertions and stable fixtures.

**HTTP-WASM template:**

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
  wasmPath: resolve(here, '../target/wasm32-wasip1/release/<crate>.wasm'),  // Rust
  // wasmPath: resolve(here, '../<app-name>.wasm'),                          // JS/TS
  tests: [
    {
      name: 'GET / returns 200',
      async run(runner) {
        const response = await runHttpRequest(runner, { path: '/', method: 'GET', headers: {} });
        assertHttpStatus(response, 200);
      },
    },
  ],
}));
```

**CDN / proxy-wasm template:**

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
  wasmPath: resolve(here, '../build/release.wasm'),                          // AssemblyScript
  // wasmPath: resolve(here, '../target/wasm32-wasip1/release/<crate>.wasm'), // Rust CDN
  tests: [
    {
      name: 'GET / passes through with X-Custom header',
      async run(runner) {
        const result = await runFlow(runner, { url: 'https://example.com/', method: 'GET' });
        assertFinalStatus(result, 200);
        assertFinalHeader(result, 'x-custom', 'expected');
      },
    },
  ],
}));
```

### Scaffold Mode

Same shape but a single TODO case — see `plugins/gcore-fastedge-codex/skills/test/reference/test-framework.md`.

## Step 5 — Create/Update test-config.json (at project root)

`fastedge-config.test.json` lives at the project root regardless of language — it's app-level config consumed by the VSCode debugger and the live-test skill.

Reference: `plugins/gcore-fastedge-codex/skills/test/reference/test-config.md`.

Always include:

- `wasm.path` (build output)
- `request` (baseline method/url/headers/body)
- `logLevel`
- `envVars` / `secrets` placeholders (see Step 5.5)
- `properties` (CDN apps only — request.country, request.city, etc.)

**Omit `properties` for HTTP-WASM apps (not applicable).**

`$schema` path differs by language because it points into wherever `@gcoredev/fastedge-test` is installed:

| Language | `$schema` value |
|---|---|
| Rust | `./fastedge-test/node_modules/@gcoredev/fastedge-test/schemas/test-config.schema.json` |
| JS/TS / AS | `./node_modules/@gcoredev/fastedge-test/schemas/test-config.schema.json` |

## Step 5.5 — Secrets Sensitivity Triage

If source code uses `getEnv(` or `getSecret(`, identify each key and triage by sensitivity. These are **app-level** concerns and live at the project root, not inside `fastedge-test/`.

**Sensitivity detection:** a value is sensitive if its name contains `secret`, `token`, `key`, `cert`, `password`, `credential`, or the user flagged it. Default to sensitive if uncertain.

| Sensitivity | Location |
|-------------|----------|
| Non-sensitive (entity IDs, URLs, feature flags) | `fastedge-config.test.json` `envVars` / `secrets` with placeholders |
| Sensitive (API keys, tokens, certs, passwords) | `.env` at project root (gitignored) + `runnerConfig: { dotenvEnabled: true }` in the test suite |

For the sensitive path:

1. Add `runnerConfig: { dotenvEnabled: true }` to the `defineTestSuite` call in `fastedge-test/app.test.mjs`.
2. Create `.env.example` at project root (committed) with placeholders using `FASTEDGE_VAR_SECRET_` / `FASTEDGE_VAR_ENV_` prefixes.
3. Ensure `.env` and `.env.secrets` are in `.gitignore` — tell the user if not already present.
4. Never commit real credentials/certs.

**SAML-specific rule:** for SAML apps, the IdP certificate and any signing keys must go in `.env` via `FASTEDGE_VAR_SECRET_` prefix — never commit real certs to `fastedge-config.test.json`.

See `plugins/gcore-fastedge-codex/skills/test/reference/dotenv.md`.

## Step 6 — npm Scripts (Preserve Existing)

Scripts live where the Node install lives.

**Rust** — write `fastedge-test/package.json`:

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

`--project-dir ..` anchors the debugger on the project root (where `fastedge-config.test.json` and `fixtures/` live). Requires `@gcoredev/fastedge-test` 0.2.3+.

**JS/TS / AssemblyScript** — root `package.json` scripts:

```json
{
  "scripts": {
    "test":  "node fastedge-test/app.test.mjs",
    "debug": "npx @gcoredev/fastedge-test"
  }
}
```

No `--project-dir` needed; CWD is already the project root.

**Do not overwrite existing scripts with different values — only add missing ones.** If a script exists with a different command, leave it alone and tell the user.

## Step 7 — Run Tests

Branch on language for the run command:

| Language | Command |
|---|---|
| Rust | `cd fastedge-test && npm test` |
| JS/TS / AS | `npm test` (from root) |

1. Execute the appropriate command.
2. Report pass/fail counts and failed case names.
3. For each failure, map to a concrete root-cause pointer:

| Error pattern | Root-cause pointer |
|---------------|--------------------|
| `WASM not found` / missing file | Build first. Rust: `cargo build --release --target wasm32-wasip1`. JS/TS: `npm run build`. AS: `npm run asbuild:release`. |
| `assertFinalStatus` mismatch | Inspect route logic / dispatch table |
| `Expected request header ... to be set` | Check the hook implementation that should add it |
| `assertFinalHeader` mismatch | Check the response-phase hook |
| Import / module resolution errors | Re-run Step 3 install check |
| Log assertion empty / "expected log to contain X" (**Rust only**) | Run the Pre-generate Rust Stderr Logging Scan (Step 4) once for the run (cache result). Empty log captures on Rust apps are almost always "wrong file descriptor" — `eprintln!` and stderr-bound logging are silently dropped. Convert to `println!`/`print!` (HTTP) or `log::*` (CDN via proxy-wasm). Skip this branch for JS/TS/AS — their SDKs route all log levels to stdout. |

4. Suggest the next debug action (e.g. open visual debugger for the failing request shape).

## Migration from Legacy Layout

When Step 2 detects legacy layout (root `tests/` + root `@gcoredev/fastedge-test`), prompt:

> Detected legacy test layout (`tests/` at project root, `@gcoredev/fastedge-test` in root devDeps). The current layout puts the test file at `fastedge-test/app.test.mjs`.
>
> For **Rust apps**, this also moves Node artifacts (`package.json`, `node_modules/`) into `fastedge-test/` to keep the Cargo crate clean.
>
> Move the setup? [yes / no / skip-and-continue]

**Yes — Rust path:**

1. `mkdir -p fastedge-test`
2. Move `tests/app.test.{ts,mjs}` → `fastedge-test/app.test.mjs`. Strip TypeScript annotations if any.
3. Rewrite `wasmPath` to the `import.meta.url`-relative form from Step 4.
4. Move `@gcoredev/fastedge-test` devDep from root → new `fastedge-test/package.json` (Step 6 template).
5. `cd fastedge-test && npm install`.
6. Remove root `node_modules/` and `package-lock.json` **only if root `package.json` had no other purpose** (no other devDeps, no `name`/`version`/build scripts). Otherwise leave them.
7. Add `fastedge-test/node_modules/` to project-root `.gitignore`.

**Yes — JS/TS / AS path:**

1. `mkdir -p fastedge-test`
2. Move `tests/app.test.{ts,mjs}` → `fastedge-test/app.test.mjs`. Strip TypeScript annotations.
3. Rewrite `wasmPath` to the `import.meta.url`-relative form.
4. Update root `package.json` scripts to point at `fastedge-test/app.test.mjs` (Step 6).
5. Root `node_modules/` and `package.json` stay — they're the app's own Node setup.

**No / Skip-and-continue:** treat the legacy layout as the working layout for this invocation. Do not write to `fastedge-test/` in this case.

## Worked Examples

These anchor expected behavior, the three-outcome pre-flight, and the hard-gate install check.

### Example 1 — Generate tests from source (HTTP Rust app)

**User prompt**: "set up tests for hello-world"

**Behavior**:

- Mode: ambiguous → ask. User picks generate.
- Step 1: detect language = rust (Cargo.toml, no package.json); app type = HTTP-WASM.
- Step 2: pre-flight — nothing exists → full scaffold path.
- Step 3: install (HARD GATE) — `mkdir fastedge-test && cd fastedge-test && npm init -y && npm install --save-dev @gcoredev/fastedge-test@latest`. Append `fastedge-test/node_modules/` to root `.gitignore`.
- Step 4 (Generate): read `src/main.rs`, identify routes, write `fastedge-test/app.test.mjs` with `import.meta.url`-anchored `wasmPath` pointing at `../target/wasm32-wasip1/release/hello_world.wasm`.
- Step 5: write `fastedge-config.test.json` at project root with `$schema` pointing at `./fastedge-test/node_modules/...`. Omit `properties` (HTTP-WASM).
- Step 5.5: no `getEnv`/`getSecret` calls in source → skip.
- Step 6: write `fastedge-test/package.json` with the three scripts and `--project-dir ..` on debug/smoke-check.
- Step 7: skip in generate mode.

**Completion output**:

```
Tests generated for hello-world  [HTTP-WASM / Rust]

  Created:  fastedge-test/app.test.mjs           (3 cases: 1 per route)
  Created:  fastedge-test/package.json           (with test, debug)
  Created:  fastedge-test/package-lock.json      (npm install ran)
  Created:  fastedge-config.test.json            (root, $schema → fastedge-test/node_modules/...)
  Updated:  .gitignore                           (added fastedge-test/node_modules/)

Next: cd fastedge-test && npm test
```

### Example 2 — Generate tests from source (HTTP TS app)

**User prompt**: "set up tests for product-cache"

**Behavior**:

- Step 1: language = js-ts (package.json present with src/index.ts); app type = HTTP-WASM.
- Step 2: nothing in `fastedge-test/`, no legacy `tests/` either → full scaffold path.
- Step 3: install check — `@gcoredev/fastedge-test` missing from root devDeps → `npm install --save-dev @gcoredev/fastedge-test@latest` at root.
- Step 4 (Generate): write `fastedge-test/app.test.mjs` with `wasmPath: resolve(here, '../product-cache.wasm')`.
- Step 5: write `fastedge-config.test.json` at root with `$schema` pointing at `./node_modules/...`.
- Step 5.5: source uses `getEnv("REGION")` (non-sensitive) and `getSecret("STRIPE_KEY")` (sensitive). Region → `fastedge-config.test.json` envVars. Stripe key → `.env` + `runnerConfig: { dotenvEnabled: true }`. Verify `.env` is in `.gitignore`.
- Step 6: add missing scripts to root `package.json`. `test` already exists with a different command → leave it, tell user.

**Completion output**:

```
Tests generated for product-cache  [HTTP-WASM / TypeScript]

  Created:  fastedge-test/app.test.mjs           (4 cases: 1 per route)
  Updated:  package.json                         (added debug script, devDep)
  Created:  fastedge-config.test.json            (envVars: REGION)
  Created:  .env, .env.example                   (sensitive: STRIPE_KEY)
  Updated:  .gitignore                           (.env, .env.secrets)
  Skipped:  test script (already defined — left untouched)

Next: npm test
```

### Example 3 — Run existing tests (with failures)

**User prompt**: "run my fastedge tests"

**Behavior**:

- Mode: Run. Step 2 detects new layout (`fastedge-test/app.test.mjs` + `fastedge-test/package.json`) → work with them. Language = rust (Cargo.toml present).
- Install check passes.
- Step 7: execute `cd fastedge-test && npm test`. 2 pass, 1 fail.
- Map failures: `assertFinalStatus expected 200, got 404` on `GET /products/:id` test → route logic / dispatch table.

**Completion output**:

```
Tests run for product-cache

  ✓ GET /                  (returns landing)
  ✓ GET /products          (returns list)
  ✗ GET /products/42       expected status 200, got 404

Root-cause pointer: assertFinalStatus mismatch → inspect route logic
  Likely culprit: src/routes/products.rs dispatch table (check :id matcher)

Next: open visual debugger to step through the request shape

  cd fastedge-test && npm run debug
```

### Example 4 — Degraded mode: install gate

**User prompt**: "set up tests for product-cache"

**Behavior**: Step 1 language = rust. Step 2 nothing exists. Step 3 install (HARD GATE) — the user has disabled npm or refused install. **HARD GATE** — do not write tests, do not create configs, do not proceed.

**Completion output**:

```
✗ @gcoredev/fastedge-test could not be installed in fastedge-test/.

  mkdir -p fastedge-test
  cd fastedge-test
  npm init -y
  npm install --save-dev @gcoredev/fastedge-test@latest

Then re-run `/gcore-fastedge:test product-cache`.

No files written. (Test scaffolding requires the runner to be present.)
```

### Example 5 — Migration prompt (legacy layout)

**User prompt**: "set up tests for hello-world"

**Behavior**:

- Step 1: language = rust.
- Step 2: pre-flight finds legacy layout — root `tests/app.test.ts` + `@gcoredev/fastedge-test` in root `package.json` devDeps. Trigger migration prompt.
- User picks `yes` → execute the Rust migration path: move file, rewrite wasmPath, relocate devDep into `fastedge-test/package.json`, clean root, update `.gitignore`.

**Completion output**:

```
Migrated hello-world to the fastedge-test/ layout  [Rust]

  Moved:    tests/app.test.ts → fastedge-test/app.test.mjs   (TS annotations stripped)
  Rewrote:  wasmPath to import.meta.url-relative form
  Created:  fastedge-test/package.json                       (test, debug, smoke-check scripts)
  Removed:  root node_modules/, root package.json, root package-lock.json
  Updated:  .gitignore                                       (added fastedge-test/node_modules/)

Next: cd fastedge-test && npm test
```

## References

- `plugins/gcore-fastedge-codex/docs-index.json`
- `plugins/gcore-fastedge-codex/skills/test/reference/test-framework.md`
- `plugins/gcore-fastedge-codex/skills/test/reference/test-config.md`
- `plugins/gcore-fastedge-codex/skills/test/reference/dotenv.md`
- `plugins/gcore-fastedge-codex/skills/test/reference/vscode-debugger.md`
