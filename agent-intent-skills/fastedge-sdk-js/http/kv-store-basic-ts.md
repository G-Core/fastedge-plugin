# Synthesis Instructions: kv-store-basic-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/kv-store-basic-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [kv-store]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/kv-store-basic
```

## Example-specific extraction hints
- Extract the minimal KV read pattern: `import { KvStore } from "fastedge::kv"`, `KvStore.open(name)`, and `await store.getEntry(key)`
- Highlight the entry-or-null contract: `getEntry` returns `null` on miss — show the explicit `if (entry === null)` 404 branch
- Show `await entry.text()` to decode the stored value
- Note that the store name (e.g. `'kv-store-name-as-defined-on-app'`) must match what was configured on the FastEdge app, not invented locally
- Preserve the top-level `try/catch` that returns a 500 JSON envelope for any unexpected host error
- If `.fastedge/build-config.js` exists, include it in Build Notes
- "When to Use" hint: user wants the simplest possible KV read against a pre-configured store — a single key lookup with miss handling, no write/update logic
