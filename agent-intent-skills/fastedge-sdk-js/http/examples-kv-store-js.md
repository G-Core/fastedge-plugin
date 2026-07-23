# Synthesis Instructions: examples-kv-store-js.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-kv-store-js.md`

## Example-specific extraction hints
- API focus: `import { KvStore } from "fastedge::kv"`, `KvStore.open(name)` (static factory, returns `KvStoreInstance`), `.get()`, `.scan()`, `.zrangeByScore()`, `.zscan()`, `.bfExists()`
- Use `KvStoreInstance` when referring to the type returned by `KvStore.open()` — this matches the `.d.ts` declarations
- Show return types and null handling — especially that `get()` returns `ArrayBuffer | null`, not a string
- Common patterns: open store + get with decode, prefix scan, error handling for missing keys, KV Store with request routing
- Gotchas: KV store is **read-only** from the app (no `set()`, `delete()`, or `list()`), data is written via the Gcore portal or API
