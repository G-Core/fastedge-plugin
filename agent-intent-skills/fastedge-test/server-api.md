# Synthesis Instructions: server-api.md

> For shared cross-referencing rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/test/reference/server-api.md`

## Audience
AI agents building custom debugger tooling or integrating with the fastedge-test server programmatically.

## Source files
- `docs/API.md` — REST endpoint documentation
- `docs/WEBSOCKET.md` — WebSocket protocol documentation

## Output goal
A complete API reference for the debugger server's REST and WebSocket interfaces. Agents use this to make HTTP/WS calls to the running debugger server — not to write test files (that belongs in the test framework reference).

## Required sections (in this order)

1. **REST Endpoints** — for each endpoint: method, path, request body schema, response schema, and one-line description. Include all endpoints documented in the source.

2. **WebSocket Protocol** — connection URL, message format (JSON), event types, and payload schemas for each event type.

3. **Server startup** — how to start the server programmatically via `@gcoredev/fastedge-test/server` export, the default port (5179), port auto-increment behaviour (tries up to 10 sequential ports when the preferred port is busy), and the `.fastedge-debug/.debug-port` file that records the bound port at runtime.

## What to exclude
- Test framework API (`defineTestSuite`, `runAndExit`, etc.) — belongs in the test framework reference
- Config file schema — belongs in the test config reference
- Dotenv setup — belongs in the dotenv configuration guide
- VSCode extension details — belongs in the VSCode debugger reference
- Internal implementation details (Express middleware, React frontend)

## Quality bar
This is a new file. Generate clean, structured API documentation. Every endpoint and event type must have its schema documented.
