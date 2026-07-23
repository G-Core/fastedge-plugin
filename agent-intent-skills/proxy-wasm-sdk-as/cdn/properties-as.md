# Synthesis Instructions: properties-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/properties-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [request-properties, property-rewrite]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/properties
```

## Example-specific extraction hints
- Catalog the request property paths read in the example: `request.url`, `request.host`, `request.path`, `request.scheme`, `request.extension`, `request.query`, `request.x_real_ip`, `request.country`, `request.city`
- Show `get_property(name)` → `ArrayBuffer` decoding via `String.UTF8.decode`; check `byteLength === 0` for absent
- Show `set_property(name, String.UTF8.encode(value))` for rewriting `request.url`, `request.host`, `request.path` based on query parameters
- Show optional-vs-required property handling: `request.extension` and `request.query` may legitimately be empty and should not trigger error responses
- Show that each property surfaces both as a log line and as a corresponding `request-*` response header via `stream_context.headers.response.add`
- Promote helper to a class private method (no closures over mutable state, no default args on indirect calls)
- "When to Use" hint: user wants to read or rewrite per-request runtime properties (URL, host, path, country, client IP) at the CDN layer
