# Synthesis Instructions: dotenv.md

> For shared cross-referencing rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/test/reference/dotenv.md`

## Audience
AI agents helping developers configure runtime secrets, env vars, and headers for local testing and debugging of FastEdge applications.

## Source file
`docs/TEST_CONFIG.md` — extract only the dotenv mechanism. Do NOT include the config schema or field reference (that belongs in the test config reference).

## Output goal
A single, authoritative reference for the dotenv injection mechanism. This file is cross-referenced from the test framework, test config, and VSCode debugger references — it must be self-contained for dotenv topics.

## Required sections (in this order)

1. **Enabling dotenv** — two ways, both using a `dotenv` object (there is no `dotenvEnabled` field):
   - In `fastedge-config.test.json`: `"dotenv": { "enabled": true, "path": "./fixtures" }`
   - In `defineTestSuite`: `runnerConfig: { dotenv: { enabled: true, path: "./fixtures" } }`
   - `enabled` defaults to `false`. `path` is a **directory** holding the dotenv files, not a file. When it is omitted, the process current working directory is used. In the config file, a relative path is resolved against the config file's directory.

2. **Prefix scheme** — table: prefix | type | how the app reads it | app types:
   - `FASTEDGE_VAR_ENV_` → environment variable (CDN and HTTP-WASM)
   - `FASTEDGE_VAR_SECRET_` → secret (CDN and HTTP-WASM)
   - `FASTEDGE_VAR_REQ_HEADER_` → request header (HTTP-WASM only)
   - `FASTEDGE_VAR_RSP_HEADER_` → response header (HTTP-WASM only)

3. **Option A — Single `.env` file** — example with the prefix types, showing that the prefix is stripped before injection; mark the header lines HTTP-WASM only

4. **Option B — Type-split files** — `.env.variables` and `.env.secrets` (CDN and HTTP-WASM); `.env.req_headers` and `.env.rsp_headers` (HTTP-WASM only). No prefix needed

5. **Key rules** — the same for CDN and HTTP-WASM apps (the CDN runner matches `fastedge-run`):
   - An unprefixed key in `.env` is an env var
   - `FASTEDGE_VAR_` keys inside `.env.variables` / `.env.secrets` are skipped
   - Same key in `.env` and a type-split file: `.env` wins
   - Do not invent other priority levels: there is no `RunnerConfig` env-var field and no `fastedge-config.test.json` fallback

6. **Gitignore guidance** — commit `.env.example`, gitignore `.env` and `.env.*` (except `.env.example`)

## What to exclude
- Config schema fields (belongs in the test config reference)
- Test framework API (belongs in the test framework reference)
- Debugger UI details (belongs in the VSCode debugger reference)
- `envVars` or `secrets` as config file fields — these do not exist in the schema

## Quality bar
The existing file at `plugins/gcore-fastedge/skills/test/reference/dotenv.md` sets the quality bar. Keep it concise — this is extracted content, not a tutorial.
