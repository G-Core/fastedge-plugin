# Synthesis Instructions: headers-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/headers-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [header-manipulation]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/headers
```

## Example-specific extraction hints
- Extract `stream_context.headers.request` and `stream_context.headers.response` manipulation patterns
- Show all header operations: `add`, `replace`, `remove`, `get`, `get_headers`
- Show both request-phase and response-phase header manipulation
- Note lifecycle constraint: response headers are only available in `onResponseHeaders` / `onResponseBody`
- Show header validation pattern (checking if a header exists before replacing)
- "When to Use" hint: user wants to add, remove, or modify HTTP headers on requests or responses at the CDN layer
