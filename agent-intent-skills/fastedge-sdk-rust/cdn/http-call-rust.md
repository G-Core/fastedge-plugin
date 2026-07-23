# Synthesis Instructions: http-call-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/http-call-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [http-call, async-dispatch]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/http_call
```

## Example-specific extraction hints
- Extract `self.dispatch_http_call()` pattern — takes upstream name, headers (pseudo-headers `:scheme`, `:authority`, `:path` plus custom), optional body, trailers, and `Duration` timeout. Include `use std::time::Duration;` in the imports — this is the one import not covered by the proxy-wasm glob imports and must be shown explicitly
- Show the async callback pattern: `Action::Pause` in `on_http_request_headers`, then `Context::on_http_call_response` fires with `token_id`, `num_headers`, `body_size`, `num_trailers`
- Show response reading: `self.get_http_call_response_header()`, `self.get_http_call_response_headers()`, `self.get_http_call_response_body(0, body_size)`
- Show `self.resume_http_request()` to continue the original request after the HTTP call completes
- Show `self.reset_http_request()` for error cases (when `num_headers == 0`, the call failed)
- Show state tracking via struct field (e.g., `state: u32`) to distinguish first request from resumed request
- Show `Status` to HTTP status code mapping for error responses
- "When to Use" hint: user wants to make async outbound HTTP calls to external services from a CDN filter
