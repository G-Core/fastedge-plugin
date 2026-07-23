---
name: live-test
disable-model-invocation: true
argument-hint: "[project-dir] [--infer] [--cleanup] [--from <dir>] [--no-env-sync] [--auto-apply]"
description: Build, deploy, and verify a FastEdge app against real edge traffic. Runs scenario fixtures against the deployed app and reports pass/fail on observable HTTP responses and edge logs.
---

# FastEdge Live-Test (Codex)

Verify a FastEdge app on the live edge. After local tests and fixtures pass, builds + deploys, wires the app to a test target (an HTTP app URL or a CDN rule on a preconfigured resource), and runs each fixture scenario against the real deployment with HTTP-level assertions.

This is **not** a substitute for `/gcore-fastedge:test`. Local tests run in-process against the WASM module with rich hook-internal assertions. Live-test runs HTTP requests against a deployed app and asserts only what's observable from outside.

## When to Use

| You have... | Run... |
|---|---|
| Working tests only (`tests/*.test.ts`) | `/gcore-fastedge:debug --infer` first to materialize fixtures, then `/gcore-fastedge:live-test --infer` |
| Working fixtures, no `.live.json` siblings | `/gcore-fastedge:live-test --infer` (auto-author drafts from source) — or run without `--infer` for print-only mode |
| Working fixtures + hand-authored `.live.json` siblings | `/gcore-fastedge:live-test` directly |
| Neither fixtures nor tests | Stop. Author tests or fixtures first. |

## Flags

- `--infer` — auto-author missing `.live.json` siblings from source inference (see Step 3.5).
- `--cleanup` — disable the CDN test rule after the run (CDN only).
- `--from <dir>` — point env-sync at a variant subdir instead of `fixtures/`. Passed through to manage.
- `--no-env-sync` — skip env-sync entirely.
- `--auto-apply` — passed through to manage sync-env for destructive env diffs.

## MCP Execution

Live-test is mostly orchestration of existing skills + a few live-test-specific workflows:

| Workflow | Purpose |
|---|---|
| `enable-app-http` | PATCH app `debug:true`, return URL + `debug_until` (HTTP apps) |
| `attach-app-to-cdn-rule-create` | PATCH app `debug:true` + POST new CDN rule wiring app at `/livetest-<name>/` (CDN, first run) |
| `attach-app-to-cdn-rule-update` | PATCH app `debug:true` + PATCH existing CDN rule (CDN, re-runs) |
| `gcore_api` | Per-scenario log query: `GET /fastedge/v1/apps/{id}/logs?request_id=<traceparent>` |
| `update-env-vars-app` | Delegated via `/gcore-fastedge:manage sync-env` (Step 4.5) |

If MCP isn't configured, halt and follow the setup path documented in `/gcore-fastedge:deploy`. Do not silently fall back to direct API calls.

## Step 1 — Detect App Type

| Signal | App Type |
|---|---|
| `Cargo.toml` with `proxy-wasm` dep, or `asconfig.json` present | CDN (proxy-wasm) |
| `package.json` with `fastedge-build` in build script | HTTP (http-wasm) |
| `Cargo.toml` with `fastedge` or `wstd` dep | HTTP (http-wasm) |

If ambiguous, ask before continuing. Type determines which MCP workflow to invoke and how to construct test URLs.

## Step 2 — Read Live-Test Config

Look for `fixtures/livetest.config.json`. Schema:

```json
{
  "cdnResourceId": 2296532,
  "rulePathPrefix": "/livetest-"
}
```

- `cdnResourceId` — required for CDN apps. Preconfigured resource that hosts test rules (don't create on the fly — CDN resources take ~20 min to propagate).
- `rulePathPrefix` — defaults to `/livetest-`. Test rules are created at `<prefix><app-name>/`.

For HTTP apps, the file may be absent. If missing on a CDN run, prompt for the resource ID and write the file.

### Gitignore Guard

Before relying on `fixtures/livetest.config.json`, check `.gitignore`. If the file (or any matching pattern) is ignored, warn the user — the config won't travel with the repo and CI/other developers won't see your CDN resource setting. Ask whether to fix.

## Step 3 — Pre-Flight (Tests + Fixtures)

1. `fixtures/*.test.json` present? If none, abort: "No fixtures found. Run `/gcore-fastedge:debug --infer` first."
2. `*.live.json` siblings? Count them:
   - `--infer` passed → Step 3.5 auto-authors missing siblings.
   - `--infer` not passed, zero siblings → warn: "No `.live.json` siblings — print-only mode (no pass/fail). Pass `--infer` or hand-author `expected` blocks."
   - `--infer` not passed, some siblings → continue. Print-only applies only to fixtures missing a sibling.
3. Run local tests if a Node test harness exists. Branch on layout:

   | State | Command |
   |---|---|
   | New layout, Rust (`fastedge-test/app.test.mjs` + no root `package.json`) | `cd fastedge-test && npm test` |
   | New layout, JS/TS / AS (`fastedge-test/app.test.mjs` + root `package.json`) | `npm test` from project root |
   | Legacy layout (root `tests/*.test.*`) | `npm test` from project root |
   | No harness | Skip — no local-test gate to apply |

   If tests fail, abort — don't deploy broken code to verify it.

## Step 3.5 — Infer `.live.json` Siblings (`--infer` only)

Skip unless `--infer` was passed.

1. Apply inference per `plugins/gcore-fastedge-codex/skills/debug/reference/inference.md`. Read **all sections** including **Step 9: Assertion Inference**.
2. For each `<basename>.test.json` lacking a `<basename>.live.json` sibling:
   - Match the fixture to a scenario in the inference output by basename ↔ `scenarios[].name`.
   - Take that scenario's `expected` block.
   - If no matching scenario (developer authored a fixture not produced by inference), fall back to the **intersection** assertion — only `logs` reached on every branch. Surface a NOTE.
   - Write `<basename>.live.json` with shape `{ "expected": <block> }`.
3. Print the list of inferred files with a one-line preview. Tell the developer these are **drafts derived from source** — review before relying on the pass/fail signal.

Inferred assertions are filter-derivable only:
- `logs` from `log(...)` calls
- `status` / `body` from `sendLocalResponse` / short-circuit calls
- `headers` / `noHeaders` from response header mutations

Origin-derivable assertions (`status` when traffic passes through, `contentType`, `json` shape, `noLogs`) are **not** inferred. The developer adds those manually.

## Step 4 — Build & Deploy

Delegate to `/gcore-fastedge:deploy`. Pass:

- The project directory.
- `--description "⚡live-test - <text>"` where `<text>` is the project's `package.json` `description` (or `Cargo.toml` `package.description`), falling back to the original project folder basename. Truncate to 250 chars. The leading `⚡` is U+26A1 lightning-bolt — preserve exactly.
- `--no-magic-comments` — **always**. Live-test must not modify the target project's source files (governance rule). The user can run deploy directly without this flag for their own iteration cycle.

The `⚡live-test - ` prefix flags the app in the FastEdge UI as a live-test app. Deploy applies the description on CREATE only.

After deploy completes, capture `app_id` and `app_name` from the deploy result (the name may differ from the project folder if deploy applied a kebab transform — always read from the result, not re-derived).

If deploy fails, abort.

## Step 4.5 — Sync Env to Deployed App

Unless `--no-env-sync` was passed, sync `.env*` from the source dir to the deployed app **before** wiring the test target. Without this, env-driven apps see an empty env on the edge and every config-dependent scenario FAILs by default.

### Resolve `<source-dir>`

- `--from <dir>` was passed → use that.
- Otherwise → `<project>/fixtures` (debug-skill convention).

### Skip cases

- `--no-env-sync` → print `Env-sync skipped` and proceed.
- `<source-dir>` doesn't exist OR no `.env*` files → print `No .env* in <source-dir>, skipping env-sync` and proceed.

### Delegate to manage

Invoke `/gcore-fastedge:manage sync-env <app_id> --from <source-dir>` and pass through `--auto-apply` if live-test received it. Manage owns parsing, secret resolution, diff, and the three-tier confirmation policy (additive auto, destructive prompt, default-no-removal). Surface manage's output in the live-test progress stream.

On manage's `[c] Cancel sync`, abort the live-test run.

### Per-variant env workflow

The deployed app has exactly one env set, and Step 6 reuses that one app across every scenario. Per-scenario `dotenv.path` overrides in `*.test.json` are debugger-only — they do NOT influence live-test.

To exercise scenarios that need different env values, re-run live-test with `--from`:

```
/gcore-fastedge:live-test --from fixtures/germany/
/gcore-fastedge:live-test --from fixtures/us/
```

Replacement semantics — each variant's `.env` is the complete env truth for that run (no layering on top of `fixtures/.env`).

## Step 5 — Wire the Test Target

### HTTP App

Call `enable-app-http` with `app_id`. Capture:
- `$app.url` — public test URL
- `$app.debug_until` — RFC3339 timestamp (debug auto-disables 30 min after PATCH)

Test base URL = `$app.url`. No CDN involved.

### CDN App

1. List rules on the resource: `GET /cdn/resources/{cdnResourceId}/rules`.
2. Look for a rule at path `<rulePathPrefix><app-name>/`. Match on the `rule` field.
3. Construct `fastedge_options` — enable on the hooks the app implements (use `inference.md` to determine which phases). Default policy per hook:

   ```
   { "enabled": true, "app_id": <id>, "interrupt_on_error": true,
     "execute_on_edge": true, "execute_on_shield": false }
   ```

   The CDN supports 4 phases: `on_request_headers`, `on_request_body`, `on_response_headers`, `on_response_body`. `interrupt_on_error: true` is right for live-test — surface failures, don't swallow.

4. Pick the workflow:
   - Rule found → `attach-app-to-cdn-rule-update` with `rule_id`, `app_id`, `resource_id`, `fastedge_options`.
   - Rule not found → `attach-app-to-cdn-rule-create` with `rule_name` (e.g. `livetest-helloWorld`), `rule_path` (e.g. `/livetest-helloWorld/`), `app_id`, `resource_id`, `fastedge_options`.

5. Test base URL = `https://<resource_cname>/<rulePathPrefix><app-name>/`. Get `cname` from `GET /cdn/resources/{id}`.

Rules persist after the run unless `--cleanup`.

## Step 5.5 — Propagation Warmup

Confirm the filter is running on the rule path before the sweep — running prematurely produces false-FAILs.

### HTTP App

Skip. `enable-app-http` toggles debug on an already-deployed URL; no rule propagation phase. Proceed to Step 6.

### CDN App, update path

Brief warmup: wait 5s, issue one warmup `GET <test_base_url>`, discard response. If 502/timeout, retry once after 5s. Proceed.

### CDN App, fresh-attach path

Empirical propagation: 60–120s for new rules. Issue a **fresh warmup each iteration** — a request issued before propagation is dropped from the log stream and polling its `traceparent` never returns logs even after propagation completes.

Loop up to **12 iterations** (10s gap → 2 min cap):

1. Issue `GET <test_base_url>` (no extra path; ignore body/status — origin behavior is irrelevant to this probe).
2. Capture response `traceparent` (W3C `00-<trace-id>-<parent-id>-<flags>`).
3. Wait 5s for logs to flush.
4. Query `gcore_api` GET `/fastedge/v1/apps/{app_id}/logs?request_id=<traceparent>`.
5. If `count > 0` → propagation confirmed, break and proceed.
6. Otherwise wait 5s and repeat with a fresh warmup.

If 12 iterations exhaust with no logs:

- **Run the Rust stderr-logging scan from Step 8 first** (third hypothesis for empty log queries; cheapest to verify). If matches found, surface the stderr diagnostic **in place of** the propagation NOTE — stderr-bound logging produces this exact symptom regardless of propagation state and wins priority.
- Only if no stderr matches (or project is not Rust), surface the NOTE: "propagation may still be in flight, or the app may have no log() calls on the warmup path" and proceed anyway.

**App-has-no-log-calls edge case**: if Step 9 inference identified zero `log(...)` calls in any hook, skip the poll and use a fixed 60s wait.

## Step 6 — Scenario Sweep

For each `fixtures/*.test.json` (alphabetical order):

1. Read the fixture. Extract request shape:
   - **HTTP**: `request.path`, `request.method`, `request.headers`, `request.body`. Path verbatim.
   - **CDN**: `request.url` is a placeholder local-debugger URL (typically `http://fastedge-builtin.debug` + optional path). Parse it and extract the **path component**. The `host` header is irrelevant for live-test. `properties` (geo, scheme, country) come from the edge based on real client — log a NOTE if the fixture has `properties` set so the developer knows assertions run against real edge geo.
2. Build live URL:
   - HTTP: `<test_base_url>` + `request.path`
   - CDN: `https://<cname>/<rulePathPrefix><app-name>/<extracted-path>`. Empty path → trailing slash form.
3. Issue HTTP request with method, headers (excluding `host`), body.
4. **Capture the response `traceparent` header** — scopes log queries to this specific request, isolating per-scenario logs from other traffic. Store alongside status/headers/body.
5. Look for sibling `<basename>.live.json`. Read its `expected` block if present.
6. Pass response (status, headers, body, traceparent) + `expected` block to Step 7.

Throttle: 1 request per 200ms. Step 5.5 already confirmed propagation. If a scenario nonetheless 502s/times out, retry once after 5s before reporting fail.

## Step 7 — Assertion Runner

The assertion vocabulary mirrors the HTTP-observable subset of `@gcoredev/fastedge-test`:

| Field in `expected` | Assertion |
|---|---|
| `status: <number>` | Exact equality on response status |
| `headers: { name: value }` | Per header, case-insensitive name lookup, exact match (or array equality, or substring containment if value is `{ contains: "..." }`) |
| `noHeaders: ["name", ...]` | Each named header must be absent |
| `body: "<string>"` | Exact equality on response body |
| `bodyContains: "<string>"` | Substring match on body |
| `contentType: "<type>"` | Case-insensitive substring on Content-Type |
| `json: { ...partial }` | Parse body as JSON; assert each key in partial matches |
| `logs: ["substring", ...]` | Query `gcore_api` GET `/fastedge/v1/apps/{id}/logs?request_id=<scenario.traceparent>`. For each substring, assert ≥1 returned log contains it. |
| `noLogs: ["substring", ...]` | Same scoped query. No returned log contains any listed substring. |

`request_id` filter eliminates time-window guessing and isolates per-scenario logs. If `expected` has neither `logs` nor `noLogs`, skip the log query.

Per scenario:
- **PASS**: all assertions matched
- **FAIL**: any assertion failed — print diff (expected vs actual)
- **WARN**: no `.live.json` sibling — print response (status, headers, body up to ~500 bytes) without asserting

**Stderr diagnostic on `logs` assertion FAIL (Rust only):** when a scenario FAILs because its `logs` query returned empty, run the Rust stderr-logging scan from Step 8 **once for the whole sweep** (cache; do not re-scan per scenario). If matches found, attach the stderr diagnostic to every affected FAIL diff — empty log queries on Rust apps are almost always "wrong file descriptor," not "wrong assertion." Verdict still stands as FAIL; diagnostic just explains why.

## Step 8 — Debug Window & Diagnostics

### Stderr-bound logging scan (Rust only)

Highest-priority hypothesis when log queries return empty. Referenced from Step 5.5 (warmup exhaustion) and Step 7 (logs-assertion FAIL on empty result). Run at most once per invocation; cache and reuse.

**Skip for non-Rust projects.** `@gcoredev/fastedge-sdk-js`'s `console-override.cpp` pipes every `console.*` level to `fprintf(stdout, ...)`; `@gcoredev/proxy-wasm-sdk-as`'s `runtime.ts` writes via `process.stdout.write`. Both stdout-safe — a scan would only produce false positives. Gate: `Cargo.toml` present at `<project-root>`.

Procedure (Rust only):

1. Glob `<project>/src/**/*.rs`.
2. Grep for: `\beprintln!`, `\beprint!`, `std::io::stderr\(\)`, `io::stderr\(\)`, `env_logger::(init|Builder::new)` without `Target::Stdout` in the same statement, `with_writer\(\s*std::io::stderr`, `proxy_wasm::hostcalls::log\s*\(`, `hostcalls::log\s*\(` (proxy-wasm log hostcall; FastEdge does not capture hostcall-level logs — stdout only).
3. Collect every hit as `(file, line, matched_token, full_line_text)`.

Diagnostic format (when matches found):

```
⚠ Likely cause: stderr-bound logging detected in <project>/src

  <file>:<line>  <matched_token>
      <full_line_text>
  [...up to 5; if more, append "(+N additional matches)"]

  FastEdge captures stdout only — stderr writes are silently dropped, producing
  empty log queries regardless of propagation state, debug-window status, or
  assertion correctness. Almost certainly why the log query returned nothing.

  Fix: convert to println!/print! (all Rust apps — HTTP and CDN), redeploy,
  and re-run live-test. proxy_wasm::hostcalls::log calls, direct stderr
  writers, env_logger defaults, and tracing-subscriber stderr overrides
  each need manual review — see skills/scaffold/reference/{http,cdn}/base-rust.md
  § Logging Convention for the per-pattern fix.
```

When no matches (or non-Rust), diagnostic is suppressed; caller emits its original NOTE / FAIL diff unchanged.

### Debug window expiry

If `debug_until` was within 2 minutes of expiring at start of sweep, re-PATCH `debug:true` partway through to extend the window. Surface to the user.

If the run took >30 min, the tail end may have run with debug disabled (log queries return zero entries even though the filter ran). Warn and suggest fewer/faster scenarios.

### Failure-mode diagnostics

If any scenario FAILed on a logs assertion, optionally pull a broader unfiltered log slice for the run window:

```
gcore_api GET /fastedge/v1/apps/{app_id}/logs?from=<run_start>&to=<now>
```

Informational only — surface in the report's debug section, not in the assertion verdict.

## Step 9 — Report

```
Live-test results — <app-name> @ <test_base_url>

  ✓ happy-path           (3 assertions)
  ✓ germany              (4 assertions)
  ✗ missing-env          (1 of 2 assertions failed)
       expected status 500, got 200
  ⚠ default              no .live.json — printed response above

Summary: 2 passed, 1 failed, 1 unasserted
debug window: closes at 2026-04-28T15:23:00Z (in 27 min)
```

Exit non-zero if any FAIL. WARN does not affect exit status.

## Step 10 — Cleanup (Optional)

If `--cleanup` was passed AND the run was for a CDN app:

```
PATCH /cdn/resources/{cdnResourceId}/rules/{rule_id}
{ "active": false }
```

Disables the test rule without deleting it. DELETE is not currently in the MCP policy. Rule remains discoverable for the next run.

HTTP apps need no cleanup — debug auto-disables after 30 min.

If `--cleanup` was not passed, surface a reminder of where the rule persists and how to disable later.

## References

- `plugins/gcore-fastedge-codex/skills/live-test/reference/live-json-schema.md` — full `expected` block shape
- `plugins/gcore-fastedge-codex/skills/debug/reference/inference.md` — determines CDN hook phases (Step 5) and assertion inference (Step 3.5)
- `plugins/gcore-fastedge-codex/skills/test/reference/test-framework.md` — in-process assertion vocabulary that live-test mirrors

## Anti-Patterns

- **Don't** create a new CDN resource per app or per run. Resources take ~20 min to propagate; use one preconfigured resource per developer.
- **Don't** silently re-deploy without running tests. The pre-flight gate is intentional.
- **Don't** delete CDN rules. Current MCP policy is `active: false`. Lingering inactive rules are acceptable.
- **Don't** infer origin-derivable assertions silently. `--infer` emits only filter-derivable assertions per `inference.md` Step 9. Origin-dependent assertions (status when traffic passes through, content-type, JSON shape, `noLogs`) must not be guessed.

## Worked Examples

These anchor expected behavior across HTTP vs CDN paths, env-sync delegation, and the propagation warmup. Mirror the structure when handling real requests.

### Example 1 — First live-test on an HTTP app

**User prompt**: "live-test product-cache"

**Behavior**:

- Step 1: HTTP-WASM (TypeScript with `fastedge-build`).
- Step 2: `fixtures/livetest.config.json` absent — fine for HTTP apps.
- Step 3: 5 fixtures present, 5 `.live.json` siblings present. Local `npm test` runs and passes. Proceed.
- Step 3.5: skipped (no `--infer`).
- Step 4: delegate to `/gcore-fastedge:deploy product-cache --description "⚡live-test - Product cache HTTP service" --no-magic-comments`. Deploy returns `app_id=4732724`.
- Step 4.5: source dir defaults to `fixtures/`. Found `fixtures/.env` with 2 vars + 1 secret. Delegate to `/gcore-fastedge:manage sync-env 4732724 --from fixtures/`. Manage reports diff: 3 adds, 0 removals → Case A auto-applies silently.
- Step 5 (HTTP branch): `enable-app-http` returns `url=https://product-cache-4732724.fastedge.cdn.gc.onl/`, `debug_until=2026-05-20T16:23:00Z`.
- Step 5.5: skipped (HTTP, no propagation phase).
- Step 6: iterate 5 fixtures, issue HTTP requests, capture `traceparent` per request.
- Step 7: assert against `.live.json` `expected` blocks. 4 pass, 1 fails on a `logs` assertion.

**Completion output**:

```
Live-test results — product-cache @ https://product-cache-4732724.fastedge.cdn.gc.onl/

  ✓ happy-path           (3 assertions)
  ✓ germany              (4 assertions)
  ✗ missing-env          (1 of 2 assertions failed)
       expected log "config missing", got no matching log entries
  ✓ auth-missing         (2 assertions)
  ✓ post-json-body       (3 assertions)

Summary: 4 passed, 1 failed, 0 unasserted
debug window: closes at 2026-05-20T16:23:00Z (in 27 min)

Failure diagnostics (broader log slice for the run window):
  No "config missing" log entry. Check the unset-env branch in src/index.ts.

Exit code: 1
```

### Example 2 — CDN app with `--cleanup` re-run

**User prompt**: "live-test geo-router --cleanup"

**Behavior**:

- Step 1: CDN (proxy-wasm Rust).
- Step 2: `fixtures/livetest.config.json` present with `cdnResourceId: 2296532`. Gitignore guard: file not gitignored → OK.
- Step 3: 3 fixtures + 3 siblings present. Local tests pass.
- Step 4: deploy with `⚡live-test - ` prefix + `--no-magic-comments`. App id `4732801`, kebab-transformed name unchanged.
- Step 4.5: `fixtures/.env` has env-sync diff: 1 change, 0 removals → Case A auto.
- Step 5 (CDN branch): list rules on resource 2296532 → existing rule at `/livetest-geo-router/` (rule id 88912). Call `attach-app-to-cdn-rule-update` with `app_id=4732801`, hook block on `on_request_headers` (only phase implemented). Test base URL: `https://cdn.example.com/livetest-geo-router/`.
- Step 5.5 (CDN update path): brief warmup — 5s wait, one warmup GET, 200 OK, proceed.
- Step 6: iterate 3 fixtures, build URLs as `https://cdn.example.com/livetest-geo-router/<path>`.
- Step 7: 3/3 pass.
- Step 10 (`--cleanup`): PATCH rule 88912 with `{ "active": false }`.

**Completion output**:

```
Live-test results — geo-router @ https://cdn.example.com/livetest-geo-router/

  ✓ block-de           (2 assertions)
  ✓ allow-us           (2 assertions)
  ✓ block-no-geo       (1 assertion)

Summary: 3 passed, 0 failed, 0 unasserted
debug window: closes at 2026-05-20T16:23:00Z (in 28 min)

Cleanup: CDN rule 88912 disabled (active: false). Rule preserved on resource 2296532
for next run. Re-run /gcore-fastedge:live-test geo-router to re-enable.

Exit code: 0
```

### Example 3 — Degraded mode: no fixtures

**User prompt**: "live-test product-cache --infer"

**Behavior**: Step 3 pre-flight — `fixtures/` directory is empty (or absent). `--infer` only auto-authors **siblings** for existing fixtures; it can't conjure fixtures from nothing. Abort before deploy.

**Completion output**:

```
✗ No fixtures found in fixtures/.

Live-test runs scenario fixtures against a deployed app — without fixtures there's
nothing to verify. Generate them first:

  /gcore-fastedge:debug product-cache --infer

Then re-run live-test (also with --infer to auto-author the .live.json siblings):

  /gcore-fastedge:live-test product-cache --infer

Nothing deployed. Nothing changed.
```
