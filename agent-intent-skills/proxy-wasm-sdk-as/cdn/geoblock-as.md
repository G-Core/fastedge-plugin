# Synthesis Instructions: geoblock-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/geoblock-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [geo-blocking]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/geoBlock
```

## Example-specific extraction hints
- Extract `getEnv` usage for reading blocklist configuration (e.g., `BLACKLIST` env var)
- Show `get_property("request.country")` for reading client country code
- Show `send_local_response` / `send_http_response` for blocking requests with 403
- Show string parsing pattern for comma-separated blocklist
- Import from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge` for `getEnv`
- "When to Use" hint: user wants to block or restrict access based on geographic location
