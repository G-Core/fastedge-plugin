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
capabilities: [kv-store]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/kv-store-basic
---

# Feature: KV Store — Basic Read (JavaScript)

## When to Use

Use this feature when the user wants the simplest possible KV read against a pre-configured store: a single key lookup with miss handling and no write or update logic.

## Overview

Reads a value from a named KV Store by key. Returns 404 on a cache miss, 200 with the value on hit, and 500 JSON on unexpected host errors. The store must be pre-configured on the FastEdge app before the binary is deployed.

## Required Import

```js
import { KvStore } from 'fastedge::kv';
```

`fastedge::kv` is a host-provided module. It is not an npm package and must not appear in `package.json` dependencies.

## API

### `KvStore.open(name: string): KvStore`

Opens a handle to a named KV Store.

| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| `name`    | string | yes      | Store name exactly as configured on the FastEdge app |

- The `name` must match the store name defined in the FastEdge app configuration. It is not invented locally.
- Returns a `KvStore` handle synchronously.
- Throws if the store is not found or not attached to the app.

---

### `store.getEntry(key: string): Promise<KvEntry | null>`

Fetches a single entry by key.

| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| `key`     | string | yes      | Key to look up in the store |

- Returns `null` if the key does not exist (miss contract — must be checked explicitly).
- Returns a `KvEntry` object on hit.
- Always `await` this call.

---

### `entry.text(): Promise<string>`

Decodes the entry value as a UTF-8 string.

- Returns a `Promise<string>`.
- Always `await` this call.

## Minimal Pattern

```js
import { KvStore } from 'fastedge::kv';

async function eventHandler(event) {
  try {
    const myStore = KvStore.open('kv-store-name-as-defined-on-app');
    const entry = await myStore.getEntry('key');

    if (entry === null) {
      return new Response('Key not found', { status: 404 });
    }

    return new Response(`The KV Store responded with: ${await entry.text()}`);
  } catch (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

## Error Handling

- **Miss (key not found)**: `getEntry` returns `null`. The explicit `if (entry === null)` branch must return a 404 response. Do not attempt to call `.text()` on a null entry.
- **Host errors / store misconfiguration**: The top-level `try/catch` catches any unexpected host-level error and returns `Response.json({ error: error.message }, { status: 500 })`.

## Build Notes

Build script from `package.json`:

```json
"build": "fastedge-build src/index.js dist/kv-store-basic.wasm"
```

- Entry point: `src/index.js`
- Output: `dist/kv-store-basic.wasm`
- SDK dependency: `@gcoredev/fastedge-sdk-js` `^2.3.0`
- Module type: `"type": "module"` (ESM)

## Constraints

- The store name passed to `KvStore.open()` must match the name configured on the FastEdge app, not a locally chosen identifier.
- `getEntry` is async — always `await`.
- `entry.text()` is async — always `await`.
- This pattern covers read-only access. Write and update operations are not demonstrated in this example.

## See Also

- http-base reference (base skeleton for HTTP apps)
- fastedge-sdk-js SDK reference
- FastEdge app configuration (store attachment)
- BUILD_CLI reference (fastedge-build options)

## Source Material

### FILE: examples/kv-store-basic/src/index.js

```js
import { KvStore } from 'fastedge::kv';

async function eventHandler(event) {
  try {
    const myStore = KvStore.open('kv-store-name-as-defined-on-app');
    const entry = await myStore.getEntry('key');

    if (entry === null) {
      return new Response('Key not found', { status: 404 });
    }

    return new Response(`The KV Store responded with: ${await entry.text()}`);
  } catch (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

### FILE: examples/kv-store-basic/package.json

```json
{
  "name": "fastedge-example-kv-store-basic",
  "version": "1.0.0",
  "description": "FastEdge JS example: simple KV Store get operation",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/kv-store-basic.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```
