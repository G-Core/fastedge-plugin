<!--
  auto-updated: true
  sources:
    - id: proxy-wasm-sdk-as
      ref: master
      commit: 8e3bb621bc013a0aed7e52122066b417ad62a207
      updated: 2026-08-17
-->

---
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [kv-store]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/kvStore
---

# KV Store — AssemblyScript (CDN)

## When to Use

Add this feature when the app needs to query a key-value store at the CDN layer — for data lookups by key, pattern scanning, sorted set range queries, or Bloom filter membership checks.

## New Files

| File | Description |
|---|---|
| `assembly/utils.ts` | Query parameter parsing and response serialization helpers |

## Modified Files

| File | Change |
|---|---|
| `assembly/index.ts` | Add `KvStore` import; implement store open + dispatch in `onResponseBody` |

## Imports

```typescript
// assembly/index.ts
import {
  KvStore,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

// assembly/utils.ts
import { ValueScoreTuple } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
```

## API Reference

### `KvStore.open`

```typescript
KvStore.open(name: string): KvStore | null
```

Opens a named KV Store attached to the application. Returns `null` if the store cannot be opened (store not configured or not linked to the app).

**Parameters:**
- `name: string` — the store name as configured on the FastEdge application

**Returns:** `KvStore | null`

---

### `KvStore.get`

```typescript
myStore.get(key: string): ArrayBuffer | null
```

Fetches a single value by key. Returns `null` if the key does not exist.

**Parameters:**
- `key: string` — the key to look up

**Returns:** `ArrayBuffer | null`

**Decoding pattern:**
```typescript
const storeArrBuff = myStore.get(key);
if (storeArrBuff == null) {
  // key not found
}
const value = String.UTF8.decode(storeArrBuff);
```

---

### `KvStore.scan`

```typescript
myStore.scan(match: string): Array<string>
```

Scans keys matching a pattern. The `match` parameter must include a wildcard (e.g. `foo*`).

**Parameters:**
- `match: string` — prefix match pattern (must include wildcard)

**Returns:** `Array<string>` — matching keys

---

### `KvStore.zrangeByScore`

```typescript
myStore.zrangeByScore(key: string, min: f64, max: f64): Array<ValueScoreTuple>
```

Range query on a sorted set by score. Returns all members whose score is between `min` and `max` (inclusive).

**Parameters:**
- `key: string` — sorted set key
- `min: f64` — minimum score (inclusive)
- `max: f64` — maximum score (inclusive)

**Returns:** `Array<ValueScoreTuple>`

---

### `KvStore.zscan`

```typescript
myStore.zscan(key: string, match: string): Array<ValueScoreTuple>
```

Pattern scan on a sorted set. Returns members whose value matches the pattern.

**Parameters:**
- `key: string` — sorted set key
- `match: string` — pattern to match against member values

**Returns:** `Array<ValueScoreTuple>`

---

### `KvStore.bfExists`

```typescript
myStore.bfExists(key: string, item: string): bool
```

Checks membership in a Bloom filter.

**Parameters:**
- `key: string` — Bloom filter key
- `item: string` — item to test for existence

**Returns:** `bool` — `true` if item may exist, `false` if definitely absent

---

### `ValueScoreTuple`

Returned by `zrangeByScore` and `zscan`.

| Field | Type | Description |
|---|---|---|
| `value` | `ArrayBuffer` | Member value — decode with `String.UTF8.decode(tuple.value)` |
| `score` | `f64` | Member score |

**Decoding pattern:**
```typescript
const tuples = myStore.zrangeByScore(key, parseFloat(min), parseFloat(max));
for (let i = 0; i < tuples.length; i++) {
  const tuple = tuples[i];
  const value = String.UTF8.decode(tuple.value);
  const score = tuple.score.toString();
}
```

---

## Supported Actions and Required Query Parameters

| Action | Required Parameters | Description |
|---|---|---|
| `get` | `store`, `key` | Fetch a single value by key |
| `scan` | `store`, `match` | Scan keys matching a pattern |
| `zrange` | `store`, `key`, `min`, `max` | Range query on a sorted set by score |
| `zscan` | `store`, `key`, `match` | Pattern scan on a sorted set |
| `bfExists` | `store`, `key`, `item` | Check membership in a Bloom filter |

Default action when `action` is omitted: `get`.

---

## Query Parameter Parsing

Query parameters are read from `request.query` via `get_property`:

```typescript
const queryBytes = get_property(REQUEST_QUERY); // REQUEST_QUERY = "request.query"
const query = queryBytes.byteLength === 0 ? "" : String.UTF8.decode(queryBytes);
```

Parsing and validation is handled in `assembly/utils.ts` via `validateQueryParams`. Returns a `Map<string, string>` containing valid params, or a map with an `"error"` key if validation fails.

The `validateQueryParams` function:
- Parses key=value pairs split by `&`
- URL-decodes keys and values (handles `%XX` hex encoding and `+` as space)
- Defaults `action` to `"get"` when omitted
- Validates `action` against `ALL_ACTIONS = ["get", "scan", "zscan", "zrange", "bfExists"]`
- Checks all required parameters for the resolved action are present and non-empty

---

## Error Handling

- Missing or empty query string → error response: `"App must be called with query parameters"`
- Invalid `action` value → error response: `"Invalid action '<action>'. Supported actions are: get, scan, zscan, zrange, bfExists"`
- Missing required parameter for an action → error response: `"Query parameters must provide '<param>' for a '<action>' action."`
- `KvStore.open` returns `null` → error response: `"Failed to open KvStore: '<name>'"`
- `KvStore.get` returns `null` → response body field set to `"null (Not found)"` (not an error response)

Error responses set HTTP status to `545` via `set_property("response.status", ...)` and return a JSON body:
```json
{ "error": "<message>" }
```

> **Note:** Because the error path runs in `onResponseBody` (after response headers have already been transmitted), the status property is advisory to the CDN runtime and the origin HTTP status passes through to the client. The JSON error body is the authoritative error signal.

---

## Response Format

Successful responses are returned as JSON in `onResponseBody`. Response headers are modified in `onResponseHeaders`:

```typescript
stream_context.headers.response.remove("content-length");
stream_context.headers.response.remove("refresh");
stream_context.headers.response.remove("location");
stream_context.headers.response.replace("transfer-encoding", "Chunked");
stream_context.headers.response.replace("content-type", "application/json");
```

Body is set via:
```typescript
set_buffer_bytes(
  BufferTypeValues.HttpResponseBody,
  0,
  <u32>body_buffer_length,
  String.UTF8.encode(responseBody)
);
```

The response body is a JSON object built from a `Map<string, string>` using `stringifyMap`. It includes fields such as `Store`, `Action`, `Key`, `Response`, and action-specific fields (`Match`, `Min`, `Max`, `Item`).

---

## Hook: `onResponseBody`

This feature is implemented in `onResponseBody`. The body is buffered until `end_of_stream` is true:

```typescript
onResponseBody(body_buffer_length: usize, end_of_stream: bool): FilterDataStatusValues {
  if (!end_of_stream) {
    return FilterDataStatusValues.StopIterationAndBuffer;
  }
  // ... dispatch on action
}
```

---

## Lifecycle

```
registerRootContext → KvStoreRoot.createContext (sets log level to info)
  → KvStoreContext.onResponseHeaders (remove/replace headers)
  → KvStoreContext.onResponseBody (read query, open store, dispatch action, write body)
```

---

## Build

```json
// package.json scripts
"asbuild:debug":   "asc assembly/index.ts --target debug",
"asbuild:release": "asc assembly/index.ts --target release",
"asbuild":         "npm run asbuild:debug && npm run asbuild:release"
```

| Output file | Description |
|---|---|
| `build/kvStore.wasm` | Optimised release binary — upload to FastEdge |
| `build/kvStore-debug.wasm` | Debug binary with source maps |

---

## Deploy Requirement

The KV Store must be configured and linked to the FastEdge application before use. `KvStore.open` will return `null` if the named store is not attached. The `store` query parameter at runtime must exactly match the binding name configured on the application.

---

## See Also

- cdn-base reference (base CDN skeleton)
- fastedge-docs: platform-overview (KV Store configuration on the portal)
- fastedge-docs: sdk-reference-js (AssemblyScript SDK overview)
