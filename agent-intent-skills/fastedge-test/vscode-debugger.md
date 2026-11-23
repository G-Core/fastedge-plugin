# Synthesis Instructions: vscode-debugger.md

> For shared cross-referencing rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/test/reference/vscode-debugger.md`

## Audience
AI agents helping developers launch and use the FastEdge visual debugger (interactive WASM debugging in a browser UI).

## Output goal
A practical usage guide. Agents use this to walk developers through launching the debugger, providing secrets, and understanding what the UI shows. Focus on what a developer does — not how the debugger is built.

## Required sections (in this order)

1. **Two ways to launch** — side by side:
   - VSCode Extension: command name (`FastEdge: Debug Application`), prerequisites (extension installed), what happens (bundled server starts, browser opens)
   - npm / any editor: exact `npx @gcoredev/fastedge-test` command, prerequisite (Node.js), what happens

2. **Dual-mode behaviour** — `npx @gcoredev/fastedge-test` has two modes:
   - No argument → visual debugger UI at `http://localhost:5179` (if port 5179 is busy, the server tries up to 50 sequential ports (5179–5228); `PORT` only sets the starting port; the bound port is written to `.fastedge-debug/.debug-port` and deleted on shutdown)
   - Headless test runner → programmatic only: import `@gcoredev/fastedge-test/test` and call `runAndExit(defineTestSuite(...))` — there is no CLI arg mode for running tests
   - Include the exact invocation for each mode

3. **Providing secrets and environment variables** — one-line note that secrets/env vars are not config fields, with a reference to the dotenv configuration guide for the full dotenv setup. Do NOT inline dotenv details — prefix scheme, file options, priority order, and gitignore guidance all belong in the dotenv configuration guide.

4. **What the UI shows** — brief list of panels so agents can describe the debugger to developers (the source covers the UI in one paragraph; this list is the backing):
   - Request bar and panel: method, URL, headers (tick a row to send it), body
   - Dotenv: loads env vars and secrets from `.env` files; off by default
   - Request Context: client and edge location (the edge dc is also the cache bucket), origin (CDN only), explicit properties (CDN only)
   - Logging: filterable by level (trace/debug/info/warn/error/critical); CDN apps get a tab per hook (onRequestHeaders, onRequestBody, onResponseHeaders, onResponseBody) with Logs, Storage, Inputs (headers, body, properties before the hook) and Outputs (what it changed); HTTP apps have Logs and Storage only
   - Storage: cache and Edge KV as the app sees them, pausable clock, reset
   - Response: status, content type, body, headers, preview for HTML and images

5. **What to commit / gitignore** — what is safe to commit (`fastedge-config.test.json` with placeholder values, `.env.example`) vs what must be ignored (`.env`, `.env.secrets`, `.env.variables`, etc.)

## What to exclude
- Bundling details or how the VSCode extension packages the server
- Port scanning / server identity logic (implementation detail)
- Architecture of the Express server or React frontend
- How to write test files (that belongs in the test framework reference)
- VSCode command names beyond `FastEdge: Debug Application` — do not invent additional command names unless they appear verbatim in the source files provided
- Any "Advising users" or workflow guidance sections — this is a reference document, not a runbook
- Application-type-specific debugging guidance (e.g. SAML, OAuth, geo-filtering) — the debugger is generic; app-specific guidance belongs in other docs
- `launch.json` in the variable priority hierarchy — there is no `launch.json` integration in this system
- `envVars` or `secrets` as fields shown inside `fastedge-config.test.json` examples — these are not config file fields; all runtime injection goes through dotenv only

## Quality bar
The existing file at `plugins/gcore-fastedge/skills/test/reference/vscode-debugger.md` sets the quality bar for depth and structure. Update launch commands and dotenv prefix list to match the current package version — do not restructure unless the debugger interface has changed. **Do not preserve content from the current file that has no backing in the source files provided.** If a section, command name, or note cannot be verified against the provided sources, omit it rather than carrying it forward.
