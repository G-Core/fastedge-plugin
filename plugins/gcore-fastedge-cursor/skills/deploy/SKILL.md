---
name: deploy
disable-model-invocation: false
argument-hint: "[app-name] [--skip-tests] [--description \"<text>\"] [--no-magic-comments]"
description: Build and deploy a FastEdge app to the edge
---

# Build & Deploy to FastEdge

Deploy the current project (or a specified app) to Gcore FastEdge.

## MCP Server Integration

This skill runs build and deploy through the **FastEdge MCP server** (the plugin's executor layer — containerized toolchains for Rust, Node, and wasm targets). The plugin's bundled `mcp.json` launches it automatically; the MCP path is the default and what almost all users should be on.

**Run the MCP path.** If MCP tools fail to start or call:

1. Diagnose the error first — most "unavailable" cases are configuration, not opt-out. Common issues:
   - Docker not running — check `docker ps`
   - API key not passed to the container — check `-e GCORE_API_KEY` in MCP config
   - Workspace not mounted — check `-v` flag maps project root to `/workspace`
   - Network issues — MCP server needs internet to call the FastEdge API and pull the image
2. If the issue is recoverable, surface the fix and re-run. Show the user the canonical config:
   ```
   {
     "mcpServers": {
       "fastedge-assistant": {
         "type": "stdio",
         "command": "docker",
         "args": ["run", "-i", "--rm", "--pull=always", "-v", "${PWD}:/workspace",
                  "-e", "WORKSPACE_ROOT=/workspace", "-e", "GCORE_API_KEY",
                  "-e", "GCORE_API_BASE", "ghcr.io/g-core/fastedge-mcp-server:latest"]
       }
     }
   }
   ```
3. Only if the user explicitly chooses to skip MCP (e.g. "I don't want to run Docker"), drop to the local-toolchain sections below. Warn them they're outside the supported default path and they're responsible for keeping toolchains current. Do not auto-fall-back silently.

---

## Instructions

### Step 1: Pre-flight Checks

1. **Verify API key** — Check that `GCORE_API_KEY` environment variable is set. If not set, tell the user how to get and set it (`https://portal.gcore.com → API Keys`). Do not proceed.

2. **Detect project type** — Look for these files in the current directory or the specified app directory:
   - `asconfig.json` → AssemblyScript CDN app
   - `Cargo.toml` → Rust app
   - `package.json` (without `asconfig.json`) → JavaScript/TypeScript app

3. **Determine and validate app name** — Pick the candidate name in this priority order, first non-empty wins:
   1. Explicit `<app-name>` argument
   2. Directory basename of the project root
   3. `name` field from `package.json` (HTTP/AS) or `Cargo.toml` (Rust)

   Validate the candidate against the FastEdge regex `^[a-z0-9][a-z0-9-]*[a-z0-9]$`. If valid, use it.

   If invalid, attempt a kebab transform:
   - Insert `-` at camelCase boundaries (`helloWorld` → `hello-World`, `MyAppV2` → `My-App-V2`)
   - Lowercase everything
   - Replace `_` with `-`
   - Strip remaining non-alnum-non-hyphen characters
   - Collapse runs of `-`, trim leading/trailing `-`

   Show the transform to the user and ask:

   ```
   App name "helloWorld" doesn't match FastEdge naming rules.
   Proposed: "hello-world". Use this name? [y/N]
   ```

   Always confirm, even when the transform looks trivial — the user knows whether they meant a different convention. If the user declines, ask for an explicit name. If the kebab result is still invalid (e.g. nothing left after stripping), abort and ask for an explicit name as the argument.

4. **Capture optional description** — If `--description "<text>"` was passed, store it for use in Step 4. Deploy treats this as pass-through; it does not generate or modify descriptions itself. Live-test populates it when delegating (with a `⚡live-test - ` prefix — leading literal U+26A1 lightning-bolt emoji); other callers may pass any text. Description is applied on CREATE only — see Step 4 below.

5. **Check for existing Magic Comments** — Read the entry file for a `/* FastEdge Deployment Magic Comments` block. If present, extract `appName`, `appId`, `appUrl`, `outputFile` as defaults for this deployment.

### Step 1.5: Pre-deploy Test Check

**Do not deploy code that hasn't been tested locally.** Check for a test setup before building:

1. Look for `tests/*.test.ts`, `tests/*.test.js`, or `src/*.test.ts`
2. Look for a `test` script in `package.json`

**If tests exist:** Run them.
```bash
npm test
```
If tests fail, stop. Do not proceed to build or upload:
```
Tests failed — fix these before deploying:
  ✗ <failing test name>: <error>

Run `npm test` to check, or `npm run debug` to debug interactively.
To deploy anyway: /gcore-fastedge:deploy --skip-tests
```

**`--skip-tests` override:** If the user invokes deploy with `--skip-tests`, skip Step 1.5 entirely (including the Rust stderr lint below). Log a warning:
```
⚠ Skipping pre-deploy tests (--skip-tests flag). Deploy at your own risk.
```

**If no tests exist:** Warn but continue:
```
No tests found. Run `/gcore-fastedge:test` to generate a test suite.
Continuing with deployment — but consider adding tests.
```

#### Rust Stderr Logging Lint (Rust projects only)

**Skip this lint entirely for JS/TS and AssemblyScript projects.** Both SDKs route every logging API through stdout (`console-override.cpp` in `@gcoredev/fastedge-sdk-js`; `process.stdout.write` in `@gcoredev/proxy-wasm-sdk-as`'s `runtime.ts`) — a lint would only produce false positives. The condition `Cargo.toml present at <project-root>` is the gate.

**Run this lint regardless of whether tests exist or passed**, because a deployed Rust app with stderr-bound logging is a separate class of broken from "tests fail" — tests can pass while `/apps/{id}/logs` returns empty forever in production. The lint is the deploy skill's belt-and-suspenders against shipping invisible logging.

##### Procedure

1. Glob all `.rs` files under `<project>/src/`.
2. Grep each file for:
   - `\beprintln!` / `\beprint!`
   - `std::io::stderr\s*\(\s*\)` / `io::stderr\s*\(\s*\)`
   - `env_logger::(init|Builder::new)` not followed by `Target::Stdout`
   - `with_writer\s*\(\s*std::io::stderr` (tracing-subscriber stderr override)
   - `proxy_wasm::hostcalls::log\s*\(` / `hostcalls::log\s*\(` (proxy-wasm log hostcall; not captured by FastEdge — stdout only)
3. Collect every hit as `(file, line, matched_token, full_line_text)`.

##### When matches are found

Block the deploy (same severity as a failing test):

```
✗ Rust stderr logging lint failed — deploy blocked.

  <file>:<line>  <matched_token>
      <full_line_text>
  [...repeat per hit, up to 5; if more, append "(+N additional matches)"]

  FastEdge captures stdout only. Deploying this binary will produce an app
  whose logs never reach /apps/{id}/logs, /gcore-fastedge:live-test
  assertions, the visual debugger, or any other observability surface.
  Tests passing locally does not detect this — local capture may differ
  from the edge.

  Fix: convert to println!/print! (all Rust apps — HTTP and CDN).
  Direct stderr writers, env_logger defaults, tracing-subscriber stderr
  overrides, and proxy_wasm::hostcalls::log calls each need manual review —
  see rules/fastedge-knowledge.mdc § "Logging — Stdout Only (Rust Hazard)".

To deploy anyway: /gcore-fastedge:deploy --skip-tests
```

The `--skip-tests` flag is reused (rather than adding a new `--skip-stderr-lint`) on the principle that pre-deploy gates should share one override — a user who knows the binary is broken in some way should be able to bypass all local checks at once. Surface that this flag also covers the stderr lint when it's invoked, so the user knows what they're skipping.

##### When no matches are found

Proceed silently to Step 2. No success message — the absence of a block is the signal.

### Step 2: Build

**Via MCP (primary):** Use the `build-wasm` tool.

| Parameter | Value |
|-----------|-------|
| `entryFile` | Entry file path (e.g., `./src/index.ts`, `./src/lib.rs`, `./assembly/index.ts`) |
| `outputFile` | Target WASM path (e.g., `./<project-name>.wasm`) |
| `buildDirectory` | Project root (if not current directory) |

The tool detects the language from the file extension and runs the appropriate compiler. On success it returns the path to the built WASM binary. Save this for Step 3.

**Local opt-out (only if user declined MCP):**

- JavaScript/TypeScript: `fastedge-build ./src/index.js ./<project-name>.wasm`
- Rust: `cargo build --release --target wasm32-wasip1` → output at `./target/wasm32-wasip1/release/<crate-name>.wasm`
- AssemblyScript: `npm run asbuild:release` → output at `./build/release.wasm`

If build fails, show error and help user fix it. Do not proceed.

### Step 3: Upload Binary

**Via MCP (primary):** Use the `upload-binary` tool.

| Parameter | Value |
|-----------|-------|
| `wasmFile` | Relative path to the WASM binary from Step 2 |

On success returns a binary ID (integer). Save this for Step 4.

**Local opt-out (only if user declined MCP):**
```bash
BINARY_RESPONSE=$(curl -s -X POST "https://api.gcore.com/fastedge/v1/binaries/raw" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$WASM_FILE")
BINARY_ID=$(echo "$BINARY_RESPONSE" | jq -r '.id')
```

### Step 4: Create or Update App

#### 4.1 — Collision check (run before invoking MCP)

If Magic Comments (Step 1.5) supplied an explicit `appId`, treat that as a pre-confirmed UPDATE — skip to Step 4.2 with that id.

Otherwise:

1. List apps via `gcore_api` (`GET /fastedge/v1/apps`) and look for a `name` match against the chosen name from Step 1.3.
2. If no match → CREATE path. Skip to Step 4.2.
3. If match found, fetch full metadata: `GET /fastedge/v1/apps/{id}`.

**Hard refuse on `api_type` mismatch.** If the existing app's `api_type` is `wasi-http` and your project is proxy-wasm (`asconfig.json` present, or `Cargo.toml` with `proxy-wasm`), or vice versa — abort the update without prompting. Different runtime models; overwriting silently breaks the existing app.

```
✗ Existing app "hello-world" is api_type=wasi-http, but your project is proxy-wasm.
  Different runtime model — overwriting would silently break the existing app.
  Refusing. Pick a different name (suggested below) or stop and pick one yourself.
```

Suggest a kebab-safe alternative — `<chosen-name>-<random-pool-name>` from the **Random pool** below — and re-validate against Step 1.3. Loop until accepted or the user supplies an explicit name.

**Prompt on `api_type`-match collision.** If `api_type` matches the project shape, surface the existing app's metadata and ask:

```
App "hello-world" already exists on this account.
  Type:    proxy-wasm
  Comment: Hello world filter for /api/*
  Binary:  421727
  URL:     <if available>

Update this app, or pick a different name? [u/n]
```

- User accepts (`u`) → UPDATE path with the existing app's id. **Remember the confirmation in this conversation** — if the user re-runs deploy on the same project later in the same session, do not re-prompt for that same app id.
- User declines (`n`) → propose `<chosen-name>-<random-pool-name>` from the pool. Confirm:

  ```
  Proposed alternative: hello-world-rapunzel. Use this name? [y/n]
  ```

  On accept, restart Step 4.1 with the new name. On decline, pick another pool name (or let the user supply their own). Cap at three pool suggestions before falling back to "please supply a name explicitly".

**Random pool** (kebab-safe; pick uniformly at random):

```
Fairy-tale:  aladdin, ariel, belle, cinderella, hansel, gretel, merida, mulan,
             pinocchio, rapunzel, tiana, snow-white
Star Wars:   yoda, leia, luke, chewbacca, han-solo, padme, ahsoka, rey, finn,
             obi-wan, anakin, boba-fett, grogu
Star Trek:   kirk, spock, picard, data, worf, riker, janeway, sisko, scotty,
             uhura, sulu, archer, tuvok
```

#### 4.2 — Create or update via MCP

**Via MCP (primary):** No dedicated `update-or-create-app` tool exists. The MCP server exposes streaming `upload-binary` (used in Step 3) plus app-management endpoints via the unified `gcore_api` tool. Branch by whether Step 4.1 produced an `appId`:

| Path | Call | Body |
|---|---|---|
| CREATE (no existing app) | `gcore_api` POST `/fastedge/v1/apps` | `{ "name": "<name>", "binary": <binaryId>, "status": 1, "comment": "<truncated-description>" }` |
| UPDATE (existing app id) | `gcore_api` PATCH `/fastedge/v1/apps/<appId>` | `{ "binary": <binaryId> }` — do NOT include `comment` (preserves any value the user later set via the portal) |

Notes:
- Truncate `comment` to **250 chars** before sending (FastEdge limit). Skip the field entirely if no description was passed.
- On CREATE, the response includes `id`, `url`, `name`. Save these for Steps 5–7.
- On UPDATE, the response echoes the existing `name`/`url`. Reuse the name from Step 4.1; the url should be unchanged.
- Two MCP calls instead of one are fine — atomicity is not required here. If the binary upload (Step 3) succeeds but the create/update fails, the orphaned binary can be cleaned up separately or simply re-bound on next deploy.

**Local opt-out (only if user declined MCP):**
```bash
# Step 4.1 already determined whether this is CREATE or UPDATE; reuse APP_ID if set.
if [ -n "$APP_ID" ]; then
  # Update existing — do NOT include comment on update path
  curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
    -H "Authorization: APIKey $GCORE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"binary\": $BINARY_ID}"
else
  # Create new — include comment if provided (truncate to 250 chars)
  COMMENT_FIELD=""
  if [ -n "$DESCRIPTION" ]; then
    TRUNC=$(printf '%s' "$DESCRIPTION" | cut -c1-250)
    COMMENT_FIELD=", \"comment\": $(printf '%s' "$TRUNC" | jq -Rs .)"
  fi
  curl -s -X POST "https://api.gcore.com/fastedge/v1/apps" \
    -H "Authorization: APIKey $GCORE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$APP_NAME\", \"binary\": $BINARY_ID, \"status\": 1${COMMENT_FIELD}}"
fi
```

### Step 5: Verify Deployment

Wait a few seconds for propagation, then verify the deployed URL:
```bash
sleep 3
curl -s -o /dev/null -w "%{http_code}" "$APP_URL"
```

This runs locally — no MCP tool needed.

### Step 6: Report Results

Print a deployment summary:
```
Deployment successful!

  App name:  <app-name>
  App ID:    <app-id>
  Binary ID: <binary-id>
  URL:       <app-url>
  Status:    <http-status>

  Manage: /gcore-fastedge:manage get <app-id>
```

If the status code is not 200, suggest debugging steps:
- 530: Check env vars and binary validity
- 531: Check for runtime errors in app code
- 532: App is timing out — optimize or upgrade plan
- 533: Memory limit exceeded — reduce binary/memory usage
- Other: The app may need a few more seconds to propagate

### Step 7: Insert Magic Comments

Magic Comments are useful for tracking which app a source file is deployed to — they let subsequent deploys (and IDE tooling) recover `appName`, `appId`, `appUrl`, `outputFile` from the source itself. Default behavior is to insert/update them on every successful deploy.

**Skip this step entirely if:**

- `--no-magic-comments` was passed on the command line, OR
- This deploy was delegated from `/gcore-fastedge:live-test` (live-test always passes `--no-magic-comments` because validation runs must not modify the target project's source — see governance rules in `proxy-wasm-sdk-as/AGENTS.md` and equivalents).

If skipping, surface a one-line note in the Step 6 report:

```
ⓘ Skipped Magic Comments insertion (--no-magic-comments). To track this app's
  deployment in source, re-run deploy without the flag.
```

Otherwise proceed with the insertion below.

**Via MCP (primary):** Use the `deployment-comments` tool to generate the comment block.

| Parameter | Value |
|-----------|-------|
| `appName` | App name |
| `appId` | App ID from Step 4 |
| `appUrl` | App URL from Step 4 |
| `outputFile` | Path to WASM binary |
| `buildDirectory` | Build directory (if applicable) |

The tool returns formatted comment text. Insert it at the top of the entry file:
- JavaScript/TypeScript: `src/index.ts` or `src/index.js`
- Rust: `src/lib.rs`
- AssemblyScript: `assembly/index.ts`

If the file already contains a `/* FastEdge Deployment Magic Comments` block, replace it. Otherwise insert before any imports.

**Local opt-out (only if user declined MCP)** — generate the block manually:
```
/* FastEdge Deployment Magic Comments
* appName: "<app-name>"
* appId: "<app-id>"
* appUrl: "<app-url>"
* outputFile: "<path-to-wasm>"
*/
```
