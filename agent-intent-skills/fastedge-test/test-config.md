# Synthesis Instructions: test-config.md

> For shared cross-referencing rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/test/reference/test-config.md`

## Audience
AI agents helping developers configure the `fastedge-config.test.json` file for their FastEdge app.

## Output goal
A complete schema reference for `fastedge-config.test.json`. Agents use this to generate correct config files and to explain each field to developers. Prioritise precision and completeness over brevity.

## Required sections (in this order)

1. **Purpose** — one sentence: what fastedge-config.test.json does and when it auto-loads (debugger + test framework)

2. **Schema** — every top-level field as a table: field | type | required | default | description. Include:
   - `$schema` — path to `./node_modules/@gcoredev/fastedge-test/schemas/fastedge-config.test.schema.json` for IDE validation
   - `description` — human label for this config
   - `wasm.path` — relative path to the compiled WASM binary
   - `wasm.description` — optional label
   - `request.method`, `request.url`, `request.headers`, `request.body`
   - `response.headers`, `response.body` — CDN-only; mock origin response headers and body
   - `properties` — CDN-only; key/value pairs for CDN property simulation (derive available keys from source)
   - `dotenvEnabled` — boolean, required, default `true`; whether to load `.env` files on server start
   - `logLevel` — numeric values 0–4 mapped to trace/debug/info/warn/error
   - Do NOT include `envVars` or `secrets` — these are not fields in the config file; they come from dotenv files only

3. **Runtime secrets and env vars** — one-line note that `envVars` and `secrets` are not config fields, with a reference to the dotenv configuration guide for the full dotenv setup. Do NOT inline dotenv details — prefix scheme, file options, and priority order all belong in the dotenv configuration guide.

4. **CDN example** — complete `fastedge-config.test.json` for a proxy-wasm app with realistic values; use `client.ip` (not `request.ip`) for the client IP property

5. **HTTP-WASM example** — complete `fastedge-config.test.json` for an HTTP-WASM app (no `properties`, `response`, or `dotenvEnabled` fields needed unless explicitly used)

6. **What to commit / gitignore** — commit `fastedge-config.test.json` and `.env.example`; gitignore `.env` and `.env.*` (except `.env.example`)

## What to exclude
- How to run tests (that belongs in the test framework reference)
- Debugger UI details such as how to open the debugger, what it shows, or its URL (that belongs in the VSCode debugger reference)
- Installation instructions
- History or changelog
- `envVars` or `secrets` as schema fields — these do not exist in the config file schema; all runtime values go through dotenv only
- Any exhaustive enumeration of available CDN property keys — the schema defines `properties` as a free-form object; only document property keys that are explicitly shown as examples in the source (e.g. `request.country`, `client.ip`)
- Any `enforceProductionPropertyRules` or similar enforcement flags — not present in the schema

## Quality bar
The existing file at `plugins/gcore-fastedge/skills/test/reference/test-config.md` sets the quality bar for depth and structure. Update field descriptions and examples to match the current package version — do not restructure unless the config schema has changed. **Do not preserve content from the current file that has no backing in the source files provided.** If a field, table, or note cannot be verified against the schema or documentation, omit it rather than carrying it forward.
