---
name: deploy
disable-model-invocation: true
argument-hint: "[app-name] [--skip-tests] [--description <text>] [--no-magic-comments]"
description: Build and deploy a FastEdge app via the FastEdge MCP server (the executor); halt with setup guidance if MCP is not configured
---

# FastEdge Deploy (Codex)

Deploy FastEdge apps with MCP-first execution, aligned with the Claude plugin flow.

## Execution Through MCP

This skill is the intelligence layer; the FastEdge MCP server is the executor. Build and deploy run exclusively through MCP tools:

- `build-wasm`
- `upload-binary`
- `gcore_api` — direct REST against `/fastedge/v1/apps` for collision check, create, and update
- `describe_api` — schema/endpoint discovery when needed
- `deployment-comments`
- `workflows_list`, `batch_execute` — when composing multi-step flows

There is **no** `update-or-create-app` MCP tool. App create and update both go through `gcore_api` POST/PATCH against `/fastedge/v1/apps`.

If MCP tools don't respond, halt before any execution step and diagnose the cause (see Degraded Mode below). Do not fabricate results, do not silently skip MCP, do not invent a local-toolchain path, and do not tell the user to run `codex mcp add` — the server is bundled with the plugin.

## Arguments

- `<app-name>` — explicit name (positional, optional — falls back to directory/package/crate name).
- `--skip-tests` — bypass the pre-deploy test gate. Prints a clear warning.
- `--description "<text>"` — CREATE only (ignored on UPDATE). Truncated to 250 chars. When delegated from `/gcore-fastedge:live-test`, the description is prefixed with `⚡live-test - ` automatically.
- `--no-magic-comments` — skip the post-deploy magic-comment write step. Also auto-applied when delegated from `/gcore-fastedge:live-test` (governance: live-test must not pollute source).

## Pre-Flight Checks

1. Verify API key exists (`GCORE_API_KEY`, legacy `FASTEDGE_API_KEY` accepted).
2. Detect project type:

- `asconfig.json` → AssemblyScript CDN
- `Cargo.toml` → Rust app
- `package.json` → JS/TS app

3. Determine app name:

- explicit `<app-name>` argument, or
- project directory / package / crate name.

4. **Kebab-case transform**: if the resolved name isn't valid kebab-case, propose a transform (lowercase, hyphens, no leading/trailing dashes) and ask the user to confirm. If they decline, use the random-pool fallback (Step 1.5).
5. Check for existing FastEdge magic comments and reuse `appId`/`appName` if present.

### Step 1.5 — Random-pool fallback (cap 3 attempts)

If the user rejects the proposed name OR an `api_type` collision (Step 4.1) blocks deployment, suggest names from a themed pool: fairy-tale / Star Wars / Star Trek + a domain noun (e.g. `hello-world-rapunzel`, `auth-filter-yoda`). Stop after 3 attempts and ask the user to provide a name directly.

## Step 1.7 — Test Gate Before Deploy

Unless `--skip-tests`:

1. Detect test setup (`tests/*.test.*`, `package.json` test script).
2. If tests exist, run them and **stop on failure**.
3. If no tests exist, warn ("No tests detected — deploying without test validation. Consider `/gcore-fastedge:test` first.") and continue.

If `--skip-tests`, print a clear warning that deployment is proceeding without test validation. This flag also skips the Rust Stderr Logging Lint below — one bypass for all pre-deploy gates.

### Rust Stderr Logging Lint (Rust projects only)

**Skip entirely for JS/TS and AssemblyScript.** Both SDKs route every logging API to stdout (`console-override.cpp` in `@gcoredev/fastedge-sdk-js`; `process.stdout.write` in `@gcoredev/proxy-wasm-sdk-as`'s `runtime.ts`) — a lint would only produce false positives. Gate: `Cargo.toml` present at `<project-root>`.

**Run regardless of whether tests exist or passed.** A deployed Rust app with stderr-bound logging is a separate failure class — tests can pass locally while `/apps/{id}/logs` returns empty forever in production (local capture may differ from the edge).

Procedure:

1. Glob `<project>/src/**/*.rs`.
2. Grep for: `\beprintln!`, `\beprint!`, `std::io::stderr\(\)`, `io::stderr\(\)`, `env_logger::(init|Builder::new)` without `Target::Stdout`, `with_writer\(\s*std::io::stderr`, `proxy_wasm::hostcalls::log\s*\(`, `hostcalls::log\s*\(` (proxy-wasm log hostcall; not captured by FastEdge — stdout only).
3. If matches found, **block deploy** (same severity as failing test):

   ```
   ✗ Rust stderr logging lint failed — deploy blocked.

     <file>:<line>  <matched_token>
         <full_line_text>
     [...up to 5; if more, append "(+N additional matches)"]

     FastEdge captures stdout only. Deploying this binary will produce an app
     whose logs never reach /apps/{id}/logs, /gcore-fastedge:live-test
     assertions, the visual debugger, or any other observability surface.
     Tests passing locally does not detect this — local capture may differ
     from the edge.

     Fix: convert to println!/print! (all Rust apps — HTTP and CDN).
     proxy_wasm::hostcalls::log calls, direct stderr writers, env_logger
     defaults, and tracing-subscriber stderr overrides each need manual
     review — see skills/scaffold/reference/{http,cdn}/base-rust.md
     § Logging Convention.

   To deploy anyway: /gcore-fastedge:deploy --skip-tests
   ```

4. If no matches, proceed silently to Step 2.

## Step 2 — Build

Tool: `build-wasm`. Capture output wasm path. Pass language-specific build options when the tool requires them.

## Step 3 — Upload

Tool: `upload-binary`. Capture `binaryId`.

## Step 4 — Create or Update App

### 4.1 Collision check

Use `gcore_api` to GET `/fastedge/v1/apps` filtered by name (or GET by id if known).

- **No collision** → CREATE path.
- **Collision, same `api_type`** (proxy-wasm or wasi-http matches your build) → prompt: "Update this existing app, or pick a different name?" Remember the user's confirmation for this `appId` for the rest of the session — do not re-prompt on subsequent operations against the same app.
- **Collision, different `api_type`** (e.g. existing proxy-wasm app with your wasi-http build) → **hard refuse**. Suggest the 3-pool random alternatives. Never overwrite an app of a different type.

### 4.2 Create or update

- CREATE: `gcore_api` POST `/fastedge/v1/apps` with `{ name, binary: <binaryId>, status: 1, comment: <description, truncated to 250 chars> }`.
- UPDATE: `gcore_api` PATCH `/fastedge/v1/apps/<id>` with `{ binary: <binaryId> }`. Do not send `comment` on UPDATE.

## Step 5 — Verify Deployment

- Wait ~3 seconds for propagation.
- `curl -sI <app-url>` and capture the status code.
- Report status code in completion output.

## Step 6 — Report Results

Return deployment summary with:

- App name and ID
- Binary ID
- URL
- Verification status code with inline guidance:
  - `200` → deployed and healthy
  - `530` → init/config issue (env vars, secrets, wasm import error)
  - `531` → runtime error (unhandled exception in app code)
  - `532` → timeout (50ms basic plan)
  - `533` → memory limit (128MB basic plan)
  - other → see `plugins/gcore-fastedge-codex/skills/fastedge-docs/reference/platform/error-codes.md`
- Suggested next operation (manage / debug / live-test)

## Step 7 — Magic Comments

Skip if `--no-magic-comments` was passed OR this deploy was delegated from `/gcore-fastedge:live-test`.

Otherwise: write/refresh deployment magic comments via `deployment-comments` so subsequent deploys reuse the `appId` automatically.

## When MCP Is Not Configured

Diagnose the 4 common issues before suggesting fallback:

1. Docker daemon not running.
2. `GCORE_API_KEY` not passed through to the container.
3. Workspace not mounted (`./:/workspace`).
4. Network egress blocked.

Then halt and report the diagnosis. The MCP server is bundled with the plugin — do **not** emit a `codex mcp add` command. Point the user at the fix: start Docker, make `GCORE_API_KEY` visible to Codex, or reinstall/upgrade the plugin if its cached snapshot is stale. They can confirm Codex resolves the server with:

```bash
codex mcp get fastedge-assistant
```

If — and only if — the user explicitly states they will not run Docker, surface local build/upload/app-update commands tailored to their language/app type, with a clear warning that this path is unsupported and the user is responsible for keeping their toolchain current. Do not auto-fall-back.

## Worked Examples

These anchor expected response shape, decision rationale, and degraded-mode behavior. Mirror the structure when handling real requests.

### Example 1 — First deploy (CREATE path)

**User prompt**: "deploy product-cache"

**Behavior**:

- Pre-flight: detect `package.json` with `fastedge-build` → HTTP TS app. App name `product-cache` is valid kebab-case — no transform needed.
- Test gate: detect `npm test` script, run it, pass → proceed.
- Build via `build-wasm`, capture wasm path.
- Upload via `upload-binary`, capture `binaryId`.
- Collision check via `gcore_api` GET `/fastedge/v1/apps?name=product-cache` → no match → CREATE.
- `gcore_api` POST `/fastedge/v1/apps` with `{ name, binary, status: 1 }` (no `--description` passed → omit `comment`).
- Verify: sleep 3s, curl URL, capture 200.
- Magic comments: write deployment markers via `deployment-comments`.

**Completion output**:

```
Deployed: product-cache  [HTTP / TypeScript]
  appId:    4732724
  binaryId: 88421
  URL:      https://product-cache-4732724.fastedge.cdn.gc.onl/
  status:   200  (deployed and healthy)

Next: /gcore-fastedge:manage get 4732724
      /gcore-fastedge:live-test product-cache
```

### Example 2 — Re-deploy with collision (UPDATE path)

**User prompt**: "deploy product-cache --skip-tests"

**Behavior**:

- Pre-flight: same as Example 1.
- Test gate: `--skip-tests` set → warn ("Deploying without test validation. `--skip-tests` is set.") and continue.
- Build + upload as before.
- Collision check: `gcore_api` finds existing app id `4732724` with matching `api_type` (wasi-http) → prompt: _"Update existing app `product-cache` (id 4732724), or pick a different name?"_ User confirms update. Confirmation cached for the session — no re-prompt on subsequent ops against id 4732724.
- `gcore_api` PATCH `/fastedge/v1/apps/4732724` with `{ binary: <new-id> }`. **No** `comment` field on UPDATE.
- Verify + magic comments as before.

**Completion output**:

```
Re-deployed: product-cache  [HTTP / TypeScript]
  appId:    4732724
  binaryId: 88514  (was 88421)
  URL:      https://product-cache-4732724.fastedge.cdn.gc.onl/
  status:   200

Next: /gcore-fastedge:manage get 4732724
```

### Example 3 — Degraded mode: MCP not configured

**User prompt**: "deploy product-cache"

**Behavior**: `build-wasm` tool call returns no response (MCP server not registered with Codex). Diagnose 4 common causes: Docker daemon, API key passthrough, workspace mount, network. Halt before any execution. Do NOT silently fall back.

**Completion output**:

```
✗ MCP not configured — cannot build or deploy.

Likely causes (check in order):
  1. Docker daemon not running         → `docker info`
  2. GCORE_API_KEY not in environment  → `echo $GCORE_API_KEY`
  3. Workspace mount missing           → check `-v ./:/workspace`
  4. Network egress blocked            → `docker pull ghcr.io/g-core/fastedge-mcp-server:latest`

The FastEdge MCP server ships with the plugin — no `codex mcp add` needed.
Confirm Codex sees it:

  codex mcp get fastedge-assistant

If it's missing, reinstall/upgrade the plugin so Codex picks up the bundled .mcp.json.
Re-run `/gcore-fastedge:deploy product-cache` once `codex mcp get fastedge-assistant` succeeds.
```

If the user replies that they will not run Docker, surface local-toolchain commands with the unsupported-path warning. Otherwise do not proceed.
