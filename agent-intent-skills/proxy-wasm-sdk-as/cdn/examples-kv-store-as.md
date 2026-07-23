# Synthesis Instructions: examples-kv-store-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-kv-store-as.md`

## Example-specific extraction hints
- API focus: `KvStore.open`, `get`, `scan`, `zrangeByScore`, `zscan`, `bfExists`
- Show `ValueScoreTuple` type structure for sorted set results
- Show `ArrayBuffer` decoding patterns for `get` (returns `ArrayBuffer | null`)
- Show `scan` returning `string[]` for key listing
- Show the utils.ts helper pattern for response formatting
- Gotchas: `get` returns null for missing keys (not an error), `open` takes a store name, all operations happen within lifecycle hooks
