# Synthesis Instructions: headers-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/headers-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [typescript, javascript]
capabilities: [headers]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/headers
```

## Example-specific extraction hints
- Extract Headers API usage: `get`, `set`, `append`, `delete`, `has`, iteration
- Show patterns for reading request headers and setting response headers
- "When to Use" hint: user wants to read, modify, or set custom request/response headers
