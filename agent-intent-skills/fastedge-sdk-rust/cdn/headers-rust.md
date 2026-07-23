# Synthesis Instructions: headers-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/headers-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [header-manipulation]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/headers
```

## Example-specific extraction hints
- Extract all header manipulation methods:
  - `self.get_http_request_header(name)` / `self.get_http_request_header_bytes(name)` — returns `Option<String>` / `Option<Bytes>`
  - `self.get_http_request_headers()` / `self.get_http_request_headers_bytes()` — returns `Vec<(String, String)>` / `Vec<(String, Bytes)>`
  - `self.add_http_request_header(name, value)` / `self.add_http_request_header_bytes(name, value)` — adds a header (allows duplicates)
  - `self.set_http_request_header(name, Some(value))` — replaces header value
  - `self.set_http_request_header(name, None)` — removes header (FastEdge platform limitation: sets the value to an empty string rather than truly removing the header; when checking for absence, test for both `None` and empty string)
- Show equivalent response header methods: `get_http_response_header`, `add_http_response_header`, `set_http_response_header`, etc.
- Show both request-phase (`on_http_request_headers`) and response-phase (`on_http_response_headers`) header manipulation
- Note that response headers set during `on_http_request_headers` are available but limited — full response headers require `on_http_response_headers`
- "When to Use" hint: user wants to add, remove, replace, or inspect HTTP request and response headers at the CDN layer
