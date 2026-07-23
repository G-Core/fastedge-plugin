# Synthesis Instructions: geo-redirect-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/geo-redirect-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [typescript, javascript]
capabilities: [geo-routing]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/geo-redirect
```

## Example-specific extraction hints
- Extract geolocation detection pattern (how client location is determined — headers, ClientInfo)
- Show redirect/routing logic based on location
- Include environment variable usage for configurable country-to-URL mappings
- "When to Use" hint: user wants to redirect or route traffic based on the client's geographic location
