---
name: scaffold
disable-model-invocation: false
argument-hint: "[http|cdn] [project-name] [description of what it does]"
description: Scaffold a new FastEdge project from blueprints — tailored to your app's specific needs
---

# Scaffold a New FastEdge Project

Creates projects from blueprint reference files in `skills/scaffold/reference/`. Blueprints contain real project structures, dependencies, and working code extracted from FastEdge SDK examples. The agent selects a base skeleton matching the app type + language and layers feature-specific blueprints on top based on what the user wants to build.

## Scope Boundary — ABSOLUTE CONSTRAINT

**You operate exclusively inside the user's active project directory.**

Before every file read, glob, grep, or directory listing, verify the path stays inside the project root. If it does not, stop — do not execute the tool call.

Prohibited at all times, no exceptions:
- Any path containing `../`
- Listing or reading the parent directory of the project
- Reading sibling directories (other projects, nearby repos, example repos)
- Using the workspace root as a base for searches unless it IS the project root

**All information needed for scaffolding is in this skill file, the blueprint reference files, and the plugin knowledge base.** If you need to understand what to build — read the blueprints, not the filesystem. Ask the user if something is unclear.

---

## Step 1: Intake — Collect App Type, Language, and Project Name

**Before doing any research or reading blueprints, collect these three inputs. Do not read blueprint files or search documentation until all three are confirmed.**

This applies even when the user's description sounds like it implies a type — "gateway for CDN resources", "auth filter at the edge", "SAML for CDN" are all ambiguous. Do not assume. Ask.

### App Type (CDN vs HTTP)

**This is the most important decision.** The two app types run in completely different environments.

Always ask unless the user has used one of these exact phrases: "CDN app", "CDN filter", "Proxy-WASM", "HTTP app", "HTTP handler", or explicitly named a type. Descriptions of use cases — no matter how suggestive — require clarification.

**HTTP apps** run as standalone serverless functions — they receive an HTTP request and return an HTTP response, like a normal server endpoint. Use these for APIs, web apps, MCP servers, or edge middleware.
- Languages: **JavaScript, TypeScript, Rust**

**CDN apps** run as filters inside Gcore's CDN proxy layer. They intercept traffic flowing through the CDN and can modify requests/responses in flight — before requests reach origin and before responses reach clients. Use these for header manipulation, auth enforcement, URL rewriting, traffic filtering, and custom caching logic.
- Languages: **AssemblyScript, Rust**

Ask: **"Are you building an HTTP app (standalone API/endpoint) or a CDN app (traffic filter running inside the CDN proxy layer)?"** Include a one-sentence description of each to help the user decide.

### Language

**Always ask if the user hasn't explicitly stated a language.** No silent defaults — even when one language is more common, listing it first in the ask is enough; do not assume.

**For HTTP apps:** TypeScript, JavaScript, or Rust. List in this order — TypeScript is the most common choice on FastEdge HTTP but should not be picked without confirmation.

**For CDN apps:** AssemblyScript or Rust. AssemblyScript is TypeScript-like syntax; Rust gives more control.

### Project Name

Require a project name if not provided. Must be a valid package/crate name (lowercase, hyphens allowed).

---

## Step 2: Intent Detection — What Does This App Need to Do?

**Smart-skip rule**: If the user's original request already describes what the app should do (e.g., "create an HTTP app with KV Store", "build a CDN auth filter with JWT validation"), extract the feature intent directly — do NOT ask again.

**Only ask** when the initial request contains no feature intent (e.g., "scaffold an HTTP app called my-api" with no description of functionality):

Ask: **"What does this app need to do? For example: KV store access, A/B testing, auth/JWT validation, geolocation routing, upstream fetch calls, header manipulation — or just a basic starter?"**

**If the user says** "just a starter", "nothing special", "basic", or similar — skip directly to Step 4 with the base skeleton only. Do not ask further questions.

---

## Step 3: Blueprint Selection

Read the blueprint reference files from `skills/scaffold/reference/`. Each blueprint has YAML frontmatter with metadata.

### 3a. Select Base Skeleton

Find the base skeleton blueprint matching the confirmed app type and language:

| App Type | Language | Base Skeleton File |
|----------|----------|--------------------|
| HTTP | TypeScript / JavaScript | `http/base-ts.md` |
| HTTP | Rust | `http/base-rust.md` |
| CDN | Rust | `cdn/base-rust.md` |
| CDN | AssemblyScript | `cdn/base-as.md` |

The base skeleton provides: directory structure, package manifest, build configuration, entry point code.

### 3b. Match Feature Blueprints

If the user expressed feature intent in Step 2, search for matching feature blueprints:

1. Filter blueprints where `frontmatter.type == "feature"` AND `frontmatter.app_type` matches AND the user's language is in `frontmatter.languages`
2. Match `frontmatter.capabilities` keywords against the user's described intent
3. Select all matching feature blueprints

**Available feature blueprints** (capabilities → file):

| Capability | HTTP TS/JS | HTTP Rust | CDN Rust |
|------------|------------|-----------|----------|
| KV Store | `http/kv-store-ts.md` | `http/kv-store-rust.md` | — |
| A/B Testing | `http/ab-testing-ts.md` | — | — |
| Fetch / HTTP calls | `http/fetch-ts.md` | — | — |
| Headers / env vars | `http/headers-ts.md` | — | — |
| Geo-routing / redirect | `http/geo-redirect-ts.md` | — | `cdn/geoblock-rust.md` |
| Auth / JWT | — | — | `cdn/auth-jwt-rust.md` |

**If no feature blueprints match**: Inform the user that no specific feature blueprints are available for their described need, and offer to proceed with the base skeleton. The base skeleton + the shared knowledge base (CLAUDE.md) provide enough structural knowledge for the agent to help add custom logic after scaffolding.

**If the user's request matches a capability that has no blueprint for their language**: Inform them (e.g., "A/B testing blueprints are only available for TypeScript/JavaScript. I'll create the base skeleton and add A/B testing logic using the SDK reference.").

---

## AssemblyScript Constraint Gate (CDN / AssemblyScript only)

**If the confirmed app type is CDN and language is AssemblyScript, read `./reference/platform/as-constraints.md` now — before writing any code.**

AssemblyScript diverges from TypeScript in ways that produce wasm that traps at runtime or silently returns wrong values — with no compiler warning. The constraints cover: no `try/catch`, no closures over mutable state, explicit numeric types, `||` pointer-truthy semantics, nested-function default-param traps, array generic requirements, and more. This read is not optional. Do not proceed to Step 4 without it.

---

## Step 4: Project Assembly

### 4a. Create Project Directory

```
mkdir <project-name>
cd <project-name>
```

### 4b. Apply Base Skeleton

Read the selected base skeleton blueprint and create all files listed in its "Files" section:
- Create the directory structure
- Write each file with the exact content from the blueprint
- For TypeScript/JavaScript: if the user chose JavaScript, omit `tsconfig.json` and use `.js` file extensions instead of `.ts`

### 4c. Apply Feature Blueprints (if any)

For each matched feature blueprint, in order:

1. **Add dependencies**: Merge the blueprint's "Dependencies to Add" into the project's package manifest (package.json or Cargo.toml). Do not duplicate existing dependencies.

2. **Create new files**: Write any files listed in the blueprint's "Files to Create" section.

3. **Modify base files**: Apply changes from the blueprint's "Files to Modify" section — add imports, extend the entry point, insert middleware or handler logic. The blueprint specifies exactly what to add and where.

4. **Check for conflicts**: If two feature blueprints modify the same file, merge the changes coherently (e.g., combine imports, chain middleware). If dependencies conflict (incompatible versions), inform the user and ask which to prioritize.

### 4d. Finalize

- If the project has a `package.json`, do NOT run `npm install` automatically — let the user decide when to install dependencies
- Ensure all file paths are correct relative to the project root
- Verify no placeholder content remains — all files should have real, working code

### 4e. Rust Logging Self-Check (Rust projects only)

**Skip this step entirely for TypeScript, JavaScript, and AssemblyScript projects** — their SDKs route all logging APIs through stdout by construction (`console-override.cpp` in `@gcoredev/fastedge-sdk-js`; `process.stdout.write` in `@gcoredev/proxy-wasm-sdk-as`'s `runtime.ts`). There is nothing to check.

**For Rust projects only** (HTTP and CDN), the scaffold can introduce stderr-bound logging in two ways: (a) the agent may have improvised logging code beyond what the blueprint specifies, or (b) a feature blueprint may have been mis-applied. FastEdge's log capture reads stdout only — stderr writes are silently dropped and cause hours of confusing debugging downstream (`/gcore-fastedge:live-test` reports log assertion failures, the visual debugger shows empty log panes, the `/apps/{id}/logs` API returns `count=0`).

Run this check before printing next steps:

1. Glob all `.rs` files under the new project's `src/` directory.
2. Grep each file for forbidden tokens (Rust regex):
   - `\beprintln!` — stderr macro
   - `\beprint!` — stderr macro
   - `std::io::stderr\s*\(\s*\)` — direct stderr handle
   - `io::stderr\s*\(\s*\)` — direct stderr handle (when `std::io` is imported)
   - `env_logger::(init|Builder::new)` without a subsequent `Target::Stdout` — env_logger defaults to stderr
   - `with_writer\s*\(\s*std::io::stderr` — tracing-subscriber stderr override
   - `proxy_wasm::hostcalls::log\s*\(` / `hostcalls::log\s*\(` — proxy-wasm log hostcall; FastEdge does not capture hostcall-level logs; use `println!()` instead

3. If any match is found:
   - **Rewrite** `eprintln!` → `println!` and `eprint!` → `print!` (these are the agent's most common mistake — the rewrite is mechanical and safe).
   - For `proxy_wasm::hostcalls::log` calls, direct `stderr()` writers, `env_logger`, or `tracing-subscriber` stderr overrides: **do not auto-rewrite** — surface them to the user with the file path, line number, and the forbidden token, and ask whether to convert. `hostcalls::log` calls require extracting the format args manually; the typical fix is `println!(...)` with the same message.
   - After rewriting `eprintln!`/`eprint!`, print a one-line note in the scaffold summary:
     ```
     ⚠ Rewrote N stderr log call(s) to stdout — FastEdge captures stdout only.
     ```

4. If no matches are found, proceed silently.

**Rationale**: See `rules/fastedge-knowledge.mdc` § "Logging — Stdout Only (Rust Hazard)" and the `## Logging Convention` blocks in `scaffold/reference/http/base-rust.md` and `scaffold/reference/cdn/base-rust.md`. This self-check is the last line of defense before the project leaves the scaffold skill — every later skill (`/gcore-fastedge:debug`, `/gcore-fastedge:test`, `/gcore-fastedge:live-test`) will assume scaffolded code is stdout-clean.

---

## Step 5: Print Next Steps

After successful scaffolding, print a summary:

**HTTP apps (TypeScript/JavaScript):**

```
FastEdge project "<project-name>" created!  [HTTP / <language>]
<if feature blueprints applied: "Applied blueprints: <list>">

  cd <project-name>
  npm install

  Build:
    npm run build

  Test locally:
    /gcore-fastedge:test <project-name>

  Deploy:
    /gcore-fastedge:deploy <project-name>
```

**HTTP apps (Rust):**

```
FastEdge project "<project-name>" created!  [HTTP / Rust]
<if feature blueprints applied: "Applied blueprints: <list>">

  cd <project-name>

  Build:
    cargo build --release --target wasm32-wasip1

  Test locally:
    /gcore-fastedge:test <project-name>

  Deploy:
    /gcore-fastedge:deploy <project-name>
```

**CDN apps (Rust):**

```
FastEdge CDN project "<project-name>" created!  [CDN / Rust]
<if feature blueprints applied: "Applied blueprints: <list>">

  cd <project-name>

  Build:
    cargo build --release --target wasm32-wasip1

  Test locally:
    /gcore-fastedge:test <project-name>

  Deploy:
    /gcore-fastedge:deploy <project-name>

  Note: CDN apps use the Proxy-WASM filter model — implement on_http_request_headers,
  on_http_response_headers, etc. to intercept and modify CDN traffic.
```

**CDN apps (AssemblyScript):**

```
FastEdge CDN project "<project-name>" created!  [CDN / AssemblyScript]
<if feature blueprints applied: "Applied blueprints: <list>">

  cd <project-name>
  npm install

  Build:
    npm run asbuild:release

  Test locally:
    /gcore-fastedge:test <project-name>

  Deploy:
    /gcore-fastedge:deploy <project-name>

  Note: CDN apps use the Proxy-WASM filter model — implement onRequestHeaders,
  onResponseHeaders, etc. to intercept and modify CDN traffic.
```

After printing next steps, make two independent offers:

**Offer 1 — Tests (CI assertions):**
Ask: **"Would you like to set up tests for your new app? (recommended)"**
- If yes: invoke `/gcore-fastedge:test` in scaffold mode for the new project directory
- If no: mention they can run `/gcore-fastedge:test` later

**Offer 2 — Debug fixtures (local scenario testing):**
Ask: **"Would you like to set up debug fixtures for local testing?"**
- If yes: invoke `/gcore-fastedge:debug` for the new project directory
- If no: mention they can run `/gcore-fastedge:debug` later

The developer can accept both, one, or neither. Tests and debug fixtures are independent concerns:
- Tests (`tests/`) are programmatic CI assertions — pass/fail, run headless
- Debug fixtures (`fixtures/`) are scenario configs for the visual debugger — interactive, manual exploration

---

## Environment Variables and Secrets

Some feature blueprints require environment variables or secrets. If a feature blueprint has environment variable requirements noted in its "Build Notes" or "Files to Modify" sections, include them in the next steps output:

```
  Environment variables needed:
    <VAR_NAME> — <description>

  Set via API or portal before deploying. See /gcore-fastedge:manage for details.
```
