<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: b78b2a80317bb632af88010816d3e54afd3bd72d
      updated: 2026-06-16
-->

---
type: feature
app_type: http
languages: [javascript]
capabilities: [kv-store, denylist, bloom-filter]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/bloom-filter-denylist
---

# Feature: Bloom-Filter Denylist (HTTP)

## When to Use

Use this pattern when you need a low-memory, near-constant-time membership check at the edge — IP denylists, leaked-password checks, abuse-token blocking — where occasional false positives (over-blocking a small fraction of legitimate requests) are acceptable. Do not use bloom filters when exact membership is required (allowlists, authorization gates); use `KvStore.get()` for those cases.

## Imports

```js
import { getEnv } from 'fastedge::env';
import { KvStore } from 'fastedge::kv';
```

## Constants

```js
const BLOOM_KEY = 'blocked-ips';
```

`BLOOM_KEY` is the key under which the bloom-filter payload (the serialized IP set) is stored in the KV store. When populating the store, upload the bloom binary under this key.

## Core Pattern

```js
function app(event) {
  // 1. Resolve store name from environment — fail fast if not configured
  const storeName = getEnv('DENYLIST_STORE');
  if (!storeName) {
    return Response.json(
      { error: 'DENYLIST_STORE environment variable is not configured' },
      { status: 500 },
    );
  }

  // 2. Extract candidate IP from request context — fail fast if unavailable
  const ip = event.client.address;
  if (!ip) {
    return Response.json({ error: 'client address unavailable' }, { status: 500 });
  }

  // 3. Bloom-filter membership check — isolated try/catch
  let blocked;
  try {
    const store = KvStore.open(storeName);
    // bfExists returns a synchronous boolean.
    // Semantics: "maybe in set" — a small fraction of positives are false positives.
    // Acceptable for over-blocking (denylists); unacceptable for exact membership
    // (allowlists) — use KvStore.get() for that.
    blocked = store.bfExists(BLOOM_KEY, ip);
  } catch (error) {
    return Response.json({ error: `KV lookup failed: ${error.message}` }, { status: 500 });
  }

  // 4. Enforce denylist decision
  if (blocked) {
    return Response.json({ allowed: false, ip }, { status: 403 });
  }

  return Response.json({ allowed: true, ip });
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

## API Reference

### `KvStore.open(storeName: string): KvStore`

Opens a KV store by name. Throws if the store does not exist or cannot be accessed. Must be called inside the request handler.

| Parameter   | Type     | Required | Description                          |
|-------------|----------|----------|--------------------------------------|
| `storeName` | `string` | yes      | Name of the KV store to open         |

**Returns**: `KvStore` instance.

**Throws**: On store open failure — catch and return a 500 response.

---

### `store.bfExists(key: string, candidate: string): boolean`

Tests whether `candidate` is a member of the bloom filter stored at `key`.

| Parameter   | Type     | Required | Description                                                  |
|-------------|----------|----------|--------------------------------------------------------------|
| `key`       | `string` | yes      | KV key holding the serialized bloom-filter payload           |
| `candidate` | `string` | yes      | Value to test for membership (e.g. an IP address string)     |

**Returns**: `boolean` — synchronous. `true` means "probably in set" (false positives possible); `false` means "definitely not in set" (no false negatives).

**Throws**: On KV read failure — isolate in a dedicated `try/catch`.

---

### `getEnv(name: string): string | undefined`

Reads a FastEdge environment variable set on the app.

| Parameter | Type     | Required | Description                    |
|-----------|----------|----------|--------------------------------|
| `name`    | `string` | yes      | Environment variable name      |

**Returns**: `string` if set, `undefined` if not configured.

---

### `event.client.address: string | undefined`

IP address of the connecting client, available on the `FetchEvent` passed to the `fetch` listener.

**Returns**: `string` (IP address) or `undefined` if the runtime cannot determine the client address.

## Environment Variables

| Variable         | Required | Description                                      |
|------------------|----------|--------------------------------------------------|
| `DENYLIST_STORE` | yes      | Name of the KV store containing the bloom filter |

## Error Responses

| Condition                           | Status | Body                                                                    |
|-------------------------------------|--------|-------------------------------------------------------------------------|
| `DENYLIST_STORE` not configured     | 500    | `{ "error": "DENYLIST_STORE environment variable is not configured" }`  |
| `event.client.address` unavailable  | 500    | `{ "error": "client address unavailable" }`                             |
| `KvStore.open` or `bfExists` throws | 500    | `{ "error": "KV lookup failed: <error.message>" }`                      |
| IP found in bloom filter            | 403    | `{ "allowed": false, "ip": "<ip>" }`                                    |
| IP not found in bloom filter        | 200    | `{ "allowed": true, "ip": "<ip>" }`                                     |

## Build Notes

**package.json scripts:**

```json
"build": "fastedge-build src/index.js dist/bloom-filter-denylist.wasm"
```

Entry point: `src/index.js`. Output: `dist/bloom-filter-denylist.wasm`. Build tool: `fastedge-build` (from the FastEdge SDK JS package, see the fastedge-build CLI reference).

**Dependencies:**

```json
"@gcoredev/fastedge-sdk-js": "^2.2.2"
```

## False-Positive Trade-off

Bloom filters guarantee no false negatives (an IP absent from the set is never blocked) but permit false positives (an IP not in the set may occasionally be reported as blocked). The rate depends on filter size and the number of inserted elements.

- **Acceptable**: Denylists, spam/abuse IP blocking, leaked-credential checks — occasional over-blocking of a legitimate user is a tolerable cost.
- **Not acceptable**: Allowlists, authorization checks, any case where incorrectly denying access to a legitimate identity is unacceptable. Use `KvStore.get()` for exact-membership lookups.

## See Also

- KvStore reference (exact get/set operations)
- fastedge::env reference
- fastedge-build CLI reference
- KV store setup and bloom-filter payload upload guide

## Source Material

### FILE: examples/bloom-filter-denylist/src/index.js

```js
import { getEnv } from 'fastedge::env';
import { KvStore } from 'fastedge::kv';

const BLOOM_KEY = 'blocked-ips';

function app(event) {
  const storeName = getEnv('DENYLIST_STORE');
  if (!storeName) {
    return Response.json(
      { error: 'DENYLIST_STORE environment variable is not configured' },
      { status: 500 },
    );
  }

  const ip = event.client.address;
  if (!ip) {
    return Response.json({ error: 'client address unavailable' }, { status: 500 });
  }

  let blocked;
  try {
    const store = KvStore.open(storeName);
    blocked = store.bfExists(BLOOM_KEY, ip);
  } catch (error) {
    return Response.json({ error: `KV lookup failed: ${error.message}` }, { status: 500 });
  }

  if (blocked) {
    // Bloom filter says "maybe in set" — a small fraction of hits will be false positives.
    // Acceptable for a denylist (you over-block some legitimate users); not acceptable for
    // allowlists or anything requiring exact membership — use KvStore.get() for that.
    return Response.json({ allowed: false, ip }, { status: 403 });
  }

  return Response.json({ allowed: true, ip });
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

### FILE: examples/bloom-filter-denylist/package.json

```json
{
  "name": "fastedge-example-bloom-filter-denylist",
  "version": "1.0.0",
  "description": "FastEdge JS example: IP denylist using a KV Store bloom filter",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/bloom-filter-denylist.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.2"
  }
}
```
