# Synthesis Instructions: ab-testing-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/ab-testing-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [typescript, javascript]
capabilities: [ab-testing]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/ab-testing
```

## Example-specific extraction hints
- Extract variant selection logic (cookie-based, random assignment)
- Show how response varies by variant and cookie setting for persistence
- "When to Use" hint: user wants to split traffic between variants, run experiments, or serve different content based on assignment
