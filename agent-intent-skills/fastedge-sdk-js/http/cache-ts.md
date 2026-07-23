# Synthesis Instructions: cache-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/cache-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [typescript, javascript]
capabilities: [cache]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/cache
```

## Example-specific extraction hints
- Extract Cache API usage: `import { Cache } from "fastedge::cache"`, and the methods `Cache.incr`, `Cache.expire`, `Cache.get`, `Cache.set`, `Cache.getOrSet`
- The example demonstrates three flagship patterns that should each appear in the blueprint as named, copy-pastable handlers:
  1. **Per-IP rate limiting** — atomic `incr` + `expire` on first hit, keyed by `event.client.address`
  2. **Origin-cache proxy** — manual `get` / `set` with `{ ttl }`, only caching successful (`upstream.ok`) responses; cached entries are byte payloads read via `entry.arrayBuffer()`
  3. **JSON memoisation** — `getOrSet(key, populator, { ttl })` with a string-returning populator and `entry.json()` on read
- Preserve the router pattern (`url.searchParams.get('action')` → switch over `rate-limit`, `proxy`, `memo`) so the blueprint compiles as a single working app
- Preserve the top-level `try/catch` in the event handler — Cache validation errors throw synchronously, host errors arrive as rejections; both must be caught
- If `.fastedge/build-config.js` exists, include it in Build Notes
- "When to Use" hint: user wants POP-local, strongly-consistent caching for rate limiting, atomic counters, origin-response caching, or memoising expensive computations at the edge
