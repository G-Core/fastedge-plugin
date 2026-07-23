# Synthesis Instructions: examples-cors-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-cors-rust.md`

## Example-specific extraction hints
- API focus: `self.get_http_request_header("Origin")` for origin detection, `self.get_http_request_header(":method")` for preflight detection, `self.send_http_response(204, headers, None)` for preflight response, `self.add_http_response_header()` for CORS headers on normal responses
- Show origin validation pattern: compare against comma-separated `ALLOWED_ORIGINS` env var, support wildcard `"*"`
- Show preflight response headers: `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`, `Access-Control-Allow-Headers` (mirrored from request), `Access-Control-Max-Age`, `Content-Length: 0`
- Show `Vary: Origin` header — required when CORS response varies by origin, skip for wildcard
- Common patterns: check origin → validate → if OPTIONS respond with 204 and CORS headers; in response phase add `Access-Control-Allow-Origin` and `Access-Control-Expose-Headers`
- Gotchas: `ALLOWED_ORIGINS` is optional but required for the filter to do anything — when unset or empty the filter is dormant (requests pass through without CORS headers; browsers will block cross-origin access but the proxy does not reject), `Vary: Origin` is needed for shared cache correctness when not using wildcard, `Access-Control-Request-Headers` from preflight should be mirrored to `Access-Control-Allow-Headers`, env var configuration with sensible defaults
