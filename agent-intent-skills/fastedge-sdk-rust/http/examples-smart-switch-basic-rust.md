# Synthesis Instructions: examples-smart-switch-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-smart-switch-basic-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::send_request` for chained GET → POST outbound calls, `Request::builder()` with `header::AUTHORIZATION`, `header::ACCEPT`, `header::CONTENT_TYPE`, `header::PRAGMA`, JSON traversal with `serde_json::Value` chained `get()` + `ok_or(StatusCode)`; manual redirect following via `request_inner(req, depth)`
- Common patterns: read-modify-write device toggle flow — `get_device_status` (GET + JSON parse) → invert `"on"`/`"off"` → `send_device_command` (POST + JSON parse); `Authorization: Bearer <token>` header from env var; match on `"ACCEPTED"` string in command result to decide final status code
- Show env var config: `PASSWORD` (simple bearer auth), `DEVICE` (SmartThings device ID), `TOKEN` (API bearer token)
- Gotchas: SmartThings JSON path `components.main.switch.switch.value` has `switch` nested twice — this is correct per the API schema; redirect helper (`request_inner`) switches to GET on redirect; `fastedge::send_request` errors map to `StatusCode` not `anyhow::Error`; `"ACCEPTED"` → `StatusCode::NO_CONTENT`, anything else → `StatusCode::NOT_FOUND`
