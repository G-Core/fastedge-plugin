<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: 81145a9a43ec499240c687bd49376ab20c72b11c
      updated: 2026-08-17
-->

---
type: feature
app_type: http
languages: [typescript, javascript]
capabilities: [cache]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/cache
---

# Cache Patterns — TypeScript/JavaScript

Feature blueprint for POP-local, strongly-consistent caching. Provides three ready-to-use handler patterns: per-IP rate limiting (atomic counters), origin-cache proxy (conditional byte caching), and JSON memoisation (computed-value caching).

## When to Use

- Rate limiting or quota enforcement per client IP using atomic counters
- Caching upstream origin responses at the edge with conditional (success-only) storage
- Memoising expensive computations (CPU-bound or slow-changing data) across requests within a POP
- Any use case requiring strongly-consistent atomic increments (not available in `fastedge::kv`)

## Cache API Reference

### Import

```typescript
import { Cache } from 'fastedge::cache';
```

### Methods

#### `Cache.incr(key: string): Promise<number>`

Atomically increments the integer counter stored at `key` by 1. Creates the key with value `1` if it does not exist. Returns the new counter value after increment. Atomic under concurrent load — two simultaneous calls cannot both observe the same initial value.

#### `Cache.expire(key: string, options: { ttl: number }): Promise<void>`

Sets a TTL (time-to-live) in seconds on an existing key. The key is deleted after `ttl` seconds. Has no effect if the key does not exist. Use on first `incr` hit only (when count === 1) to avoid extending the window on each request.

#### `Cache.get(key: string): Promise<CacheEntry | null>`

Returns a `CacheEntry` if the key exists, or `null` on a cache miss.

**`CacheEntry` read methods:**
- `entry.arrayBuffer(): Promise<ArrayBuffer>` — raw bytes
- `entry.text(): Promise<string>` — UTF-8 decoded string
- `entry.json(): Promise<unknown>` — parses stored UTF-8 bytes as JSON

#### `Cache.set(key: string, value: ArrayBuffer | string, options?: { ttl?: number }): Promise<void>`

Stores `value` at `key`. Optional `ttl` in seconds. Overwrites any existing entry. The byte cache does not preserve HTTP status codes or headers — only the raw payload is stored.

#### `Cache.getOrSet(key: string, populator: () => string | Promise<string>, options?: { ttl?: number }): Promise<CacheEntry>`

Returns the cached entry if it exists. On a miss, calls `populator()`, stores its return value, and returns a `CacheEntry` for the newly stored value. The populator may be synchronous or async. Always returns a `CacheEntry` — use `entry.json()`, `entry.text()`, or `entry.arrayBuffer()` to read the value. The populator cannot signal "do not cache" — use manual `get`/`set` when caching must be conditional on the populator result.

### Cache Semantics

- **Strongly consistent within a POP** — `incr` is atomic; concurrent requests see correct, non-duplicated counts.
- **POP-local** — values do not replicate across data centers. Suitable for transient state (rate counters, short-lived memos).
- **Sub-millisecond reads and writes** on the hot path.
- Cache errors (e.g. conflicting `WriteOptions`) throw synchronously. Host errors arrive as Promise rejections. Both must be caught in the event handler.

---

## Pattern 1 — Per-IP Rate Limiting

```typescript
import { Cache } from 'fastedge::cache';

const RATE_LIMIT_MAX = 10;       // Requests per window
const RATE_LIMIT_WINDOW_S = 60;  // Window length, seconds

async function rateLimit(event: FetchEvent): Promise<Response> {
  // event.client.address is the trusted-edge client IP.
  // Set by the FastEdge POP from x-real-ip (fallback: x-forwarded-for).
  const ip = event.client.address || 'unknown';
  const key = `rl:${ip}`;

  const count = await Cache.incr(key);

  // Set TTL only on the first hit to anchor the fixed window.
  // Setting it on every request would push the deadline out indefinitely.
  if (count === 1) {
    await Cache.expire(key, { ttl: RATE_LIMIT_WINDOW_S });
  }

  if (count > RATE_LIMIT_MAX) {
    return Response.json(
      { error: 'Too Many Requests', limit: RATE_LIMIT_MAX, count },
      { status: 429, headers: { 'retry-after': String(RATE_LIMIT_WINDOW_S) } },
    );
  }

  return Response.json({
    pattern: 'rate-limit',
    ip,
    count,
    remaining: RATE_LIMIT_MAX - count,
    windowSeconds: RATE_LIMIT_WINDOW_S,
  });
}
```

**Key constraints:**
- Window is fixed, anchored to the *first* request in the window — not a sliding window.
- `incr` atomicity ensures no double-counting under concurrent load.
- `expire` is called only when `count === 1`. Multiple callers cannot both see `count === 1` due to atomicity.

---

## Pattern 2 — Origin-Cache Proxy

```typescript
import { Cache } from 'fastedge::cache';

const PROXY_TTL_S = 30;

async function proxy(url: string): Promise<Response> {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return Response.json({ error: `Invalid url: "${url}"` }, { status: 400 });
  }

  // Strip fragment: fetch() never sends it to the origin.
  // https://example.com/#a and #b must share one cache entry.
  parsed.hash = '';

  const key = `proxy:${parsed.toString()}`;

  // Cache hit — replay bytes as 200 OK.
  // Status and headers from the original response are NOT preserved.
  const cached = await Cache.get(key);
  if (cached !== null) {
    return new Response(await cached.arrayBuffer(), {
      headers: {
        'content-type': 'application/octet-stream',
        'x-cache': 'hit',
        'x-cache-ttl': String(PROXY_TTL_S),
      },
    });
  }

  // Cache miss — only cache successful (2xx) responses.
  // Non-2xx and redirects pass through unchanged.
  const upstream = await fetch(parsed.toString());
  if (!upstream.ok) {
    return upstream;
  }

  const bytes = await upstream.arrayBuffer();
  await Cache.set(key, bytes, { ttl: PROXY_TTL_S });
  return new Response(bytes, {
    headers: {
      'content-type': 'application/octet-stream',
      'x-cache': 'miss',
      'x-cache-ttl': String(PROXY_TTL_S),
    },
  });
}
```

**Key constraints:**
- Only `upstream.ok` (HTTP 2xx) responses are cached. Transient errors (404, 500) are not pinned.
- `getOrSet` is not used here because its populator cannot signal "fetched, but do not cache."
- Cached entries are raw bytes — no HTTP status or headers stored. Replayed as `200 OK` with `application/octet-stream`.
- Fragment (`#...`) is stripped from the cache key before use as a URL.

---

## Pattern 3 — JSON Memoisation

```typescript
import { Cache } from 'fastedge::cache';

const MEMO_TTL_S = 60;

async function memo(): Promise<Response> {
  const entry = await Cache.getOrSet(
    'memo:report',
    () => {
      // Replace with the actual expensive computation.
      const report = {
        generatedAt: new Date().toISOString(),
        topItems: ['alpha', 'beta', 'gamma'].map((name, i) => ({
          name,
          score: Math.round(Math.random() * 1000) / 10,
          rank: i + 1,
        })),
      };
      // Serialise to string; read back with entry.json().
      return JSON.stringify(report);
    },
    { ttl: MEMO_TTL_S },
  );

  const report = await entry.json();

  return Response.json({
    pattern: 'memo',
    note: `Cached for ${MEMO_TTL_S}s. Refresh to confirm 'generatedAt' stays the same until expiry.`,
    report,
  });
}
```

**Key constraints:**
- The populator must return a `string` (or `Promise<string>`). Serialise objects with `JSON.stringify` before returning.
- Read the cached value with `entry.json()` to deserialise, `entry.text()` for the raw string, or `entry.arrayBuffer()` for bytes.
- `getOrSet` always caches the populator result — cannot skip caching conditionally.
- Use for: search index lookups, signed-token verification, report rollups, JSON transformations of slow-changing data.

---

## Complete Router (Compiles as Single Working App)

```typescript
import { Cache } from 'fastedge::cache';

// ... (paste rateLimit, proxy, memo functions above)

function landing(): Response {
  return Response.json({
    name: 'FastEdge Cache patterns',
    actions: {
      'rate-limit': '/?action=rate-limit',
      proxy: '/?action=proxy&url=https://www.example.com',
      memo: '/?action=memo',
    },
  });
}

async function eventHandler(event: FetchEvent): Promise<Response> {
  try {
    const url = new URL(event.request.url);
    const action = url.searchParams.get('action');

    switch (action) {
      case 'rate-limit':
        return await rateLimit(event);
      case 'proxy':
        return await proxy(url.searchParams.get('url') ?? '');
      case 'memo':
        return await memo();
      case null:
        return landing();
      default:
        return Response.json(
          { error: `Unknown action: "${action}". Use one of: rate-limit, proxy, memo.` },
          { status: 400 },
        );
    }
  } catch (error: unknown) {
    // Cache validation errors throw synchronously.
    // Host errors arrive as Promise rejections.
    // This single handler catches both.
    return Response.json({ error: (error as Error).message }, { status: 500 });
  }
}

addEventListener('fetch', (event: FetchEvent) => {
  event.respondWith(eventHandler(event));
});
```

**Error handling requirement:** The top-level `try/catch` in `eventHandler` is mandatory. `Cache.*` validation errors (e.g. conflicting `WriteOptions` fields) are thrown synchronously; host-level failures arrive as rejected Promises. Both surface through this single handler.

---

## Build Notes

**package.json**
```json
{
  "scripts": { "build": "fastedge-build -c" },
  "dependencies": { "@gcoredev/fastedge-sdk-js": "^2.3.0" }
}
```

**tsconfig.json**
```json
{
  "compilerOptions": {
    "target": "ES2023",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "lib": ["ES2023"],
    "types": ["@gcoredev/fastedge-sdk-js"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```

Build command: `fastedge-build -c`

---

## See Also

- fastedge-sdk-js SDK reference (Cache module API)
- http-base skeleton (base event listener and fetch handler structure)
- platform-overview (POP-local vs. global state trade-offs)
- best-practices (key naming conventions, TTL selection, error handling)
