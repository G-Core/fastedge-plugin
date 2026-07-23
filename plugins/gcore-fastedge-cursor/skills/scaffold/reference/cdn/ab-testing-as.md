<!--
  auto-updated: true
  sources:
    - id: proxy-wasm-sdk-as
      ref: master
      commit: 60f25c7bd35564e5bafb421be7f37aa4acf1bf81
      updated: 2026-05-20
-->

---
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [ab-testing, cookies, traffic-splitting]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/abTesting
---

# Feature: A/B Testing (AssemblyScript)

Cookie-based traffic splitting at the CDN layer. Routes requests to different origin paths based on persistent variant assignment.

## When to Use

Use this feature when you need to split traffic between A/B variants using cookie-stickiness and path rewriting at the CDN layer — without requiring changes to the origin server routing logic.

## How It Works

**`onRequestHeaders`:**
1. Reads `EXPERIMENT_NAME`, `VARIANT_A_PATH`, `VARIANT_B_PATH` from env; returns 500 if any are missing.
2. Checks the incoming `Cookie` header for an existing `fe_exp_<EXPERIMENT_NAME>` cookie.
3. If no valid cookie is found, assigns variant `"A"` or `"B"` via `getCurrentTime() % 2 == 0 ? "A" : "B"` (50/50 split).
4. Prepends the variant path prefix to the original `request.path`.
5. Reconstructs `request.url` from decomposed properties (`request.scheme`, `request.host`, `request.query`) — does **not** splice the variant path into the full URL string.
6. Writes the new URL via `set_property("request.url", ...)`.
7. Adds `X-Experiment` and `X-Variant` request headers for upstream visibility and cross-hook coordination.

**`onResponseHeaders`:**
1. Recovers the assigned variant from `stream_context.headers.request.get("X-Variant")` — instance state does not survive the nginx→core-proxy hop.
2. Sets `Set-Cookie: fe_exp_<EXPERIMENT_NAME>=<variant>; Path=/; Max-Age=86400; SameSite=Lax` to persist assignment for 24 hours.
3. Adds `X-Variant` response header for observability.

## Environment Variables

| Variable | Required | Example | Description |
|---|---|---|---|
| `EXPERIMENT_NAME` | yes | `homepage-redesign` | Experiment identifier; used in cookie name |
| `VARIANT_A_PATH` | yes | `/variant-a` | Path prefix prepended for variant A |
| `VARIANT_B_PATH` | yes | `/variant-b` | Path prefix prepended for variant B |

## Imports

```typescript
import {
  Context,
  FilterHeadersStatusValues,
  get_property,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
  send_http_response,
  set_property,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import {
  getEnv,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
import { getCurrentTime } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge/utils/runtime";
```

## Class Structure

### `AbTestingRoot extends RootContext`

```typescript
class AbTestingRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new AbTestingContext(context_id, this);
  }
}
```

### `AbTestingContext extends Context`

```typescript
class AbTestingContext extends Context {
  constructor(context_id: u32, root_context: AbTestingRoot)
  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues
  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues
  private getCookieValue(cookieHeader: string, name: string): string
}
```

## Key Patterns

### Cookie Parsing (`getCookieValue`)

Private method. Splits `cookieHeader` on `";"`, trims each pair, matches on prefix `name + "="`, returns the value substring. Returns `""` if not found or header is empty.

```typescript
private getCookieValue(cookieHeader: string, name: string): string {
  if (cookieHeader === "") return "";
  const pairs = cookieHeader.split(";");
  const prefix = name + "=";
  for (let i = 0; i < pairs.length; i++) {
    const pair = pairs[i].trim();
    if (pair.startsWith(prefix)) {
      return pair.substring(prefix.length);
    }
  }
  return "";
}
```

### Variant Assignment

Uses `getCurrentTime()` (returns `u64` milliseconds) as entropy source for new visitors.

```typescript
const now = getCurrentTime();
assignedVariant = now % 2 == 0 ? "A" : "B";
```

**Constraint:** `getCurrentTime() % 2` is not sticky across two requests in the same millisecond and is not reproducible in tests. For deterministic assignment, hash a stable visitor identifier (e.g. client IP or session token) instead.

### URL Reconstruction

Reconstruct `request.url` from decomposed properties. Do **not** splice the variant path out of the full URL string — the path substring can collide with host substrings, and the query string may be silently lost.

```typescript
const schemeBuf = get_property("request.scheme");
const hostBuf = get_property("request.host");
if (schemeBuf.byteLength > 0 && hostBuf.byteLength > 0) {
  const scheme = String.UTF8.decode(schemeBuf);
  const host = String.UTF8.decode(hostBuf);
  const queryBuf = get_property("request.query");
  const query = queryBuf.byteLength > 0 ? String.UTF8.decode(queryBuf) : "";
  const newUrl =
    scheme + "://" + host + newPath + (query.length > 0 ? "?" + query : "");
  set_property("request.url", String.UTF8.encode(newUrl));
}
```

Properties used:

| Property | Type | Description |
|---|---|---|
| `request.path` | `ArrayBuffer` | Original request path |
| `request.scheme` | `ArrayBuffer` | URL scheme (`http` / `https`) |
| `request.host` | `ArrayBuffer` | Host header value |
| `request.query` | `ArrayBuffer` | Query string (may be empty) |
| `request.url` | `ArrayBuffer` | Full URL — write target for rewrite |

### Cross-Hook Coordination

Instance state does not survive between `onRequestHeaders` and `onResponseHeaders` (nginx→core-proxy hop). Pass variant via request header:

- `onRequestHeaders` writes: `stream_context.headers.request.add("X-Variant", assignedVariant)`
- `onResponseHeaders` reads: `stream_context.headers.request.get("X-Variant")`

### Cookie Emission

```typescript
stream_context.headers.response.add(
  "Set-Cookie",
  cookieName + "=" + variant + "; Path=/; Max-Age=86400; SameSite=Lax",
);
```

Cookie name format: `fe_exp_<EXPERIMENT_NAME>`
TTL: 86400 seconds (24 hours)

## Registration

```typescript
registerRootContext((context_id: u32) => {
  return new AbTestingRoot(context_id);
}, "abTesting");
```

## Error Handling

| Condition | Response |
|---|---|
| `EXPERIMENT_NAME` not set | `send_http_response(500, "internal server error", "App misconfigured - EXPERIMENT_NAME must be set", [])` → `StopIteration` |
| `VARIANT_A_PATH` or `VARIANT_B_PATH` not set | `send_http_response(500, "internal server error", "App misconfigured - VARIANT_A_PATH and VARIANT_B_PATH must be set", [])` → `StopIteration` |
| `request.path` property empty | Return `Continue` without rewriting |
| `request.scheme` or `request.host` empty | Skip URL rewrite; path header is still modified |

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output | Description |
|---|---|
| `build/abTesting.wasm` | Release binary — upload to FastEdge |
| `build/abTesting-debug.wasm` | Debug binary with source maps |

## Dependencies

```json
{
  "dependencies": {
    "@gcoredev/proxy-wasm-sdk-as": "^1.2.3"
  },
  "devDependencies": {
    "@assemblyscript/wasi-shim": "^0.1.0",
    "assemblyscript": "^0.28.9"
  }
}
```

## See Also

- cdn-base skeleton reference
- proxy-wasm-sdk-as assembly API reference
- FastEdge environment variable configuration
- FastEdge CDN application deployment guide
