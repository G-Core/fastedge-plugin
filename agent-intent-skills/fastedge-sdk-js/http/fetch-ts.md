# Synthesis Instructions: fetch-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/fetch-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [typescript, javascript]
capabilities: [fetch]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/downstream-fetch
```

## Example-specific extraction hints
- Extract `fetch()` usage pattern — URL construction, headers, response handling
- Show error handling for failed fetch calls
- "When to Use" hint: user wants to make outbound HTTP requests to external APIs or services from the edge
