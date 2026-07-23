# Synthesis Instructions: geo-redirect-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/geo-redirect-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [geo-routing, redirect]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/geoRedirect
```

## Example-specific extraction hints
- Extract `get_property("request.country")` and `get_property("request.host")` / `request.path` for building the target URL — all return `ArrayBuffer` that must be decoded with `String.UTF8.decode`
- Show country-keyed origin lookup pattern: `getEnv(countryCode)` returning the per-country origin, with `getEnv("DEFAULT")` as fallback (empty-string check, not null)
- Show URL rewrite via `set_property("request.url", String.UTF8.encode(newUrl))` — this redirects the upstream fetch, not a 3xx browser redirect
- Show trailing-slash normalization on the origin before concatenating with the path
- Show error responses via `send_http_response` (500 for missing DEFAULT, 502 for missing country)
- Import `getEnv` and `setLogLevel` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`; `get_property`, `set_property`, `send_http_response` from `@gcoredev/proxy-wasm-sdk-as/assembly`
- "When to Use" hint: user wants to route traffic to a different origin based on the client's country code at the CDN layer
