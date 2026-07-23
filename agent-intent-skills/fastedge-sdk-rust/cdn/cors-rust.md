# Synthesis Instructions: cors-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/cors-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [cors, preflight]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/cors
```

## Example-specific extraction hints
- Extract CORS preflight handling in `on_http_request_headers`: detect `OPTIONS` method via `:method` pseudo-header, respond with `self.send_http_response(204, headers, None)` and `Action::Pause`
- Show origin validation: read `Origin` request header, check against `ALLOWED_ORIGINS` env var (comma-separated list or `"*"` for wildcard)
- Show preflight response headers: `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`, `Access-Control-Allow-Headers`, `Access-Control-Max-Age`, `Content-Length: 0`
- Show `Vary: Origin` header — needed when response varies by origin (not needed for wildcard `*`)
- Extract response-phase CORS headers in `on_http_response_headers`: add `Access-Control-Allow-Origin` and optional `Access-Control-Expose-Headers` to all non-preflight responses
- Show env var configuration: `ALLOWED_ORIGINS` (optional but required for the filter to do anything — when unset or empty the filter is dormant, requests pass through without CORS headers), `ALLOWED_METHODS` (optional, defaults), `MAX_AGE` (optional), `EXPOSE_HEADERS` (optional)
- Show `is_origin_allowed()` helper function pattern for origin matching
- CDN pattern: uses both `on_http_request_headers` (preflight) and `on_http_response_headers` (CORS headers on normal responses)
- "When to Use" hint: user wants to handle CORS preflight requests and add CORS response headers at the CDN layer
