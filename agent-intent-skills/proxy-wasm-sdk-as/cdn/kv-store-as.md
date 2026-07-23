# Synthesis Instructions: kv-store-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/kv-store-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [kv-store]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/kvStore
```

## Example-specific extraction hints
- Extract `KvStore.open` / `get` / `scan` / `zrangeByScore` / `zscan` / `bfExists` patterns
- Note the `assembly/utils.ts` helper file — this is a new file this feature adds
- Show `ValueScoreTuple` type for sorted set results
- Show `ArrayBuffer` decoding patterns (KvStore.get returns `ArrayBuffer | null`)
- Import `KvStore` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`
- "When to Use" hint: user wants to query a key-value store for data lookups, sorted sets, bloom filters, or pattern scanning at the CDN layer
