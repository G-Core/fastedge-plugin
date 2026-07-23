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

1. **Enabling dotenv** — two ways:
   - In `fastedge-config.test.json`: `"dotenvEnabled": true`
   - In `defineTestSuite`: `runnerConfig: { dotenvEnabled: true }`

2. **Prefix scheme** — table: prefix | type | how the app reads it. Include all four:
   - `FASTEDGE_VAR_ENV_` → environment variable
   - `FASTEDGE_VAR_SECRET_` → secret
   - `FASTEDGE_VAR_REQ_HEADER_` → request header
   - `FASTEDGE_VAR_RSP_HEADER_` → response header

3. **Option A — Single `.env` file** — example with all four prefix types, showing that the prefix is stripped before injection

4. **Option B — Type-split files** — list the four filenames (`.env.variables`, `.env.secrets`, `.env.req_headers`, `.env.rsp_headers`) and note that no prefix is needed

5. **Priority order** — ordered list (highest to lowest): Direct `RunnerConfig` values → `.env` → type-split files → `fastedge-config.test.json` fallback

6. **Gitignore guidance** — commit `.env.example`, gitignore `.env` and `.env.*` (except `.env.example`)

## What to exclude
- Config schema fields (belongs in the test config reference)
- Test framework API (belongs in the test framework reference)
- Debugger UI details (belongs in the VSCode debugger reference)
- `envVars` or `secrets` as config file fields — these do not exist in the schema

## Quality bar
The existing file at `plugins/gcore-fastedge/skills/test/reference/dotenv.md` sets the quality bar. Keep it concise — this is extracted content, not a tutorial.
