# Synthesis Instructions: kv-store-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/kv-store-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [typescript, javascript]
capabilities: [kv-store]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/kv-store
```

## Example-specific extraction hints
- Extract KV Store API usage: `import { KvStore } from "fastedge::kv"`, `new KvStore(name)`, `get()`, `set()`
- Include complete content of utility modules (e.g., `utils.ts`)
- If `.fastedge/build-config.js` exists, include it in Build Notes
- "When to Use" hint: user wants to store/retrieve data using a key-value store at the edge
