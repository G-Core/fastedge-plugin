---
name: debug
disable-model-invocation: false
argument-hint: "[project-dir] [--infer] [--smoke-check] [--no-modify-project | --modify-project]"
description: Generate local debug fixtures for FastEdge visual debugging scenarios. --infer derives scenarios from source; --smoke-check validates generated fixtures load cleanly; --no-modify-project / --modify-project gate package.json mutation (auto-detected from AGENTS.md/CLAUDE.md).
---

# FastEdge Debug (Codex)

Generate `fixtures/` scenario files for manual debugging with the FastEdge visual debugger.

This is independent from automated test generation (`/gcore-fastedge:test`).

## Modes

- **Manual** (default): agent reads source with developer and picks scenarios.
- **Inferred** (`--infer`): agent applies `plugins/gcore-fastedge-codex/skills/debug/reference/inference.md` to derive a structured scenario list automatically.

Both modes produce the same fixture format — only the selection differs.

`--smoke-check` is orthogonal — after writing fixtures, validate each loads cleanly in the headless `@gcoredev/fastedge-test` runner.

## Goal

Realistic scenario coverage from app behavior:

- always `happy-path.test.json`
- geo variants
- auth valid/invalid variants
- header/body variants
- missing env/secrets variants
- key error-path variants

## Step 1: Detect App Type

Choose fixture schema by app type.

CDN/proxy-wasm:

- `appType: "proxy-wasm"`
- use full `request.url`
- include `response` (mock origin) and optional `properties` (e.g. `request.country`, `request.host`, `client.ip`)

HTTP-wasm:

- `appType: "http-wasm"`
- use `request.path`
- no `response` field (app generates its own)
- no `properties` field (geo comes via headers like `geoip-country-code`)

## Step 2: Identify Scenarios

### Manual mode

Inspect entrypoint and major modules for:

- routes/hooks
- env/secrets access
- geo logic
- header/body branching
- error handling

### Inferred mode (`--infer`)

Read `plugins/gcore-fastedge-codex/skills/debug/reference/inference.md` and apply its patterns end-to-end. Produce the structured output (hooks, env, secrets, properties, scenarios, testSeeds).

Each `scenarios[]` entry maps to one fixture file. Use the entry's `name`, `description`, `request`, `properties`, and `env` directly. Do not deviate from inference output unless it violates the quality bar in `inference.md`.

## Step 3: Generate Fixtures

### Pre-flight: existing `.test.json` scan (REQUIRED — safety rule)

Before writing any fixture, scan `fixtures/` for existing `*.test.json` files. **Never silently overwrite** — hand-authored fixtures encode developer intent the skill cannot reconstruct from source. The canonical counterexample is a `missing-config.test.json` that deliberately omits `dotenv` to test the unset-env path; a re-generation would silently invert the scenario.

Bucket each intended write:

- File absent → write fresh.
- File present, byte-for-byte match → skip silently.
- File present, content differs → hold for prompt.
- Existing fixture with no matching inferred scenario → leave untouched, note in summary.

If anything is in the "content differs" bucket, print a diff summary and use `AskUserQuestion` with three options (single-select; `[a]` is the recommended default):

- **[a] Keep all existing fixtures, write only new scenarios** — preserves hand-authored content. Default.
- **[b] Replace all colliding fixtures with inferred drafts** — destroys hand-authored content.
- **[c] Cancel — exit without writing anything** — aborts the whole skill (including Step 4).

No "merge" option is offered — structural merge can silently break intent (see `missing-config` example).

### Pre-flight: `fixtures/.env`

If `fixtures/.env` exists, leave it untouched and print its current contents alongside what `--infer` would write so the developer can merge manually. If it does not exist, write fresh.

### Write fixtures

Create `fixtures/` if missing. Write only what the pre-flight policy decided to write. Use kebab-case filenames with `.test.json` suffix (required — debugger recognises this extension).

Examples: `happy-path.test.json`, `auth-missing.test.json`, `auth-expired.test.json`, `germany.test.json`, `post-json-body.test.json`, `missing-env.test.json`.

If env/secrets are used, write `fixtures/.env` with safe test values prefixed `FASTEDGE_VAR_ENV_*` / `FASTEDGE_VAR_SECRET_*`. Never include real secrets. Set `dotenv.enabled: true` and `dotenv.path: "."` in each fixture.

### Per-scenario `.env` subfolders (inferred mode)

When inference detects env values **must differ** between scenarios (e.g. `EXPERIMENT_NAME=A` vs `EXPERIMENT_NAME=B`), put each variant's overrides in `fixtures/<scenario>/.env` and set `dotenv.path: "./<scenario>"` in that fixture. Per-scenario `.env` is additive to shared `fixtures/.env` — only include override vars.

Manual mode rarely needs this — keep a single shared `.env` unless the developer asks for divergent values.

## Step 4: Debug Script

### Pre-flight: governance detection (REQUIRED)

Resolve policy in this order:

1. `--no-modify-project` passed → **off**.
2. `--modify-project` passed → **on** (overrides auto-detect).
3. Auto-detect: walk up from `<project-root>` toward filesystem root, reading `AGENTS.md` and `CLAUDE.md` at each level. Stop at the git repo root (`git -C <project-root> rev-parse --show-toplevel`) if inside a repo, else at `/`. Case-insensitively substring-match for `"never change code"`. Any match → **off**; no match anywhere → **on**.

Rationale for walking up: nested example layouts (e.g. `<sdk-repo>/examples/<example>/`) often have no `AGENTS.md` of their own — the governance rule lives at the SDK repo root.

Print the resolved policy verbosely so the user can audit and override. Include the matching file's path relative to project-root (e.g. `AGENTS.md`, `../AGENTS.md`, `../../CLAUDE.md`) and the walk-stop path (git root or `/`).

### Policy ON — mutate

Branches on host language. Detect: `Cargo.toml` at project root and **no** root `package.json` → Rust. Else JS/TS / AS.

**Rust** — target `fastedge-test/package.json`:

| State | Action |
|---|---|
| `fastedge-test/package.json` exists, no `"debug"` script | Add `"debug": "npx @gcoredev/fastedge-test --project-dir .."` |
| `fastedge-test/package.json` missing | Tell user: run `/gcore-fastedge:test` first to set up the sandbox. Do not silently scaffold from this skill. |
| `@gcoredev/fastedge-test` missing from `fastedge-test/package.json` devDeps | Recommend (do not auto-install): `cd fastedge-test && npm install --save-dev @gcoredev/fastedge-test@latest` |

**JS/TS / AssemblyScript** — target root `package.json`:

| State | Action |
|---|---|
| `package.json` exists, no `"debug"` script | Add `"debug": "npx @gcoredev/fastedge-test"` |
| `@gcoredev/fastedge-test` missing from root devDeps | Recommend: `npm install --save-dev @gcoredev/fastedge-test@latest` |

`--project-dir ..` (Rust only) anchors the debugger on the project root when run from `fastedge-test/`. Requires `@gcoredev/fastedge-test` 0.2.3+.

### Policy OFF — recommend only

Do **not** modify any `package.json`. Print language-specific manual instructions:

**Rust:**

```
mkdir -p fastedge-test
cd fastedge-test
npm init -y
npm install --save-dev @gcoredev/fastedge-test@latest

# then add to fastedge-test/package.json scripts:
#   "debug": "npx @gcoredev/fastedge-test --project-dir .."

# run:
#   cd fastedge-test && npm run debug
```

**JS/TS / AS:**

```
npm install --save-dev @gcoredev/fastedge-test@latest

# then add to package.json scripts:
#   "debug": "npx @gcoredev/fastedge-test"

# run:
#   npm run debug
```

Fixture generation in Step 3 proceeds regardless — governance gates only `package.json` mutation.

## Step 5: Smoke Check (`--smoke-check` only)

Skip unless `--smoke-check` was passed. For each generated `.test.json`, run a non-asserting load via the headless runner. Command depends on host language:

**Rust** (runner installed in `fastedge-test/node_modules/`):

```bash
cd fastedge-test
npx @gcoredev/fastedge-test --project-dir .. ../fixtures/<scenario>.test.json --no-assert
```

**JS/TS / AS** (runner in root `node_modules/`):

```bash
npx @gcoredev/fastedge-test ./fixtures/<scenario>.test.json --no-assert
```

If the installed runner doesn't support `--no-assert`, fall back to a minimal `defineTestSuite` wrapper asserting only "did not throw".

Report PASS/FAIL per fixture. On FAIL, surface the error and offer to regenerate that scenario. Smoke check verifies fixture **well-formedness only** — not behavioral correctness.

## Step 5.5: Rust Stderr Logging Pre-Check (Rust projects only)

**Skip entirely for TS/JS/AS.** Both `@gcoredev/fastedge-sdk-js` (via `console-override.cpp`) and `@gcoredev/proxy-wasm-sdk-as` (via `runtime.ts`'s `process.stdout.write`) route every logging call through stdout. Nothing to check.

**Rust only** (`Cargo.toml` at `<project-root>`). The visual debugger's log pane reads stdout — stderr writes are silently dropped, exactly the symptom a developer would mistake for "my hook isn't being called" or "my fixture is wrong." Warn before they open the debugger and waste time.

Procedure:

1. Glob `<project>/src/**/*.rs`.
2. Grep for: `\beprintln!`, `\beprint!`, `std::io::stderr\(\)`, `io::stderr\(\)`, `env_logger::(init|Builder::new)` without `Target::Stdout`, `with_writer\(\s*std::io::stderr`.
3. If matches found, print **before** Step 6's usage output:

   ```
   ⚠ Stderr-bound logging detected — debugger log pane will be empty for these calls.

     <file>:<line>  <matched_token>
         <full_line_text>
     [...up to 5; if more, append "(+N additional matches)"]

     FastEdge captures stdout only. The visual debugger's log pane reads stdout —
     stderr is silently dropped, producing the false impression that the hook
     didn't run, the fixture is wrong, or logging is broken.

     Fix before debugging:
       HTTP Rust: convert eprintln!/eprint! → println!/print!
       CDN Rust:  prefer log::* macros (log::info!, log::warn!, etc.) — already
                  wired to stdout via proxy-wasm's host ABI in the base skeleton
   ```

4. Do **not** auto-rewrite — debug operates on user-owned code; only scaffold's Rust Logging Self-Check auto-rewrites (it owns code it authored).

5. If no matches, proceed silently.

See `skills/scaffold/reference/http/base-rust.md` § Logging Convention and `skills/scaffold/reference/cdn/base-rust.md` § Logging Convention for the ruleset.

## Step 6: Usage Output

Return:

- fixture files created (with pre-flight summary: kept / written / skipped)
- scenario coverage summary
- command to run debugger (language-aware)

| Language | Run command |
|---|---|
| Rust | `cd fastedge-test && npm run debug` |
| JS/TS / AS | `npm run debug` |

## Worked Examples

These anchor the pre-flight fixture safety prompt and the governance detection gate. Mirror the structure when handling real requests.

### Example 1 — `--infer` on a fresh project

**User prompt**: "generate debug fixtures for product-cache --infer"

**Behavior**:

- App type detected: HTTP-WASM (TypeScript with `fastedge-build`).
- Step 2 (Inferred mode): apply `inference.md` end-to-end → 5 scenarios identified (`happy-path`, `germany`, `missing-env`, `auth-missing`, `post-json-body`).
- Step 3 pre-flight: `fixtures/` doesn't exist → no collision. `fixtures/.env` doesn't exist → write fresh.
- Write 5 `.test.json` files with HTTP-WASM schema (`request.path`, no `properties`, no `response`).
- Write `fixtures/.env` with `FASTEDGE_VAR_ENV_REGION=`, `FASTEDGE_VAR_SECRET_STRIPE_KEY=` (safe placeholders, never real values).
- Step 4 governance: no `--no-modify-project` or `--modify-project`. Auto-detect — walk from project root, read `AGENTS.md` and `CLAUDE.md`. None found → policy ON. Add `debug` script to `package.json`.

**Completion output**:

```
Fixtures generated for product-cache  [HTTP / inferred]

  Created:
    fixtures/happy-path.test.json
    fixtures/germany.test.json
    fixtures/missing-env.test.json
    fixtures/auth-missing.test.json
    fixtures/post-json-body.test.json
    fixtures/.env  (placeholders only — fill in real values before debugging)

  Governance: policy ON (no governance file found, walked to git root)
  Updated:    package.json (added "debug" script)

Next: npm run debug
```

### Example 2 — Pre-flight collision with existing fixtures

**User prompt**: "regenerate fixtures for product-cache --infer"

**Behavior**:

- Step 3 pre-flight scans `fixtures/`: 4 existing `.test.json` files. Inference produces 5 scenarios. Bucket:
  - `happy-path.test.json` → byte-for-byte match → skip silently
  - `germany.test.json` → content differs → hold for prompt
  - `missing-config.test.json` → no matching inferred scenario (developer-authored — tests deliberately-unset env) → leave untouched, note in summary
  - `post-json-body.test.json` → content differs → hold for prompt
  - `auth-missing.test.json` (new) → write fresh
- 2 fixtures in "content differs" bucket. Print diff summary. Prompt with three options. Default `[a]` (keep existing).

**Completion output (before prompt)**:

```
Pre-flight: existing fixtures detected.

  Skip (identical):           happy-path.test.json
  Differs (would change):     germany.test.json, post-json-body.test.json
  Hand-authored (untouched):  missing-config.test.json
  New (would write):          auth-missing.test.json

[a] Keep all existing fixtures, write only new scenarios (default)
[b] Replace all colliding fixtures with inferred drafts (destroys hand-authored content)
[c] Cancel — exit without writing anything
```

User picks `[a]` → write only `auth-missing.test.json`, leave the rest.

### Example 3 — Degraded mode: governance gate blocks package.json mutation

**User prompt**: "generate debug fixtures for examples/jwt-filter (this is inside an SDK example tree)"

**Behavior**:

- Project root: `<sdk-repo>/examples/jwt-filter/`. No `AGENTS.md` or `CLAUDE.md` at this level.
- Step 4 governance auto-detect walks up: `../AGENTS.md` is absent, `../../AGENTS.md` (at SDK repo root) contains the substring `"never change code"` → policy **OFF**.
- Fixture writing in Step 3 proceeds normally (governance gates only `package.json` mutation, not fixture writes).
- Step 4: print recommendation only, do NOT modify `package.json`.

**Completion output**:

```
Fixtures generated for jwt-filter  [CDN / inferred]

  Created:  fixtures/happy-path.test.json
            fixtures/auth-missing.test.json
            fixtures/auth-expired.test.json
            fixtures/.env

  Governance: policy OFF  (matched "never change code" in ../../AGENTS.md)
  Skipped:    package.json mutation. Add the debug script manually:

      "scripts": {
        "debug": "npx @gcoredev/fastedge-test"
      }

  And install the runner if missing:
      npm install --save-dev @gcoredev/fastedge-test

  Override with --modify-project if you want the skill to write the script anyway.

Next: npm run debug
```

## References

- Inference patterns (`--infer`): `plugins/gcore-fastedge-codex/skills/debug/reference/inference.md`
- Visual debugger details: `plugins/gcore-fastedge-codex/skills/test/reference/vscode-debugger.md`
- Indexed local docs: `plugins/gcore-fastedge-codex/docs-index.json`
- Test config schema: search "test-config" under `plugins/gcore-fastedge-codex/skills/test/reference/`
