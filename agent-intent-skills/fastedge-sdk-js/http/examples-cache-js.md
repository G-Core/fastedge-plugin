# Synthesis Instructions: examples-cache-js.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-cache-js.md`

## Example-specific extraction hints
- API focus: `import { Cache } from "fastedge::cache"` — static methods only, no instance to construct
  - `Cache.incr(key)` — atomic increment, returns the new count as a number; creates the key at 1 if missing
  - `Cache.expire(key, { ttl })` — attach/replace a TTL (seconds) on an existing key
  - `Cache.get(key)` — returns `CacheEntry | null`; read the body via `entry.arrayBuffer()`, `entry.text()`, or `entry.json()`
  - `Cache.set(key, value, { ttl })` — write bytes (`ArrayBuffer` / `Uint8Array`) or string; `ttl` is seconds
  - `Cache.getOrSet(key, populator, { ttl })` — returns `CacheEntry`; populator may be sync or async and returns the value to store
- Common patterns (pull verbatim or near-verbatim from the example):
  1. **Rate limiting** — `count = await Cache.incr(key); if (count === 1) await Cache.expire(key, { ttl })` — set the TTL only on the first hit so the window is anchored to that request, not refreshed on every call
  2. **Origin-cache proxy** — `Cache.get` → on miss `fetch` upstream, only `Cache.set` when `upstream.ok`; pass non-2xx and redirects through uncached so transient errors aren't pinned
  3. **Memoisation** — `Cache.getOrSet('key', () => JSON.stringify(expensive()), { ttl })` then `await entry.json()` to read structured data back
- Gotchas:
  - **Byte cache, not response cache** — only the body is stored. Status code, headers, and content-type are NOT preserved; cached replays must reconstruct them
  - **POP-local** — values do not replicate across data centers. Acceptable (and often desirable) for rate limiters, locks, and short-lived caches
  - **Strongly consistent within a POP** — `incr` is atomic under concurrent load, so it's safe for counters, quotas, and lock primitives where `fastedge::kv` would race
  - **`getOrSet` populator cannot signal "don't cache"** — every populator return value is stored. For conditional caching (e.g. only on HTTP 2xx) use manual `get` / `set` instead
  - **Validation errors throw synchronously**; host errors arrive as promise rejections — wrap call sites in a single `try/catch` that handles both
- Trusted client IP comes from `event.client.address` (set by the POP from `x-real-ip` / `x-forwarded-for`); safe to use as a rate-limit key
