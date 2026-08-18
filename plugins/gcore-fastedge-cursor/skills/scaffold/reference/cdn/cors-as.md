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
capabilities: [cors]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/cors
---

# CORS — AssemblyScript (CDN)

## When to Use

Use this feature when you need to add CORS response headers (e.g. `Access-Control-Allow-Origin`) based on a configurable allowed-origin list at the CDN layer, without modifying origin server code.

## Overview

Inspects the `Origin` request header in `onResponseHeaders`. If the origin is on the allowed list (or the list is `*`), injects `Access-Control-Allow-Origin` and `Vary: Origin` into the response. Optionally injects `Access-Control-Expose-Headers`. Requests from disallowed origins pass through unchanged.

OPTIONS preflight requests are handled by the FastEdge edge layer before proxy-wasm hooks fire. Do not attempt preflight handling inside WASM code.

## Environment Variables

| Variable | Required | Example | Description |
|---|---|---|---|
| `ALLOWED_ORIGINS` | Yes | `https://example.com,https://app.example.com` | Comma-separated list of allowed origins, or `*` to allow any origin |
| `EXPOSE_HEADERS` | No | `X-Request-Id,X-Trace-Id` | Comma-separated list of response headers to expose to the browser via `Access-Control-Expose-Headers` |

## Class Structure

```
CorsRoot extends RootContext
  createContext(context_id: u32): Context
    → sets log level to info
    → returns new CorsContext

CorsContext extends Context
  constructor(context_id: u32, root_context: CorsRoot)
  private isOriginAllowed(origin: string, allowedOrigins: string): bool
  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues
  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues
```

## Private Method: isOriginAllowed

```assemblyscript
private isOriginAllowed(origin: string, allowedOrigins: string): bool
```

- Returns `true` if `allowedOrigins === ""` or `allowedOrigins === "*"`
- Otherwise splits `allowedOrigins` on `","` and checks each trimmed entry against `origin`
- Returns `false` if no match found

> AssemblyScript has no closures over mutable state and nested functions miss default args under indirect dispatch — implement as a class private method, not a closure or standalone function.

## Hook: onRequestHeaders

```assemblyscript
onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues
```

- Reads `ALLOWED_ORIGINS` via `getEnv("ALLOWED_ORIGINS")`
- Reads `Origin` header via `stream_context.headers.request.get("Origin")`
- Logs origin value at `LogLevelValues.info`
- If origin is non-empty and not allowed, logs a warning
- Does NOT block the request or handle OPTIONS preflights — returns `FilterHeadersStatusValues.Continue` unconditionally

## Hook: onResponseHeaders

```assemblyscript
onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues
```

- Reads `ALLOWED_ORIGINS` via `getEnv("ALLOWED_ORIGINS")`
- Reads `Origin` header via `stream_context.headers.request.get("Origin")`
- If `origin === ""` or origin is not allowed → returns `FilterHeadersStatusValues.Continue` with no headers added
- If origin is allowed:
  - Computes `effectiveOrigin`: `"*"` if `allowedOrigins === "*"`, otherwise the echoed `origin` value
  - Adds `Access-Control-Allow-Origin: <effectiveOrigin>` via `stream_context.headers.response.add`
  - Adds `Vary: Origin` via `stream_context.headers.response.add`
  - If `getEnv("EXPOSE_HEADERS") !== ""` → adds `Access-Control-Expose-Headers: <exposeHeaders>`
- Returns `FilterHeadersStatusValues.Continue`

## Root Context Registration

```assemblyscript
registerRootContext((context_id: u32) => {
  return new CorsRoot(context_id);
}, "cors");
```

Plugin name: `"cors"`

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

No additional dependencies beyond the CDN base skeleton.

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output file | Description |
|---|---|
| `build/cors.wasm` | Optimised release binary — upload to FastEdge |
| `build/cors-debug.wasm` | Debug binary with source maps |

Build scripts:
- `asbuild:debug` — `asc assembly/index.ts --target debug`
- `asbuild:release` — `asc assembly/index.ts --target release`
- `asbuild` — runs both

## Constraints and Behaviour Notes

- `ALLOWED_ORIGINS` must be set; if empty string, all origins are allowed (same as `*`)
- Origin matching is exact string equality after `trim()` — no wildcard subdomains, no regex
- `Vary: Origin` is always added alongside `Access-Control-Allow-Origin` to prevent cache poisoning
- OPTIONS preflights are answered by the FastEdge edge layer before this hook fires — configure preflight behaviour (allowed methods, max-age) in CDN application settings, not in WASM

## See Also

- cdn-base skeleton reference
- proxy-wasm-sdk-as SDK reference
- FastEdge CDN application environment variable configuration
- FastEdge portal deployment guide

## Source Material

### FILE: examples/cors/assembly/index.ts

```ts
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
import {
  Context,
  FilterHeadersStatusValues,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import {
  getEnv,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

class CorsRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new CorsContext(context_id, this);
  }
}

class CorsContext extends Context {
  constructor(context_id: u32, root_context: CorsRoot) {
    super(context_id, root_context);
  }

  private isOriginAllowed(origin: string, allowedOrigins: string): bool {
    if (allowedOrigins === "" || allowedOrigins === "*") return true;
    const origins = allowedOrigins.split(",");
    for (let i = 0; i < origins.length; i++) {
      if (origins[i].trim() == origin) return true;
    }
    return false;
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    const allowedOrigins = getEnv("ALLOWED_ORIGINS");
    const origin = stream_context.headers.request.get("Origin");
    log(LogLevelValues.info, "onRequestHeaders >> origin: " + origin);

    if (origin !== "" && !this.isOriginAllowed(origin, allowedOrigins)) {
      log(LogLevelValues.info, "CORS: origin not allowed: " + origin);
    }

    // OPTIONS preflights are answered by the FastEdge edge layer before this
    // hook fires — don't try to handle them here.

    return FilterHeadersStatusValues.Continue;
  }

  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    const allowedOrigins = getEnv("ALLOWED_ORIGINS");
    const origin = stream_context.headers.request.get("Origin");

    if (origin === "" || !this.isOriginAllowed(origin, allowedOrigins)) {
      return FilterHeadersStatusValues.Continue;
    }

    const effectiveOrigin = allowedOrigins === "*" ? "*" : origin;

    stream_context.headers.response.add(
      "Access-Control-Allow-Origin",
      effectiveOrigin,
    );
    stream_context.headers.response.add("Vary", "Origin");

    const exposeHeaders = getEnv("EXPOSE_HEADERS");
    if (exposeHeaders !== "") {
      stream_context.headers.response.add(
        "Access-Control-Expose-Headers",
        exposeHeaders,
      );
    }

    return FilterHeadersStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => {
  return new CorsRoot(context_id);
}, "cors");
```

### FILE: examples/cors/package.json

```json
{
  "name": "fastedge-as-example-cors",
  "version": "1.0.0",
  "description": "FastEdge AssemblyScript example: CORS — preflight handling and response headers",
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

### FILE: examples/cors/README.md

```
[← Back to examples](../README.md)

# CORS

This application adds Cross-Origin Resource Sharing (CORS) headers to responses from allowed origins.

## What it does

In `onResponseHeaders`, for requests from allowed origins, the app adds `Access-Control-Allow-Origin` and `Vary: Origin` response headers. Optionally exposes additional headers via `Access-Control-Expose-Headers`. Requests from disallowed origins pass through unchanged (no CORS headers added).

> **Note on OPTIONS preflights:** FastEdge's edge layer answers OPTIONS preflight requests directly — proxy-wasm hooks do not fire for OPTIONS. Configure preflight behaviour (allowed methods, max-age, etc.) in your CDN application settings, not in WASM code.

## Configuration

Set the following environment variables on your FastEdge application:

| Variable | Example | Description |
|----------|---------|-------------|
| `ALLOWED_ORIGINS` | `https://example.com,https://app.example.com` | Comma-separated allowed origins, or `*` for any (required) |
| `EXPOSE_HEADERS` | `X-Request-Id, X-Trace-Id` | Response headers to expose to the browser (optional) |

## Build

```sh
pnpm install
pnpm run asbuild
```

Build output:

| File | Description |
|------|-------------|
| `build/cors.wasm` | Optimised release binary — upload this to FastEdge |
| `build/cors-debug.wasm` | Debug binary with source maps |

## Deploy

Upload `build/cors.wasm` to the FastEdge portal and attach it to your CDN application. Configure the `ALLOWED_ORIGINS` environment variable in the application settings.
```
