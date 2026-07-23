# Synthesis Instructions: geoblock-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/geoblock-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [geo-routing, geoblock]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/geoblock
```

## Example-specific extraction hints
- Extract geolocation detection (properties, headers via proxy-wasm)
- Show allow/deny list logic and how it's configured (env vars, hardcoded)
- CDN pattern: check in `on_http_request_headers`, `send_http_response` to block or `Action::Continue` to allow
- "When to Use" hint: user wants to block or allow traffic based on the client's country at the CDN layer
