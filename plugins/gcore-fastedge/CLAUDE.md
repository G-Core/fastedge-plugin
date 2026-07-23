# Gcore FastEdge — Shared Knowledge Base

## RULE 0 — FILE SYSTEM SCOPE (READ THIS BEFORE ANYTHING ELSE)

**You operate exclusively inside the user's active project directory. You have no access to anything outside it.**

Before every single file read, glob, grep, or directory listing — check: does this path stay inside the project root? If the answer is anything other than a definite YES, do not proceed.

Specific prohibitions — these are NEVER acceptable under any circumstance:
- Any path containing `../` — even one level up
- Listing or reading the parent directory of the project
- Reading or grepping sibling folders (e.g. other projects that happen to be nearby on disk)
- Searching for "related" or "example" projects anywhere outside the current project root
- Using the workspace root or repository root as a starting point for searches unless it IS the project root

**There is no exception.** Not for gathering context. Not for finding examples. Not for understanding patterns. Not for "just a quick look". If information isn't in the current project or in this plugin's knowledge base, ask the user rather than searching the filesystem.

If you are about to form a path that goes above the current project directory — stop. Do not execute the tool call. Ask the user for the information instead.

---

## Interaction Protocol

### When a user wants to build something

**Collect before you research.** When a user describes an application they want to build, do not read examples, browse GitHub repos, or look up SDK patterns until you have confirmed all three of:

1. **App type** — CDN app or HTTP app (ask if not explicitly stated — use-case descriptions are NOT explicit)
2. **Language** — determined by type constraints (ask if multiple options exist for the confirmed type)
3. **Project name** — required before scaffolding

Only after all three are confirmed, use **parallel sub-agents** to research. Do not do sequential research in the main agent. Scope all research strictly to the confirmed type + language — do not read resources for types or languages that won't be used.

**What counts as explicit vs ambiguous:**
- Explicit: "I want a CDN filter", "HTTP app in TypeScript", "Proxy-WASM filter in Rust"
- Ambiguous (always ask): "gateway for CDN resources", "auth for CDN traffic", "edge middleware", "SAML at the edge", "protect my CDN"

### Scaffolding new projects — HARD CONSTRAINT

**Never manually create project files (package.json, tsconfig.json, src/index.ts, Cargo.toml, etc.) from scratch.** Always use the `/gcore-fastedge:scaffold` skill, which creates projects from **blueprint reference files** in `skills/scaffold/reference/`.

Blueprints contain real project structures, dependencies, and working code extracted from FastEdge SDK examples. The scaffold skill selects a base skeleton matching the app type + language and layers feature-specific blueprints on top based on what the user wants to build.

**Available base skeletons:** `http/base-ts.md` (TS/JS), `http/base-rust.md`, `cdn/base-rust.md`, `cdn/base-as.md`
**Available feature blueprints:** KV Store, A/B testing, fetch/HTTP calls, headers, geo-redirect (HTTP TS/JS); KV Store (HTTP Rust); JWT auth, geoblocking, body processing (CDN Rust)

Do not look for existing projects in the workspace to use as a template reference. Do not look at sibling folders to copy package.json or tsconfig.json structure. The blueprint files contain the correct structure — the scaffold skill reads them and creates the project.

After scaffolding, if the user's application requires non-trivial logic (auth, integrations, custom protocols), plan and write only the app-specific files on top of what the scaffold generated.

### When a user asks a question (not building)

Answer from this knowledge base and the SDK reference files directly. No research needed for factual questions about FastEdge APIs, error codes, or SDK usage.

---

## Platform Overview

Gcore FastEdge is a serverless edge computing platform that runs WebAssembly (Wasm) workloads on 210+ global Points of Presence (PoPs). Apps are compiled to Wasm and deployed instantly worldwide with sub-millisecond cold starts.

**Supported languages:** JavaScript/TypeScript, Rust, AssemblyScript
**Default framework (HTTP apps):** Hono (lightweight, edge-native, official FastEdge examples use it)

---

## Available Skills

### `/gcore-fastedge:scaffold` — Create New Projects
Blueprint-driven project creation with intent detection. Supports HTTP (JS/TS/Rust) and CDN (AS/Rust) apps. After scaffolding, offers to set up tests and debug fixtures independently.

### `/gcore-fastedge:deploy` — Build & Deploy
Build, test, and deploy to FastEdge. Uses the MCP server for builds and API operations when available, falls back to local toolchain with a warning if not. Pre-deploy test gate blocks broken deploys (override with `--skip-tests`).

### `/gcore-fastedge:manage` — Manage Apps
List, get, update, delete apps. Manage secrets and environment variables. Sync dotenv files to deployed apps (`sync-env <id> [--from <dir>] [--auto-apply]` — defaults to project root, tiered confirmation: additive auto-applies, destructive removals prompt with default-no). Uses MCP server for API operations where available.

### `/gcore-fastedge:test` — TDD & CI Tests
Generate, scaffold, or run test suites using `@gcoredev/fastedge-test`. Produces `tests/*.test.ts` with programmatic assertions for CI/CD. Headless: `npm test`.

### `/gcore-fastedge:debug` — Debug Fixtures
Generate `fixtures/` directory with scenario-specific `.test.json` configs for the visual debugger. Each fixture is a pre-configured request/response scenario. Interactive: `npm run debug`. Pass `--infer` to derive scenarios from source automatically; `--smoke-check` to validate generated fixtures load cleanly in the headless runner. Pre-flights existing fixtures: never silently overwrites hand-authored content — prompts with keep / replace / cancel options. Skips `package.json` mutation when project's `AGENTS.md` or `CLAUDE.md` contains a "never change code" rule (override with `--modify-project`; force off with `--no-modify-project`).

### `/gcore-fastedge:live-test` — Verify on the Edge
Build, deploy, and run scenario fixtures against the **deployed** app. HTTP apps test against their public URL; CDN apps wire to a preconfigured resource at `/livetest-<app>/`. Pairs each `*.test.json` with a sibling `*.live.json` (only an `expected` block) to assert pass/fail on observable HTTP and edge logs. Auto-syncs `fixtures/.env*` to the deployed app each run (delegates to `manage sync-env`) so env-driven apps work out of the box — pass `--from <dir>` to point at a variant subdir, `--no-env-sync` to skip. Persists rules between runs; pass `--cleanup` to disable when done.

### `/gcore-fastedge:fastedge-docs` — SDK Reference (Auto-triggered)
FastEdge expert for SDK usage, platform capabilities, error debugging, best practices. Auto-triggers when users ask about FastEdge. Not invoked via slash command.

---

## MCP Server Integration

The deploy and manage skills run through the **FastEdge MCP server**, which is the plugin's executor layer. Skills are the intelligence layer; the MCP server is how that intelligence gets executed. The plugin's bundled `.mcp.json` launches `ghcr.io/g-core/fastedge-mcp-server:latest` automatically — Docker is required.

A local-toolchain fallback exists for users who explicitly choose not to run Docker. Treat it as an opt-out, not a default. When falling back, warn the user that they're outside the supported path and proceed only on confirmation.

**What the MCP server provides:**
- `build-wasm` — Containerized WASM compilation (no local toolchain needed)
- `upload-binary` — Binary upload to FastEdge API
- `update-or-create-app` — App deployment and updates
- `update-env-vars-app` — Environment variable and secrets management
- `fastedge-docs` — Reference documentation search for non-Claude editors (Cursor, Codex, etc.)

---

## App Types — CDN vs HTTP

This is the most important distinction when creating a FastEdge application. The two app types run in fundamentally different environments and have different capabilities.

### HTTP Apps
Run as **standalone serverless functions**. They own the entire request/response cycle — the Wasm module receives an HTTP request and returns an HTTP response, just like a normal server endpoint.

**Use HTTP apps for:**
- APIs and API gateways
- Server-side rendering (React, Hono)
- Edge middleware with full request control
- MCP servers at the edge
- Anything that behaves like a web server endpoint

**Languages:** JavaScript, TypeScript, Rust
**ABI:** HTTP-WASM (HTTP handler interface)
**Templates:** `http-base`, `http-react`, `http-react-hono`

### CDN Apps
Run **inside the CDN proxy layer** using the Proxy-WASM ABI. These are HTTP filters — they intercept and modify traffic flowing through Gcore's CDN. The CDN handles the actual request/response; the Wasm module hooks into specific phases of that flow.

**Use CDN apps for:**
- Modifying request or response headers in flight
- Enforcing auth or rate limits at the CDN layer (before traffic reaches origin)
- URL rewriting and traffic routing logic
- Inspecting/transforming payloads for all CDN traffic
- Custom caching logic
- Bot detection and traffic filtering

**Languages:** AssemblyScript, Rust
**ABI:** Proxy-WASM (filter phase callbacks)
**Templates:** `cdn-base`

**Key difference:** CDN apps use a callback model — you implement methods like `onRequestHeaders`, `onResponseHeaders`, `onRequestBody`, etc. You don't "return a response"; you call `continue_request()` or `send_local_response()` to control flow.

### Decision Guide

| Question | Answer → |
|----------|----------|
| Do I need to build an API or web endpoint? | HTTP app |
| Do I need to modify traffic passing through the CDN? | CDN app |
| Do I need full control over the response body? | HTTP app |
| Do I want to intercept headers before they reach origin? | CDN app |
| Am I using JavaScript or TypeScript? | HTTP app (JS/TS not supported for CDN) |
| Am I writing something that behaves like a filter or plugin? | CDN app |

---

## Authentication

All API calls require `GCORE_API_KEY` environment variable.

```
Authorization: APIKey <GCORE_API_KEY>
```

Verify auth is set before any API operation:
```bash
if [ -z "$GCORE_API_KEY" ]; then
  echo "Error: GCORE_API_KEY environment variable is not set"
  echo "Get your API key from https://portal.gcore.com → API Keys"
  exit 1
fi
```

## API Endpoints

Base URL: `https://api.gcore.com/fastedge/v1`

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/binaries/raw` | Upload Wasm binary (Content-Type: application/octet-stream) |
| GET | `/apps` | List all apps |
| POST | `/apps` | Create new app |
| GET | `/apps/{id}` | Get app details |
| PUT | `/apps/{id}` | Update app |
| DELETE | `/apps/{id}` | Delete app |
| GET | `/apps/{id}/stats` | Get app statistics |
| GET | `/secrets` | List all secrets |
| GET | `/secrets/{id}` | Get secret details |

### Upload Binary
```bash
BINARY_ID=$(curl -s -X POST "https://api.gcore.com/fastedge/v1/binaries/raw" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @<path-to-wasm> | jq -r '.id')
```

### Create App
```bash
curl -s -X POST "https://api.gcore.com/fastedge/v1/apps" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<app-name>",
    "binary": <binary-id>,
    "status": 1,
    "env_vars": {}
  }'
```

### Update App
```bash
curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/<app-id>" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "binary": <new-binary-id> }'
```

### Secrets

Secrets are encrypted environment variables. They're referenced by ID when assigning to apps.

```bash
# List all secrets
curl -s "https://api.gcore.com/fastedge/v1/secrets" \
  -H "Authorization: APIKey $GCORE_API_KEY"
```

Response contains an array of secrets with `id` and `name` fields.

To assign secrets to an app, use the `secrets` field in the update payload:
```bash
curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/<app-id>" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "secrets": {"MY_SECRET": {"id": <secret-id>}},
    "rsp_headers": {"X-Custom-Header": "value"}
  }'
```

## Build Pipelines

### JavaScript/TypeScript (HTTP apps only)
```bash
fastedge-build ./src/index.js ./<project-name>.wasm
# Output: ./<project-name>.wasm (in project root)
```

Requires `@gcoredev/fastedge-sdk-js` as a dev dependency. The `fastedge-build` tool compiles JS → Wasm using ComponentizeJS.

### Rust (HTTP or CDN apps)
```bash
cargo build --release --target wasm32-wasip1
# Output: ./target/wasm32-wasip1/release/<crate-name>.wasm
```

Requires `.cargo/config.toml` with `[build] target = "wasm32-wasip1"`.

### AssemblyScript (CDN apps only)
```bash
npm run asbuild:release
# Output: build/release.wasm (as configured in asconfig.json)
```

Requires `@gcoredev/proxy-wasm-sdk-as` as a dependency and `assemblyscript` as a dev dependency. The `asc` compiler compiles AssemblyScript → Wasm using the Proxy-WASM ABI. Project is identified by the presence of `asconfig.json`.

## SDK Capabilities

### JavaScript SDK (`@gcoredev/fastedge-sdk-js`) — HTTP apps

```typescript
import { getEnv } from "fastedge::env";
import { getSecret } from "fastedge::secret";
import { KvStore } from "fastedge::kv";

// Environment variables (set via API or portal)
const value = getEnv("MY_VAR");

// Secrets (encrypted env vars)
const secret = getSecret("API_TOKEN");

// KV Store
const store = new KvStore("my-store");
await store.get("key");
await store.set("key", "value");

// Standard Web APIs available:
// fetch(), Request, Response, Headers, URL, TextEncoder/Decoder, crypto
```

### Rust SDK (`fastedge` crate) — HTTP apps

```rust
use fastedge::http::{Request, Response, StatusCode, Error};

#[fastedge::http]
fn main(req: Request<Vec<u8>>) -> Result<Response<Vec<u8>>, Error> {
    let body = format!("Hello from FastEdge! Path: {}", req.uri().path());
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "text/plain")
        .body(body.into_bytes())?)
}
```

### AssemblyScript SDK (`@gcoredev/proxy-wasm-sdk-as`) — CDN apps

CDN apps use a **callback/filter model**, not a request/response model. Implement a `Context` class and override phase callbacks:

```typescript
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
import {
  RootContext,
  Context,
  registerRootContext,
  FilterHeadersStatusValues,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import { getEnv } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
import { KvStore } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
import { getSecret } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

class MyRoot extends RootContext {
  createContext(context_id: u32): Context {
    return new MyFilter(context_id, this);
  }
}

class MyFilter extends Context {
  // Called when request headers arrive — modify before forwarding to origin
  onRequestHeaders(a: i32, end_of_stream: bool): FilterHeadersStatusValues {
    stream_context.headers.request.add("X-Custom", "value");
    return FilterHeadersStatusValues.Continue; // or StopIteration to block
  }

  // Called when response headers arrive — modify before sending to client
  onResponseHeaders(a: i32, end_of_stream: bool): FilterHeadersStatusValues {
    stream_context.headers.response.add("X-Powered-By", "FastEdge");
    return FilterHeadersStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => new MyRoot(context_id), "my-filter");
```

**FastEdge-specific APIs available in AssemblyScript CDN apps:**
```typescript
import { getEnv, getSecret, KvStore } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

// Environment variables
const val = getEnv("MY_VAR");

// Secrets
const token = getSecret("API_TOKEN");

// KV Store (read-only from CDN filter context)
const store = KvStore.open("my-store"); // returns KvStore | null
if (store) {
  const buf = store.get("key");          // returns ArrayBuffer | null
  const keys = store.scan("prefix*");   // returns Array<string>
}
```

**Flow control in CDN apps:**
- `FilterHeadersStatusValues.Continue` — pass headers to next filter/origin
- `FilterHeadersStatusValues.StopIteration` — pause processing (e.g. waiting for async)
- `stream_context.sendLocalResponse(403, "Forbidden", ...)` — short-circuit, return response directly without hitting origin

## Logging — Stdout Only (Rust Hazard)

FastEdge's log capture (visible via `GET /apps/{id}/logs`, the visual debugger, `@gcoredev/fastedge-test`, and `/gcore-fastedge:live-test`) reads from the WASM module's **stdout stream only**. Anything written to stderr is silently discarded — the log API returns it as `count=0`, indistinguishable from "no logs were emitted."

### Per-language status

| Language | Logging API | Stdout-safe? | Notes |
|----------|-------------|--------------|-------|
| JavaScript / TypeScript (HTTP) | `console.log` / `console.info` / `console.warn` / `console.error` / `console.debug` | ✅ All levels safe | The SDK's `console-override.cpp` builtin pipes every level through `fprintf(stdout, ...)`. Use any level freely. |
| AssemblyScript (CDN) | `log(LogLevelValues.X, msg)` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge` | ✅ Safe | SDK's `runtime.ts` writes via `process.stdout.write`. All levels (TRACE → CRITICAL) reach stdout. |
| **Rust (HTTP and CDN)** | `println!` / `print!` | ⚠ Manual responsibility | Rust does not have a FastEdge logging wrapper. The user picks the writer, and getting it wrong silently breaks all log-based observability. |

### Rust rules

**Use:** `println!(...)` and `print!(...)`. These macros write to `std::io::stdout()`, which the FastEdge runtime captures.

**Do not use:**
- `eprintln!(...)` / `eprint!(...)` — write to stderr, dropped by the runtime.
- `writeln!(std::io::stderr(), ...)` / any direct `std::io::stderr()` writer.
- `log` crate with `env_logger` default configuration — `env_logger` writes to stderr unless explicitly retargeted via `Builder::target(Target::Stdout)`.
- `tracing-subscriber` with a stderr writer (`fmt().with_writer(std::io::stderr)`). The default `tracing_subscriber::fmt()` writes to stdout and is safe, but explicit stderr overrides are not.
- `proxy_wasm::hostcalls::log(LogLevel::*, ...)` — routes through the proxy-wasm log hostcall ABI, which FastEdge does **not** capture. Despite the `LogLevel::Info` level, this produces `count=0` in the log API, indistinguishable from "no logs emitted." Use `println!(...)` instead for CDN Rust apps.

**Verification (local):** When in doubt, run the WASM locally:
```bash
fastedge-run http -w ./path/to/app.wasm --port 8080
# In another terminal:
curl http://localhost:8080/
```
If your log line does not appear in `fastedge-run`'s captured stdout output, it is going to stderr and will be invisible in production too. There is no FastEdge-specific magic — it's the same Unix file-descriptor distinction.

### Why this matters

The failure mode is silent and confusing. A Rust app with `eprintln!("Hello")` builds, deploys, and serves traffic correctly — but `/gcore-fastedge:live-test` will report log assertion failures, the visual debugger will show no log entries, and the `/apps/{id}/logs` API will return empty arrays. The natural debugging instinct (blame propagation, blame the test harness, blame the app initialization) wastes hours before someone checks which file descriptor the log macro writes to.

When debugging missing logs in a Rust FastEdge app, **always check for stderr-bound logging in the source first** before suspecting infrastructure.

## Error Codes

| Code | Meaning | Common Cause |
|------|---------|--------------|
| 530 | App initialization failed | Missing env vars, invalid Wasm binary |
| 531 | Runtime error | Unhandled exception in app code |
| 532 | Timeout | App exceeded execution time limit (typically 50ms for basic plan) |
| 533 | Memory limit exceeded | App exceeded memory limit (typically 128MB) |

## Local Testing

### Visual Debugger

`@gcoredev/fastedge-test` is a dual-mode package:

```bash
# Visual debugger mode (no args) — Express + React UI at http://localhost:5179
npm run debug                          # requires: "debug": "npx @gcoredev/fastedge-test" in package.json
npx @gcoredev/fastedge-test            # or directly

# Test runner mode (with test file) — runs suite, exits with pass/fail
npm test                               # requires: "test": "npx @gcoredev/fastedge-test ./tests/app.test.ts"
npx @gcoredev/fastedge-test ./tests/app.test.ts
```

**VSCode users:** The FastEdge extension bundles the same debugger server — use
`FastEdge: Debug Application` from the Command Palette (no Node.js required).

The debugger auto-loads `test-config.json` from the project root. Use `/gcore-fastedge:test`
to create it. Full details: `skills/test/reference/vscode-debugger.md`.

### Raw CLI runner

```bash
fastedge-run http -w <path-to-wasm> --port 8080
curl http://localhost:8080/
```

## App URL Pattern

Once deployed, apps are accessible at the URL returned by the API (in the `url` field of the response), typically:
```
https://<app-name>-<id>.fastedge.app
```
