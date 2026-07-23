# Synthesis Instructions: cache-control-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/cache-control-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [cache-control, caching]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/cache_control
```

## Example-specific extraction hints
- Extract response status detection: `self.get_property(vec!["response.status"])` returns 2-byte big-endian `u16` — decode with `u16::from_be_bytes([bytes[0], bytes[1]])`
- Show content-type-aware caching rules: `self.get_http_response_header("Content-Type")` to determine asset category
- Show caching tiers: static assets (image/*, font/*, .js, .css, .wasm) → `public, max-age=<STATIC_MAX_AGE>, immutable`; HTML → `public, max-age=<HTML_MAX_AGE>, must-revalidate`; JSON/XML APIs → `no-cache` or `private, max-age=<API_MAX_AGE>`; errors (4xx/5xx) → `no-store`
- Show `Vary` header addition: `Accept-Encoding` for HTML, `Accept, Authorization` for API responses
- Show env var configuration with defaults: `STATIC_MAX_AGE` (31536000), `HTML_MAX_AGE` (3600), `API_MAX_AGE` (0)
- Show `is_static_asset()` helper function for content-type matching
- CDN pattern: all logic in `on_http_response_headers` — set `Cache-Control` and `Vary` headers based on content type and status
- "When to Use" hint: user wants to set content-type-aware Cache-Control headers on responses at the CDN layer
