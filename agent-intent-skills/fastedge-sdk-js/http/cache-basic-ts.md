# Synthesis Instructions: cache-basic-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/cache-basic-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [cache]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/cache-basic
```

## Example-specific extraction hints
- Extract the four flagship Cache primitives in a single router: `import { Cache } from "fastedge::cache"` with `Cache.set`, `Cache.get`, `Cache.exists`, `Cache.delete`
- Preserve the `?action=set|get|exists|delete&key=…&value=…` URL switch so the blueprint compiles as a single working app the user can curl against
- Highlight write options: `{ ttl: 60 }` (seconds), `{ ttlMs }` (sub-second), `{ expiresAt }` (fixed epoch deadline), and "omit options entirely for no expiry"
- On read, `Cache.get` returns a `CacheEntry` on hit or `null` on miss; decode via `entry.text()`, `entry.json()`, or `entry.arrayBuffer()` — show `entry.text()` in the blueprint
- Note that `Cache.delete` is a no-op when the key is absent (no error)
- Preserve the top-level `try/catch` in the handler — Cache validation errors throw synchronously, host errors arrive as Promise rejections; both must be caught
- Call out the POP-local data scope (writes from one POP not visible to others) so users understand when to reach for `fastedge::kv` instead
- If `.fastedge/build-config.js` exists, include it in Build Notes
- "When to Use" hint: user wants the simplest possible per-POP key/value store for short-lived state, hit counters, idempotency checks, or transient request-time caching without the operational overhead of the full Cache flagship patterns
