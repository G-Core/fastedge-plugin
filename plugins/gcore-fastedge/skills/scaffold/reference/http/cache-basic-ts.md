<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: 81145a9a43ec499240c687bd49376ab20c72b11c
      updated: 2026-07-23
-->

---
type: feature
app_type: http
languages: [javascript]
capabilities: [cache]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/cache-basic
---

# Cache Basic — HTTP Feature Blueprint (JavaScript)

A single-handler HTTP app demonstrating the four core `fastedge::cache` primitives: `set`, `get`, `exists`, and `delete`. Dispatches on the `?action=` query parameter so the deployed binary is immediately testable with `curl`.

## When to Use

Use this blueprint when the user wants:
- The simplest possible per-POP key/value store for short-lived state
- Hit counters, rate-limit windows, or idempotency-key checks
- Transient request-time caching without global replication overhead
- A single working app they can `curl` against to explore Cache semantics

**Not appropriate when** writes from one POP must be visible to others — use `fastedge::kv` for globally replicated storage instead.

## Data Scope

Cache is **POP-local**: values are stored in the same point of presence that runs the worker. Reads and writes are fast, but a write at POP-A is not visible at POP-B. This is intentional for transient, request-scoped state.

## Blueprint Code

```javascript
import { Cache } from 'fastedge::cache';

async function eventHandler(event) {
  try {
    const url = new URL(event.request.url);
    const action = url.searchParams.get('action');
    const key = url.searchParams.get('key');

    if (!key) {
      throw new Error('Missing required query parameter: "key"');
    }

    switch (action) {
      case 'set': {
        const value = url.searchParams.get('value') ?? '';
        await Cache.set(key, value, { ttl: 60 });
        return Response.json({ action, key, value, ttl: 60 });
      }

      case 'get': {
        const entry = await Cache.get(key);
        if (entry === null) {
          return Response.json({ action, key, hit: false });
        }
        const value = await entry.text();
        return Response.json({ action, key, hit: true, value });
      }

      case 'exists': {
        const present = await Cache.exists(key);
        return Response.json({ action, key, present });
      }

      case 'delete': {
        await Cache.delete(key);
        return Response.json({ action, key, deleted: true });
      }

      default:
        throw new Error(
          `Unknown action: "${action}". Use one of: set, get, exists, delete.`,
        );
    }
  } catch (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

## API Reference

### Import

```javascript
import { Cache } from 'fastedge::cache';
```

---

### `Cache.set(key, value, options?)`

Writes a value under `key`.

**Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `key` | `string` | yes | Cache key |
| `value` | `string \| ArrayBuffer \| ArrayBufferView \| ReadableStream \| Response` | yes | Value to store. For `Response`, only the body is consumed; status and headers are not stored. |
| `options` | `WriteOptions` | no | Expiry configuration. Omit entirely for no expiry. |

**WriteOptions** (mutually exclusive fields — use at most one)

| Field | Type | Description |
|-------|------|-------------|
| `ttl` | `number` | Seconds until expiry from time of write |
| `ttlMs` | `number` | Milliseconds until expiry (sub-second precision) |
| `expiresAt` | `number` | Fixed Unix-epoch deadline (seconds) |

Validation errors (e.g. conflicting `WriteOptions` fields, wrong value type) are thrown **synchronously**.

**Returns**: `Promise<void>`

---

### `Cache.get(key)`

Reads the value stored under `key`.

**Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `key` | `string` | yes | Cache key to look up |

**Returns**: `Promise<CacheEntry | null>`
- Returns `null` on a miss (key absent or expired)
- Returns a `CacheEntry` on a hit

**CacheEntry decode methods**

| Method | Return type | Description |
|--------|-------------|-------------|
| `entry.text()` | `Promise<string>` | Decode stored bytes as UTF-8 string |
| `entry.json()` | `Promise<unknown>` | Parse stored bytes as JSON |
| `entry.arrayBuffer()` | `Promise<ArrayBuffer>` | Return raw bytes |

---

### `Cache.exists(key)`

Checks whether a key is present without transferring its value.

**Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `key` | `string` | yes | Cache key to check |

**Returns**: `Promise<boolean>` — `true` if the key exists and has not expired, `false` otherwise.

Use for cheap presence checks: idempotency-key guards, "have we seen this token?" patterns, or any path where you only need presence information.

---

### `Cache.delete(key)`

Removes the entry under `key`.

**Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `key` | `string` | yes | Cache key to remove |

**Returns**: `Promise<void>`

**No-op behavior**: If the key is already absent (never set or already expired), `Cache.delete` completes without error. No exception is thrown.

---

## Error Handling

The blueprint wraps the entire handler in a top-level `try/catch`. Both error categories are caught:

| Error category | Origin | Delivery mechanism |
|----------------|--------|--------------------|
| Validation errors | Wrong types, conflicting `WriteOptions` fields, missing parameters | Thrown **synchronously** |
| Host errors | Access denied, internal POP error | Arrive as **Promise rejections** (caught by `await` inside `try/catch`) |

Both categories produce a `{ error: string }` JSON response with HTTP 500.

## URL Contract

| Query string | Cache operation |
|---|---|
| `?action=set&key=foo&value=bar` | `Cache.set("foo", "bar", { ttl: 60 })` |
| `?action=get&key=foo` | `Cache.get("foo")` → decoded with `entry.text()` |
| `?action=exists&key=foo` | `Cache.exists("foo")` |
| `?action=delete&key=foo` | `Cache.delete("foo")` |

Missing `key` parameter returns HTTP 500 with `{ error: "Missing required query parameter: \"key\"" }`.

## Build Notes

**package.json**

```json
{
  "name": "fastedge-example-cache-basic",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/cache-basic.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```

Build command: `fastedge-build src/index.js dist/cache-basic.wasm`

SDK version constraint: `@gcoredev/fastedge-sdk-js ^2.3.0`

## See Also

- `fastedge::kv` reference — globally replicated key/value storage (use when cross-POP visibility is required)
- `fastedge::cache` full API reference — advanced patterns, streaming values, CacheEntry interface
- http-base skeleton — base HTTP handler structure this feature extends
- deploy skill reference — building and uploading the compiled WASM binary
