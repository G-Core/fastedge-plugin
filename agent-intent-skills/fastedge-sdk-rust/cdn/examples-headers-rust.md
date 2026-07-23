# Synthesis Instructions: examples-headers-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-headers-rust.md`

## Example-specific extraction hints
- API focus: full proxy-wasm header manipulation API for both request and response:
  - `get_http_request_header(name)` / `get_http_request_header_bytes(name)` → `Option<String>` / `Option<Bytes>`
  - `get_http_request_headers()` / `get_http_request_headers_bytes()` → `Vec<(String, String)>` / `Vec<(String, Bytes)>`
  - `add_http_request_header(name, value)` — appends (allows duplicate names)
  - `set_http_request_header(name, Some(value))` — replaces existing value
  - `set_http_request_header(name, None)` — removes header
  - Equivalent `_response_` variants for response headers
- Show request-phase vs response-phase manipulation: request headers in `on_http_request_headers`, response headers in `on_http_response_headers`
- Common patterns: iterate headers with `get_http_request_headers()`, check presence with `get_http_request_header("host").is_none()`, add/replace/remove headers
- Show `_bytes` variants for binary header values
- Gotchas: removing a header with `set_...(name, None)` sets the value to an empty string rather than truly removing the header (FastEdge platform limitation — when checking for absence, test for both `None` and empty string), response headers set during request phase have limited availability, `add_` allows duplicate header names while `set_` replaces
