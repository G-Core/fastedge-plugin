# Synthesis Instructions: examples-api-wrapper-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-api-wrapper-basic-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::send_request(req)` for outbound HTTP, `Request::builder().uri().method().body()`, `fastedge::Error` enum variants (`UnsupportedMethod`, `BindgenHttpError`, `HttpError`, `InvalidBody`, `InvalidStatusCode`), automatic redirect following up to `MAX_REDIRECTS = 5`
- Common patterns: orchestrate multiple outbound calls (`get_device_status`, `send_device_command`) and combine results; read env vars with `env::var()` for `PASSWORD`, `DEVICE`, `TOKEN`; method guard at handler entry; `Authorization: Bearer <token>` header construction; JSON traversal with `serde_json::Value` chained `get()` + `ok_or()`
- Show env var config: `PASSWORD` (auth), `DEVICE` (SmartThings device ID), `TOKEN` (API bearer token)
- Gotchas: SmartThings JSON path `components.main.switch.switch.value` has `switch` twice — this is the actual schema; redirect helper resets method to GET on redirect; `fastedge::send_request` is synchronous (basic handler); `"ACCEPTED"` string from command result maps to `StatusCode::NO_CONTENT`
