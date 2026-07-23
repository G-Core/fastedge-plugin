---
name: live-test
disable-model-invocation: false
argument-hint: "[project-dir] [--infer] [--cleanup] [--from <dir>] [--no-env-sync] [--auto-apply]"
description: Build, deploy, and verify a FastEdge app against real edge traffic. Runs scenario fixtures against the deployed app and reports pass/fail per scenario. Auto-syncs `<project>/fixtures/.env*` to the deployed app on each run so env-driven apps work out of the box. Pass --infer to auto-author missing .live.json siblings from source; --cleanup to disable the test rule; --from <dir> to point env-sync at a different directory (e.g. a per-variant subdir); --no-env-sync to skip env-sync; --auto-apply to apply destructive env diffs without prompting.
---

# /gcore-fastedge:live-test

Verify a FastEdge app on the live edge. After local tests and fixtures pass, this skill builds, deploys, wires the app to a test target (an HTTP app URL or a CDN rule on a preconfigured resource), and runs each fixture scenario against the real deployment with HTTP-level assertions.

## When to Use

| You have... | Run... |
|---|---|
| Working tests only (`tests/*.test.ts`) | `/gcore-fastedge:debug --infer` first to materialize fixtures, then `/gcore-fastedge:live-test --infer` |
| Working fixtures, no `.live.json` siblings | `/gcore-fastedge:live-test --infer` to auto-author drafts from source, then re-run for pass/fail. Or run without `--infer` for print-only mode |
| Working fixtures + hand-authored `.live.json` siblings | `/gcore-fastedge:live-test` directly |
| Neither fixtures nor tests | Stop. Author tests or fixtures first. Live-test without scenarios has nothing to verify. |

This skill is **not** a substitute for `/gcore-fastedge:test`. Local tests run in-process against the WASM module with rich hook-internal assertions. Live-test runs HTTP requests against a deployed app and asserts only what's observable from outside (status, headers, body, logs). Both have a place.

---

## MCP Server Integration

This skill uses MCP workflows (executor layer) chained by skill orchestration:

| Workflow | Purpose |
|---|---|
| `enable-app-http` | PATCH app `debug:true`, return URL + `debug_until` (HTTP apps) |
| `attach-app-to-cdn-rule-create` | PATCH app `debug:true` + POST a new CDN rule wiring app at `/livetest-<name>/` (CDN apps, first run) |
| `attach-app-to-cdn-rule-update` | PATCH app `debug:true` + PATCH existing CDN rule (CDN apps, iterative re-runs) |
| `update-env-vars-app` (via `/gcore-fastedge:manage sync-env`) | Sync `.env*` from `<source-dir>` to the deployed app's env / secrets / rsp_headers (Step 4.5) |

If MCP tools fail, diagnose first (Docker running? API key forwarded? Network?) — see `/gcore-fastedge:deploy` for the canonical MCP config and recovery steps. Do not silently fall back to direct API calls without warning the user.

---

## Step 1 — Detect App Type

Same signals as `/gcore-fastedge:debug`:

| Signal | App Type |
|---|---|
| `Cargo.toml` with `proxy-wasm` dep, or `asconfig.json` present | CDN (proxy-wasm) |
| `package.json` with `fastedge-build` in build script | HTTP (http-wasm) |
| `Cargo.toml` with `fastedge` or `wstd` dep | HTTP (http-wasm) |

If ambiguous, ask before continuing. Type determines which MCP workflow to invoke and how to construct test URLs.

---

## Step 2 — Read Live-Test Config

Look for `fixtures/livetest.config.json` — co-located with the scenario fixtures it configures, in the same spirit as a per-app `.env`. Schema:

```json
{
  "cdnResourceId": 2296532,
  "rulePathPrefix": "/livetest-"
}
```

- `cdnResourceId` — required for CDN apps. The preconfigured resource that hosts test rules. Should be set up once with the desired origin and aliases (CDN resources take ~20 min to propagate, so we do not create them on the fly).
- `rulePathPrefix` — optional, defaults to `/livetest-`. Test rules are created at `<prefix><app-name>/` so each app gets a unique stable path on the resource.

For HTTP apps, the file may be absent or empty — HTTP apps don't need a CDN resource.

If the file is missing on a CDN-app run, prompt the user for the resource ID (typically a number they get from the Gcore portal or `GET /cdn/resources`) and write the file. The fixture loader globs `fixtures/*.test.json` so a bare `livetest.config.json` is not picked up as a scenario — safe to co-locate.

### Gitignore Guard

Before writing or relying on `fixtures/livetest.config.json`, check the project's `.gitignore`. If `fixtures/livetest.config.json` (or any pattern that would match it, like `livetest.config.json`) is ignored, warn loudly:

```
⚠ fixtures/livetest.config.json is gitignored — config will not travel with the repo.
  CI runs and other developers won't see your CDN resource setting.
  Suggest: remove the gitignore rule, or commit the file with a comment.
```

Do not silently proceed; ask whether to fix.

---

## Step 3 — Pre-Flight (Tests + Fixtures)

Verify the project has scenarios to run:

1. Are there `fixtures/*.test.json` files? If none, abort with: "No fixtures found. Run `/gcore-fastedge:debug --infer` to generate scenarios from your code, then re-run live-test."
2. Are there `*.live.json` siblings? Count them.
   - If `--infer` was passed → proceed to Step 3.5 to auto-author missing siblings.
   - If `--infer` was not passed and zero siblings exist → warn: "No `.live.json` siblings found — running in print-only mode (no pass/fail assertions). Pass `--infer` to auto-author from source, or hand-author `expected` blocks per `reference/live-json-schema.md`."
   - If `--infer` was not passed and some siblings exist → continue. Print-only applies only to fixtures missing a sibling.
3. Run local tests if a Node test harness exists. Branch on layout:
   - **New layout** — `fastedge-test/app.test.mjs` exists:
     - Rust (no root `package.json`): `cd fastedge-test && npm test`.
     - JS/TS / AS (root `package.json` present): `npm test` from project root.
   - **Legacy layout** — only root `tests/*.test.*` exists: `npm test` from project root.
   - **No harness**: skip this step (no local-test gate to apply).

   If the harness exists and tests fail, abort. Don't deploy broken code to verify it on the edge — fix locally first.

The pre-flight is intentionally simple. Whether scenarios exist (Step 1) is a debug-skill concern; whether assertions exist for them is what live-test owns.

---

## Step 3.5 — Infer `.live.json` Siblings (`--infer` only)

Skip this step unless `--infer` was passed. When passed, before deploying:

1. Apply inference to the project per `../debug/reference/inference.md` end-to-end. Read **all sections** including **Step 9: Assertion Inference** — that's the section that drives `expected` block construction. Do not skim.
2. For each `fixtures/<basename>.test.json` lacking a `<basename>.live.json` sibling:
   - Match the fixture to a scenario in the inference output by basename ↔ `scenarios[].name`.
   - Take that scenario's `expected` block.
   - If the fixture's basename does not match any inferred scenario name (the developer authored a fixture not produced by inference), fall back to the **intersection** assertion — only `logs` reached on every branch — and surface a NOTE so the developer knows.
   - Write `<basename>.live.json` with shape `{ "expected": <block> }`.
3. After writing, print the list of inferred files with a one-line preview of each `expected` block. Tell the developer these are **drafts derived from source** — review before relying on the pass/fail signal. Inferred assertions are filter-derivable only:
   - `logs` from `log(...)` calls
   - `status` and `body` from `sendLocalResponse` / short-circuit calls
   - `headers` / `noHeaders` from response header mutations

   Origin-derivable assertions (`status` when traffic passes through to origin, `contentType`, `json` shape, `noLogs`) are **not** inferred — the developer adds those manually if they want to assert on them.
4. Continue to Step 4 (build & deploy).

If `--infer` was passed but every fixture already has a `.live.json` sibling, surface "Nothing to infer — all fixtures have siblings" and proceed without modifying any file.

---

## Step 4 — Build & Deploy

Delegate to `/gcore-fastedge:deploy`. Pass:

- The project directory.
- `--description "⚡live-test - <text>"` where `<text>` is the project's `package.json` `description` field (or `Cargo.toml` `package.description`), falling back to the original (pre-kebab) project folder basename if no description field exists. Truncate the full string to 250 chars before passing. The leading `⚡` is a literal U+26A1 lightning-bolt emoji — preserve it exactly (do not substitute ASCII bracket forms).
- `--no-magic-comments` — **always**. Live-test must not modify the target project's source files; that's a validation-context governance rule (see `proxy-wasm-sdk-as/AGENTS.md` and equivalents in other example repos). The user can run deploy directly without this flag if they want Magic Comments in their own iteration cycle.

The `⚡live-test - ` prefix flags the app in the FastEdge UI as having been created by live-test rather than a hand-deploy — the lightning-bolt sentinel makes live-test apps visually scannable in the portal's app list. Deploy applies the description on CREATE only — re-runs UPDATE the binary without touching the comment, preserving any custom value the user may have set via the portal.

After deploy completes, capture the resulting `app_id` and `app_name` (the name may differ from the project folder if deploy applied a kebab transform, so always read it from the deploy result rather than re-deriving). If deploy fails, abort — there's nothing to test.

---

## Step 4.5 — Sync Env to Deployed App

Unless `--no-env-sync` was passed, sync `.env*` from the source directory to the deployed app **before** wiring the test target. Without this step, env-driven apps (anything reading `getEnv()` / `getSecret()`) see an empty env on the edge and every scenario that depends on configuration FAILs by default.

### Resolve `<source-dir>`

- If `--from <dir>` was passed, use that directory (relative to project root, or absolute).
- Otherwise default to `<project>/fixtures` — the canonical location for live-runtime values per the debug skill convention (`fixtures/.env` is co-located with the scenario fixtures it parameterizes).

### Skip cases

- `--no-env-sync` passed → print `Env-sync skipped (--no-env-sync)` and proceed to Step 5.
- `<source-dir>` does not exist OR contains no `.env*` files → print `No .env* in <source-dir>, skipping env-sync` and proceed to Step 5. Apps that don't consume env config are fine here — nothing to sync.

### Delegate to manage sync-env

Otherwise, invoke `/gcore-fastedge:manage sync-env <app_id> --from <source-dir>` and pass through `--auto-apply` if live-test received it.

The manage skill owns parsing, secret-name resolution, diff computation, and the tiered confirmation policy (auto-apply additive, prompt destructive with default-no-removal). Don't re-implement any of that here — surface manage's output in the live-test progress stream and proceed when manage returns.

If manage prompts (destructive diff case), live-test pauses on that prompt as a natural part of the flow. On `Cancel sync` (manage's option `[c]`), abort the live-test run — the deployed app is in a state the user explicitly rejected, so don't continue to the sweep.

### Per-variant env workflow

The deployed app has exactly one env set, and Step 6 reuses that one deployed app across every scenario in the sweep. Per-scenario `dotenv.path` overrides in `*.test.json` are debugger-only and do **not** influence live-test.

To exercise scenarios that need different env values, re-run live-test pointing `--from` at a variant subdirectory:

```bash
/gcore-fastedge:live-test --from fixtures/germany/
/gcore-fastedge:live-test --from fixtures/us/
```

Each invocation re-syncs env (replacement semantics — `fixtures/germany/.env` is the complete env truth for that run, no layering on top of `fixtures/.env`) and runs the sweep against that env. Iterate by editing the relevant `.env`, re-running, and reading the report.

---

## Step 5 — Wire the Test Target

Branch by app type.

### HTTP App

Call MCP workflow `enable-app-http` with `app_id`. Capture the response:
- `$app.url` — public test URL (e.g. `https://my-app-4732724.fastedge.cdn.gc.onl/`)
- `$app.debug_until` — RFC3339 timestamp; debug auto-disables 30 minutes after the PATCH

The test URL becomes the base URL for the scenario sweep. No CDN involved.

### CDN App

The wiring is more involved because CDN rules are stateful.

1. **List rules on the resource**: `GET /cdn/resources/{cdnResourceId}/rules`
2. **Look for a rule** at path `<rulePathPrefix><app-name>/` (e.g. `/livetest-helloWorld/`). Match on the `rule` field.
3. **Construct `fastedge_options`** — the body to wire on the rule. Default policy: enable on the hooks the app actually implements (use `reference/inference.md` to determine which phases). Skill uses:
   ```json
   {
     "enabled": true,
     "on_request_headers": {
       "enabled": true,
       "app_id": "<deployed-app-id>",
       "interrupt_on_error": true,
       "execute_on_edge": true,
       "execute_on_shield": false
     }
   }
   ```
   Add equivalent blocks for `on_request_body`, `on_response_headers`, `on_response_body` if the app implements those hooks. (The CDN supports all four phases.) `interrupt_on_error: true` is the right default for live-test — we want failures surfaced, not silently swallowed.
4. **Pick the workflow**:
   - Rule found → call `attach-app-to-cdn-rule-update` with `rule_id`, `app_id`, `resource_id`, `fastedge_options`
   - Rule not found → call `attach-app-to-cdn-rule-create` with `rule_name` (e.g. `livetest-helloWorld`), `rule_path` (e.g. `/livetest-helloWorld/`), `app_id`, `resource_id`, `fastedge_options`
5. **Construct the test base URL**: `https://<resource_cname>/livetest-<app-name>/`. Get `cname` from the resource details (`GET /cdn/resources/{id}`).

The test base URL is what the scenario sweep hits. Persistence: rules stay attached after the run unless `--cleanup` is passed.

---

## Step 5.5 — Propagation Warmup

Branch on which workflow Step 5 picked. The goal is to confirm the FastEdge filter is actually running on the rule path before the scenario sweep starts — running the sweep prematurely produces false-FAILs because the filter hasn't attached at the edge yet.

### HTTP App

Skip this step. `enable-app-http` toggles debug on an already-deployed app URL; there is no rule-propagation phase to wait for. Proceed directly to Step 6.

### CDN App, update path (`attach-app-to-cdn-rule-update` was called)

Brief warmup: wait 5s, then issue one warmup request to `<test_base_url>` and discard the response. If it 502s or times out, retry once after another 5s wait. After that, proceed to Step 6.

### CDN App, fresh-attach path (`attach-app-to-cdn-rule-create` was called)

Empirical propagation observed at 60–120s for new rules — much longer than rule updates. The readiness signal is "a fresh request lands on a propagated edge node and produces logs". This requires issuing a **new warmup each iteration** — a request issued before propagation is dropped from the log stream and polling its `traceparent` will never return logs even after propagation completes.

1. Loop up to **12 iterations** (10s gap each → 2 min total cap):
   1. Issue a warmup `GET <test_base_url>` (no extra path; ignore response body and status — origin behavior is irrelevant to this probe).
   2. Capture the response `traceparent` header (W3C format `00-<trace-id>-<parent-id>-<flags>`).
   3. Wait 5s to allow logs to flush to the API.
   4. Query `GET /fastedge/v1/apps/{app_id}/logs?request_id=<traceparent>`.
   5. If `count > 0` → the filter ran for *this iteration's* request, propagation is confirmed. Break out and proceed to Step 6.
   6. Otherwise wait 5s (rounding out the 10s gap) and repeat with a fresh warmup.
2. If all 12 iterations exhaust without logs:
   - **Run the Rust stderr-logging scan from Step 8 first** (this is the third hypothesis for empty log queries, and the cheapest to verify). If it finds matches, surface the stderr diagnostic to the user **in place of** the propagation NOTE below — stderr-bound logging produces this exact symptom regardless of propagation state, and the diagnostic should win priority.
   - Only if the scan finds no stderr matches (or the project is not Rust), surface this NOTE and proceed:

   ```
   ⚠ No edge logs for any warmup request in 2 min. Either propagation is still
     in flight, or the app has no log() calls reachable on the warmup path.
     Proceeding to sweep — log-based assertions may falsely fail if propagation
     is still the cause.
   ```

**Why a fresh warmup per iteration:** logs are only retained for requests that hit a propagated edge node. If the first warmup landed on a node before its rule was attached, that request's events are dropped — polling its `traceparent` returns `count=0` indefinitely, even after the node propagates. Each new warmup samples the current state.

**App-has-no-log-calls edge case**: if Step 9 inference identified zero `log(...)` calls in any hook, skip the poll and use a fixed 60s wait instead — the poll has nothing to find. This is rare (most filters log something).

The warmup logs live harmlessly in the edge buffer; do not delete them. Each scenario in Step 6 carries its own `traceparent`, so the warmup's logs cannot pollute scenario assertions.

---

## Step 6 — Scenario Sweep

For each `fixtures/*.test.json` (in alphabetical order):

1. Read the fixture. Extract the request shape:
   - **HTTP apps**: `request.path`, `request.method`, `request.headers`, `request.body`. Path is taken verbatim.
   - **CDN apps**: `request.url` is a placeholder URL the local debugger uses (typically `http://fastedge-builtin.debug` plus an optional path). Parse it and extract the **path component** (everything after the host). `request.method`, `request.headers`, and `request.body` are extracted as-is. The `host` header in the fixture is irrelevant for live-test — the live URL has its own host. `properties` (geo, scheme, country, etc.) come from the edge layer based on the actual client and cannot be set via the request — log a NOTE if the fixture has `properties` set so the developer knows the assertion is run against real edge geo, not the fixture override.
2. Build the live URL:
   - HTTP: `<test_base_url>` + `request.path`
   - CDN: `https://<cname>/<rulePathPrefix><app-name>/<extracted-path>`. If the extracted path is empty or `/`, the URL is `https://<cname>/<rulePathPrefix><app-name>/` (trailing slash matches the CDN rule path).
3. Issue an HTTP request with the method, headers (excluding `host`), and body from the fixture.
4. **Capture the response `traceparent` header** (W3C format `00-<trace-id>-<parent-id>-<flags>`). Every request through the CDN has one; it scopes log queries to that specific request, isolating per-scenario logs from any other traffic on the app. Store it on the response record alongside status/headers/body.
5. Look for a sibling `<basename>.live.json` (same dir, same basename). Read its `expected` block if present.
6. Pass the response (status, headers, body, **traceparent**) and the `expected` block to the assertion runner (Step 7).

Throttle modestly: 1 request per 200ms by default. Step 5.5 has already confirmed propagation, so individual scenario requests should not normally need a propagation retry. If a scenario nonetheless 502s or times out, retry once after a 5s delay before reporting fail (covers transient edge issues during the sweep).

---

## Step 7 — Assertion Runner

The assertion vocabulary mirrors the HTTP-observable subset of `@gcoredev/fastedge-test`. See `reference/live-json-schema.md` for the full `expected` shape; here's the runtime mechanic:

| Field in `expected` | Assertion |
|---|---|
| `status: <number>` | Exact equality on response status |
| `headers: { name: value }` | Per header, case-insensitive name lookup, exact match on value (or array equality if value is array, or substring containment if value is `{ contains: "..." }`) |
| `noHeaders: ["name", ...]` | Each named header must be absent |
| `body: "<string>"` | Exact equality on response body |
| `bodyContains: "<string>"` | Substring match on body |
| `contentType: "<type>"` | Case-insensitive substring on Content-Type header |
| `json: { ...partial }` | Parse body as JSON; assert each key in the partial matches |
| `logs: ["substring", ...]` | Query `GET /fastedge/v1/apps/{id}/logs?request_id=<scenario.traceparent>` — returns only logs for **this scenario's request**. For each substring in the array, assert at least one returned log entry contains it. |
| `noLogs: ["substring", ...]` | Same scoped query as above. No returned log entry contains any of the listed substrings. |

The `request_id` filter eliminates time-window guessing and isolates each scenario's logs from concurrent traffic on the same app (other scenarios in the sweep, production traffic, debug iterations). If `expected` has neither `logs` nor `noLogs`, skip the log query entirely — status/body/header assertions don't need it.

Per scenario, run all listed assertions and report:
- **PASS**: all assertions matched
- **FAIL**: any assertion failed — print the diff (expected vs actual) for the failing ones
- **WARN**: no `.live.json` sibling — print the actual response (status, headers, body up to ~500 bytes) without asserting

**Stderr diagnostic on `logs` assertion FAIL (Rust only):** When a scenario FAILs because its `logs` query returned an empty result (no log entries scoped to that scenario's `traceparent`), run the Rust stderr-logging scan from Step 8 **once for the whole sweep** (cache the result; do not re-scan per scenario). If matches are found, attach the stderr diagnostic to every affected FAIL diff in the report so the user gets root-cause information alongside the verdict — empty log queries on Rust apps are far more often "wrong file descriptor" than "wrong assertion." The verdict still stands as FAIL; the diagnostic just explains why.

---

## Step 8 — Debug Window & Failure Diagnostics

Per-scenario log assertions are already evaluated in Step 7 (scoped by `request_id`). This step covers three cross-cutting concerns that don't fit a single scenario.

### Stderr-bound logging scan (Rust only)

This scan is the **highest-priority hypothesis** when log queries return empty results — for Rust apps it explains the symptom far more often than propagation lag, debug-window expiry, or missing log calls. It is referenced from Step 5.5 (warmup exhaustion) and Step 7 (logs-assertion FAIL on empty result). Run it at most once per live-test invocation; cache the result and reuse.

**Skip this scan entirely for non-Rust projects.** The JS SDK's `console-override.cpp` pipes every `console.*` level through `fprintf(stdout, ...)`, and the AssemblyScript SDK's `runtime.ts` writes via `process.stdout.write` — both are stdout-safe by construction, and a scan would only produce false positives. The condition `Cargo.toml present at <project-root>` is the gate.

**Procedure (Rust only):**

1. Glob all `.rs` files under `<project>/src/`.
2. Grep each file for forbidden tokens:
   - `\beprintln!` — stderr macro
   - `\beprint!` — stderr macro
   - `std::io::stderr\s*\(\s*\)` — direct stderr handle
   - `io::stderr\s*\(\s*\)` — direct stderr handle when `std::io` is imported
   - `env_logger::(init|Builder::new)` with no following `Target::Stdout` in the same statement chain — env_logger defaults to stderr
   - `with_writer\s*\(\s*std::io::stderr` — tracing-subscriber stderr override
   - `proxy_wasm::hostcalls::log\s*\(` — proxy-wasm log hostcall; FastEdge does not capture hostcall-level logs (stdout only); use `println!()` instead
   - `hostcalls::log\s*\(` — same, when called via short form after `use proxy_wasm::hostcalls`
3. Collect every hit as `(file, line, matched_token, full_line_text)`.

**Diagnostic format (when at least one match is found):**

```
⚠ Likely cause: stderr-bound logging detected in <project>/src

  <file>:<line>  <matched_token>
      <full_line_text>
  [...repeat per hit, up to 5; if more, append "(+N additional matches)"]

  FastEdge captures stdout only — stderr writes are silently dropped, producing
  empty log queries regardless of propagation state, debug-window status, or
  assertion correctness. This is almost certainly why the log query returned
  nothing.

  Fix: convert to println!/print! (all Rust apps — HTTP and CDN), redeploy,
  and re-run live-test. Direct stderr writers, env_logger defaults,
  tracing-subscriber stderr overrides, and proxy_wasm::hostcalls::log calls
  each need manual review — see rules/fastedge-knowledge.mdc § "Logging
  — Stdout Only (Rust Hazard)" for the per-pattern fix.
```

When the scan finds no matches (or the project is not Rust), the diagnostic is suppressed and the calling step (5.5 or 7) emits its original NOTE / FAIL diff without modification.

### Debug window expiry

If `debug_until` was within 2 minutes of expiring at the start of the sweep, re-PATCH `debug:true` partway through to extend the window. Surface to the user when this happens — they should know the iteration cadence.

If the run took longer than 30 minutes, the tail end of scenarios may have run with debug already disabled (causing `request_id`-scoped log queries to return zero entries even though the filter ran). Warn and suggest fewer/faster scenarios next time.

### Failure-mode diagnostics

If any scenario FAILed on a logs assertion, optionally pull a broader unfiltered log slice for the run window to help the user see what *did* happen versus what they expected:

```
GET /fastedge/v1/apps/{app_id}/logs?from=<run_start_rfc3339>&to=<now_rfc3339>
```

This is purely informational — surface it in the report's debug section, not in the assertion verdict. The verdict already came from the per-scenario `request_id`-scoped query in Step 7.

---

## Step 9 — Report

Output format:

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

---

## Step 10 — Cleanup (Optional)

If `--cleanup` was passed AND the run was for a CDN app:

```
PATCH /cdn/resources/{cdnResourceId}/rules/{rule_id}
{ "active": false }
```

This disables the test rule without deleting it (DELETE is not currently in the MCP server's policy — see CHANGELOG entry on writableTags). The rule remains discoverable in the resource's rule list for the next run.

For HTTP apps, no cleanup needed — debug auto-disables after 30 min, and the app URL stays live (it's just a deployed app at that point).

If `--cleanup` was not passed, surface the reminder:

```
Test rule persisted at /livetest-<app-name>/ on resource <id>.
Re-run live-test to update; pass --cleanup to disable when done.
```

---

## Reference

- `reference/live-json-schema.md` — full `expected` block shape with examples
- `../debug/reference/inference.md` — used to determine which CDN hook phases the app needs (Step 5)
- `../test/reference/test-framework.md` — the in-process assertion vocabulary that live-test mirrors

## Anti-Patterns

❌ **Don't** create a new CDN resource per app or per run. Resources take ~20 min to propagate; live-test is for fast iteration. Use one preconfigured resource per developer.

❌ **Don't** silently re-deploy without running tests. The pre-flight gate is intentional. If the user really wants to skip, they can do it manually before invoking live-test.

❌ **Don't** delete CDN rules. The current MCP policy is `active: false` for cleanup. DELETE may be enabled later; until then, lingering inactive rules are an acceptable cost.

❌ **Don't** infer origin-derivable assertions silently. The `--infer` flag emits only filter-derivable assertions per `inference.md` Step 9 — `logs`, short-circuit `status`/`body`, response header add/remove. Origin-dependent things (response status when traffic passes through, content-type from origin, JSON body shape, `noLogs`) are **not** inferred and must not be guessed. The developer adds those after reviewing the inferred `.live.json`.
