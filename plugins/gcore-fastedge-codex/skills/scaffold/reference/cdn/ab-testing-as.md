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

## Source Material

### FILE: examples/abTesting/assembly/index.ts

```ts
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
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

class AbTestingRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new AbTestingContext(context_id, this);
  }
}

class AbTestingContext extends Context {
  constructor(context_id: u32, root_context: AbTestingRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    const experimentName = getEnv("EXPERIMENT_NAME");
    if (experimentName === "") {
      send_http_response(
        500,
        "internal server error",
        String.UTF8.encode("App misconfigured - EXPERIMENT_NAME must be set"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    const variantAPath = getEnv("VARIANT_A_PATH");
    const variantBPath = getEnv("VARIANT_B_PATH");
    if (variantAPath === "" || variantBPath === "") {
      send_http_response(
        500,
        "internal server error",
        String.UTF8.encode(
          "App misconfigured - VARIANT_A_PATH and VARIANT_B_PATH must be set",
        ),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    // Check for existing experiment cookie
    const cookieName = "fe_exp_" + experimentName;
    const cookieHeader = stream_context.headers.request.get("Cookie");
    let assignedVariant = this.getCookieValue(cookieHeader, cookieName);

    // Assign variant if not already set
    if (assignedVariant !== "A" && assignedVariant !== "B") {
      // Use current time as a simple entropy source for 50/50 split
      const now = getCurrentTime();
      assignedVariant = now % 2 == 0 ? "A" : "B";
    }

    // Rewrite the request path to the variant path
    const pathArrBuf = get_property("request.path");
    if (pathArrBuf.byteLength === 0) {
      return FilterHeadersStatusValues.Continue;
    }
    const originalPath = String.UTF8.decode(pathArrBuf);
    const variantPath = assignedVariant === "A" ? variantAPath : variantBPath;
    const newPath = variantPath + originalPath;

    // Reconstruct request.url from its decomposed parts rather than splicing
    // the path out of the full URL — splicing breaks when the path happens to
    // appear inside the host, and it can silently lose the query string.
    const schemeBuf = get_property("request.scheme");
    const hostBuf = get_property("request.host");
    if (schemeBuf.byteLength > 0 && hostBuf.byteLength > 0) {
      const scheme = String.UTF8.decode(schemeBuf);
      const host = String.UTF8.decode(hostBuf);
      const queryBuf = get_property("request.query");
      const query = queryBuf.byteLength > 0 ? String.UTF8.decode(queryBuf) : "";
      const newUrl =
        scheme + "://" + host + newPath + (query.length > 0 ? "?" + query : "");
      log(LogLevelValues.info, `A/B routing: ${newUrl}`);
      set_property("request.url", String.UTF8.encode(newUrl));
    }

    // Add variant header for upstream visibility
    stream_context.headers.request.add("X-Experiment", experimentName);
    stream_context.headers.request.add("X-Variant", assignedVariant);

    log(
      LogLevelValues.info,
      `A/B test "${experimentName}": variant ${assignedVariant}, path ${newPath}`,
    );

    return FilterHeadersStatusValues.Continue;
  }

  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    // Recover the assigned variant from the request header set in onRequestHeaders.
    // Instance state (this.variant) does not survive the nginx -> core-proxy hop.
    const variant = stream_context.headers.request.get("X-Variant");
    if (variant === "") {
      return FilterHeadersStatusValues.Continue;
    }

    const experimentName = getEnv("EXPERIMENT_NAME");
    const cookieName = "fe_exp_" + experimentName;

    // Set the experiment cookie so subsequent requests stick to the same variant
    stream_context.headers.response.add(
      "Set-Cookie",
      cookieName + "=" + variant + "; Path=/; Max-Age=86400; SameSite=Lax",
    );

    // Add variant as response header for observability
    stream_context.headers.response.add("X-Variant", variant);

    return FilterHeadersStatusValues.Continue;
  }

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
}

registerRootContext((context_id: u32) => {
  return new AbTestingRoot(context_id);
}, "abTesting");
```


### FILE: examples/abTesting/package.json

```json
{
  "name": "fastedge-as-example-ab-testing",
  "version": "1.0.0",
  "description": "FastEdge AssemblyScript example: A/B Testing — cookie-based traffic splitting at the CDN layer",
  "scripts": {
    "asbuild:debug": "asc assembly/index.ts --target debug",
    "asbuild:release": "asc assembly/index.ts --target release",
    "asbuild": "npm run asbuild:debug && npm run asbuild:release"
  },
  "dependencies": {
    "@gcoredev/proxy-wasm-sdk-as": "^1.2.3"
  },
  "devDependencies": {
    "@assemblyscript/wasi-shim": "^0.1.0",
    "assemblyscript": "^0.28.9"
  }
}
```


### FILE: examples/abTesting/README.md

```
[← Back to examples](../README.md)

# A/B Testing

This application performs cookie-based A/B traffic splitting at the CDN layer, routing requests to different origin paths based on variant assignment.

## What it does

In `onRequestHeaders`, the app:

1. Checks for an existing experiment cookie (`fe_exp_<EXPERIMENT_NAME>`).
2. If no cookie is found, assigns the user to variant **A** or **B** (50/50 split).
3. Rewrites the request path by prepending the variant-specific path prefix (e.g. `/variant-a/original/path`).
4. Adds `X-Experiment` and `X-Variant` request headers for upstream visibility.

In `onResponseHeaders`, the app sets a `Set-Cookie` header to persist the variant assignment for subsequent requests (24-hour TTL).

> **Note on variant assignment entropy:** New-visitor assignment uses `getCurrentTime() % 2` as a simple 50/50 source. This is illustrative — it is not sticky across two requests that arrive in the same millisecond and is not reproducible in tests. Production A/B implementations typically hash a stable visitor identifier (e.g. client IP or session token) for deterministic, sticky pre-cookie assignment.

## Configuration

Set the following environment variables on your FastEdge application:

| Variable | Example | Description |
|----------|---------|-------------|
| `EXPERIMENT_NAME` | `homepage-redesign` | Name of the experiment (required) |
| `VARIANT_A_PATH` | `/variant-a` | Path prefix for variant A (required) |
| `VARIANT_B_PATH` | `/variant-b` | Path prefix for variant B (required) |

Your origin server should serve different content at each variant path prefix.

## Build

```sh
pnpm install
pnpm run asbuild
```

Build output:

| File | Description |
|------|-------------|
| `build/abTesting.wasm` | Optimised release binary — upload this to FastEdge |
| `build/abTesting-debug.wasm` | Debug binary with source maps |

## Deploy

Upload `build/abTesting.wasm` to the FastEdge portal and attach it to your CDN application. Configure the experiment environment variables in the application settings.
```
