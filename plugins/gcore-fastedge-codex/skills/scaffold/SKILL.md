---
name: scaffold
disable-model-invocation: false
argument-hint: "[http|cdn] [project-name] [description]"
description: Scaffold a FastEdge HTTP/CDN app from local blueprint references and indexed docs
---

# FastEdge Scaffold (Codex)

Scaffold new FastEdge projects with the same decision flow used in the Claude plugin: collect app type, language, and project name, then apply a base skeleton plus feature-specific additions.

## Scope Rules

Operate inside the target project/workspace only.

- Do not infer requirements from sibling repositories.
- Use local references and indexed docs as source-of-truth.
- If user intent is ambiguous, ask one concise clarifying question.

## Required Inputs

Collect and confirm before writing files:

1. App type:
- `HTTP` app: standalone endpoint/API
- `CDN` app: proxy-wasm traffic filter
2. Language (always ask if not explicitly stated — no silent defaults):
- HTTP: `typescript`, `javascript`, `rust` (list in this order; TypeScript is the most common but not assumed)
- CDN: `assemblyscript`, `rust`
3. Project name:
- lowercase, kebab-case preferred

## Intent Detection

If the initial request already includes behavior requirements (KV, JWT, geo, headers, fetch, etc.), reuse that intent directly.

Ask only if missing:

- "What does the app need to do beyond a base starter?"

If user says basic/starter-only, build base skeleton only.

## Local Reference Sources

Always consult docs index first, then targeted sections:

- `plugins/gcore-fastedge-codex/docs-index.json`
- `plugins/gcore-fastedge-codex/skills/scaffold/reference/*.md`
- `plugins/gcore-fastedge-codex/skills/fastedge-docs/reference/*.md`

Use section ranges (`line_start`, `line_end`) where available.

## Blueprint Selection

Select base skeleton by app type + language:

- HTTP TS/JS: `skills/scaffold/reference/http/base-ts.md`
- HTTP Rust: `skills/scaffold/reference/http/base-rust.md`
- CDN Rust: `skills/scaffold/reference/cdn/base-rust.md`
- CDN AssemblyScript: `skills/scaffold/reference/cdn/base-as.md`

Then match feature blueprints by:

1. `type == feature`
2. `app_type` compatibility
3. language compatibility
4. capability/tag match against user intent

If no feature blueprint matches:

- Scaffold base app
- Explain unsupported gap
- Suggest nearest supported path

## Assembly Flow

1. Create project directory.
2. Apply base skeleton files exactly.
3. Merge feature blueprint changes:
- dependencies
- new files
- file edits
4. Resolve collisions coherently (imports, middleware chains, versions).
5. Leave dependency install commands to the user (do not auto-install unless explicitly asked).

## Post-Scaffold Verification

Before returning:

1. Build script/command exists.
2. Output wasm path is explicit.
3. Entrypoint path is explicit.
4. No placeholder TODO-only files unless user asked for stubs.

## Rust Logging Self-Check (Rust projects only)

**Skip entirely for TypeScript, JavaScript, AssemblyScript.** Their SDKs route every logging API through stdout by construction (`console-override.cpp` in `@gcoredev/fastedge-sdk-js` → `fprintf(stdout, ...)`; `runtime.ts` in `@gcoredev/proxy-wasm-sdk-as` → `process.stdout.write`).

**Rust only.** FastEdge captures stdout only — stderr writes are silently dropped, producing empty `/apps/{id}/logs` responses indistinguishable from "no log calls." The agent may have improvised stderr-bound logging beyond what the blueprint specifies. Catch it before the project leaves this skill.

Procedure:

1. Glob `<project>/src/**/*.rs`.
2. Grep for: `\beprintln!`, `\beprint!`, `std::io::stderr\(\)`, `io::stderr\(\)`, `env_logger::(init|Builder::new)` without `Target::Stdout`, `with_writer\(\s*std::io::stderr`.
3. Action:
   - `eprintln!` → rewrite to `println!`. `eprint!` → `print!`. Mechanical, safe.
   - Direct `stderr()` / `env_logger` default / `tracing-subscriber` stderr override → surface to user with `file:line` and forbidden token; ask whether to remove or retarget. Do not silently rewrite (these often carry intent).
4. If anything was rewritten, append to completion output:
   ```
   ⚠ Rewrote N stderr log call(s) to stdout — FastEdge captures stdout only.
   ```

See `skills/scaffold/reference/http/base-rust.md` § Logging Convention and `skills/scaffold/reference/cdn/base-rust.md` § Logging Convention for the per-app-type ruleset. Downstream skills (`/gcore-fastedge:test`, `/gcore-fastedge:debug`, `/gcore-fastedge:live-test`, `/gcore-fastedge:deploy`) assume scaffolded code is stdout-clean.

## Completion Output

Return:

- Selected app type/language
- Applied base + feature blueprints
- Files created/updated summary
- Exact next commands

Example next commands:

```bash
cd <project-name>
npm install
npm run build
# then run local tests and deploy flows
```

For Rust:

```bash
cd <project-name>
cargo build --release --target wasm32-wasip1
```

Offer both follow-up actions independently:

1. test setup/execution
2. debug fixture generation

## Worked Examples

These anchor expected response shape and clarification behavior. Mirror the structure when handling real requests.

### Example 1 — HTTP TypeScript with KV store

**User prompt**: "scaffold an HTTP app called product-cache that reads from a KV store"

**Behavior**: App type is explicit (HTTP). Feature intent is explicit (KV). Language is NOT stated — ask:

> Which language? TypeScript, JavaScript, or Rust?

Assume user picks TypeScript. Then proceed to assembly.

- Base: `http/base-ts.md`
- Feature: `http/kv-store-ts.md`

**Completion output**:

```
FastEdge project "product-cache" created!  [HTTP / TypeScript]
Applied blueprints: base-ts, kv-store-ts

  cd product-cache
  npm install

  Build:
    npm run build

  Test locally:
    /gcore-fastedge:test product-cache

  Deploy:
    /gcore-fastedge:deploy product-cache
```

Then offer test setup and debug fixture generation as two independent yes/no prompts.

### Example 2 — CDN Rust with geoblocking

**User prompt**: "scaffold geo-router, a CDN filter that blocks DE traffic"

**Behavior**: App type explicit ("CDN filter"). Language unstated for CDN — ask: *"AssemblyScript or Rust?"* Assume user picks Rust.

- Base: `cdn/base-rust.md`
- Feature: `cdn/geoblock-rust.md`

**Completion output**:

```
FastEdge CDN project "geo-router" created!  [CDN / Rust]
Applied blueprints: base-rust, geoblock-rust

  cd geo-router

  Build:
    cargo build --release --target wasm32-wasip1

  Test locally:
    /gcore-fastedge:test geo-router

  Deploy:
    /gcore-fastedge:deploy geo-router

  Note: CDN apps use the Proxy-WASM filter model — implement
  on_http_request_headers, on_http_response_headers, etc.
```

### Example 3 — Degraded mode: ambiguous app type

**User prompt**: "scaffold an edge gateway for our API"

**Behavior**: "edge gateway" does NOT confirm app type — both HTTP and CDN can act as gateways. Do not assume. Do not begin research or blueprint selection.

Ask exactly:

> Are you building an **HTTP app** (standalone API/endpoint that owns the full request/response) or a **CDN app** (filter that intercepts traffic flowing through Gcore's CDN before it reaches origin)?

Only after the answer, collect language and project name, then proceed.
