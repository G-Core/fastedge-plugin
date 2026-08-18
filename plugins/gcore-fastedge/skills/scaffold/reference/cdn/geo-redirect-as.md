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
capabilities: [geo-routing, redirect]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/geoRedirect
---

# Geo Redirect (AssemblyScript, CDN)

Routes upstream fetch requests to different origin URLs based on the client's country code. The redirect is transparent — the client receives a normal response from the matched origin; no 3xx browser redirect is issued.

## When to Use

Use this blueprint when you need to route CDN traffic to a different origin server based on the client's country code at the edge layer, without exposing the routing logic to the client.

## Imports

```typescript
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
} from "@gcoredev/proxy-wasm-sdk-as/assembly";

import {
  getEnv,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
```

- `get_property`, `set_property`, `send_http_response`, `log`, `registerRootContext` — from `@gcoredev/proxy-wasm-sdk-as/assembly`
- `getEnv`, `setLogLevel` — from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`

## Class Structure

### RootContext subclass

```typescript
class GeoRedirectRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new GeoRedirect(context_id, this);
  }
}
```

- Call `setLogLevel` in `createContext` before returning the context instance.

### Context subclass

```typescript
class GeoRedirect extends Context {
  constructor(context_id: u32, root_context: GeoRedirectRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    // ... routing logic
  }
}
```

## Core Pattern: `onRequestHeaders`

All routing logic runs in `onRequestHeaders`. Return `FilterHeadersStatusValues.Continue` to proceed with the upstream fetch, or `FilterHeadersStatusValues.StopIteration` after calling `send_http_response` on error.

### Step 1 — Validate DEFAULT origin

```typescript
const defaultOrigin = getEnv("DEFAULT");

if (!defaultOrigin) {
  send_http_response(
    INTERNAL_SERVER_ERROR,
    "internal server error",
    String.UTF8.encode("App misconfigured - DEFAULT must be set"),
    [],
  );
  return FilterHeadersStatusValues.StopIteration;
}
```

- `getEnv("DEFAULT")` returns an empty string `""` when unset; falsy check covers both empty string and null.
- Missing `DEFAULT` → 500 response, stop iteration.

### Step 2 — Read country code

```typescript
const countryArrBuf = get_property("request.country");
if (countryArrBuf.byteLength === 0) {
  send_http_response(
    BAD_GATEWAY,
    "bad gateway",
    String.UTF8.encode("Missing country information"),
    [],
  );
  return FilterHeadersStatusValues.StopIteration;
}
const countryCode = String.UTF8.decode(countryArrBuf);
```

- `get_property("request.country")` returns `ArrayBuffer`; decode with `String.UTF8.decode`.
- `byteLength === 0` means the property was absent — return 502 and stop.
- Country codes follow ISO 3166-1 alpha-2 (e.g. `"DE"`, `"US"`).

### Step 3 — Country-keyed origin lookup

```typescript
const countrySpecificOrigin = getEnv(countryCode);
```

- `getEnv(countryCode)` looks up an env var named after the country code (e.g. env var `DE` for Germany).
- Returns `""` (empty string) when no matching env var is set.
- Do **not** use a null/undefined check; use an empty-string check.

### Step 4 — Read request host (optional)

```typescript
const hostArrBuf = get_property("request.host");
if (hostArrBuf.byteLength > 0) {
  const host = String.UTF8.decode(hostArrBuf);
  log(LogLevelValues.info, `Provided Host: ${host}`);
}
```

- `get_property("request.host")` returns `ArrayBuffer`; decode with `String.UTF8.decode`.
- Reading the host is optional; absence does not stop iteration.

### Step 5 — Read request path

```typescript
const pathArrBuf = get_property("request.path");
if (pathArrBuf.byteLength === 0) {
  send_http_response(
    INTERNAL_SERVER_ERROR,
    "internal server error",
    String.UTF8.encode("Internal server error - no request path"),
    [],
  );
  return FilterHeadersStatusValues.StopIteration;
}
const path = String.UTF8.decode(pathArrBuf);
```

- `get_property("request.path")` returns `ArrayBuffer`; decode with `String.UTF8.decode`.
- Missing path → 500 response, stop iteration.

### Step 6 — Build and set target URL

```typescript
const origin = countrySpecificOrigin === "" ? defaultOrigin : countrySpecificOrigin;
const cleanedOrigin = origin.endsWith("/") ? origin.slice(0, -1) : origin;
const requestUrl = `${cleanedOrigin}${path}`;

set_property("request.url", String.UTF8.encode(requestUrl));

return FilterHeadersStatusValues.Continue;
```

- Select country-specific origin if non-empty; otherwise fall back to `DEFAULT`.
- Strip trailing slash from origin before concatenating with path.
- `set_property("request.url", ...)` rewrites the upstream fetch target — this is **not** an HTTP redirect; the client sees a normal response.
- Encode the URL string with `String.UTF8.encode` before passing to `set_property`.

## Runtime Properties

| Property | Access | Return type | Description |
|---|---|---|---|
| `request.country` | `get_property` | `ArrayBuffer` | ISO 3166-1 alpha-2 country code from FastEdge Geo-IP |
| `request.host` | `get_property` | `ArrayBuffer` | Request Host header value |
| `request.path` | `get_property` | `ArrayBuffer` | Request URL path |
| `request.url` | `set_property` | — | Upstream fetch target URL (rewrite, not redirect) |

All `get_property` return values must be decoded with `String.UTF8.decode`. All `set_property` values must be encoded with `String.UTF8.encode`.

## Environment Variables

| Variable | Required | Example | Description |
|---|---|---|---|
| `DEFAULT` | Yes | `https://origin.example.com` | Fallback origin URL; must be set or app returns 500 |
| `<COUNTRY_CODE>` | No | `DE=https://de.example.com` | Per-country origin URL; one env var per country code |

- Country code env vars use ISO 3166-1 alpha-2 (uppercase, e.g. `DE`, `US`, `JP`).
- Any country without a matching env var falls back to `DEFAULT`.

## Error Responses

| Condition | Status | Body |
|---|---|---|
| `DEFAULT` env var not set | 500 | `App misconfigured - DEFAULT must be set` |
| `request.country` property absent | 502 | `Missing country information` |
| `request.path` property absent | 500 | `Internal server error - no request path` |

`send_http_response(status: u32, status_message: string, body: ArrayBuffer, headers: string[]): void`

## Registration

```typescript
registerRootContext((context_id: u32) => {
  return new GeoRedirectRoot(context_id);
}, "geoRedirect");
```

- The second argument is the root context name; must match the name used during app registration.

## Logging

```typescript
log(LogLevelValues.info, "onRequestHeaders >> ");
log(LogLevelValues.info, `Country code: ( ${countryCode} ): ${countrySpecificOrigin === "" ? "no matching origin" : countrySpecificOrigin}`);
log(LogLevelValues.info, `Provided Host: ${host}`);
log(LogLevelValues.info, `request-url: ${requestUrl}`);
```

- Log level is set to `info` in `createContext` via `setLogLevel(LogLevelValues.info)`.
- Logs are visible in FastEdge application logs.

## Build

```json
{
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

Build outputs:

| File | Description |
|---|---|
| `build/geoRedirect.wasm` | Optimised release binary — deploy this to FastEdge |
| `build/geoRedirect-debug.wasm` | Debug binary with source maps |

## See Also

- cdn-base skeleton reference
- platform-overview (runtime properties, Geo-IP data)
- deploy skill reference
- manage skill reference (environment variable configuration)

## Source Material

### FILE: examples/geoRedirect/assembly/index.ts

```ts
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy"; // this exports the required functions for the proxy to interact with us.
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
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import {
  getEnv,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

const BAD_GATEWAY: u32 = 502;
const INTERNAL_SERVER_ERROR: u32 = 500;

class GeoRedirectRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new GeoRedirect(context_id, this);
  }
}

class GeoRedirect extends Context {
  constructor(context_id: u32, root_context: GeoRedirectRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    log(LogLevelValues.info, "onRequestHeaders >> ");

    const defaultOrigin = getEnv("DEFAULT");

    if (!defaultOrigin) {
      send_http_response(
        INTERNAL_SERVER_ERROR,
        "internal server error",
        String.UTF8.encode("App misconfigured - DEFAULT must be set"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    const countryArrBuf = get_property("request.country");
    if (countryArrBuf.byteLength === 0) {
      send_http_response(
        BAD_GATEWAY,
        "bad gateway",
        String.UTF8.encode("Missing country information"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }
    const countryCode = String.UTF8.decode(countryArrBuf);
    const countrySpecificOrigin = getEnv(countryCode);

    log(
      LogLevelValues.info,
      `Country code: ( ${countryCode} ): ${
        countrySpecificOrigin === "" ? "no matching origin" : countrySpecificOrigin
      }`,
    );

    const hostArrBuf = get_property("request.host");
    if (hostArrBuf.byteLength > 0) {
      const host = String.UTF8.decode(hostArrBuf);
      log(LogLevelValues.info, `Provided Host: ${host}`);
    }

    const pathArrBuf = get_property("request.path");
    if (pathArrBuf.byteLength === 0) {
      send_http_response(
        INTERNAL_SERVER_ERROR,
        "internal server error",
        String.UTF8.encode("Internal server error - no request path"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    const path = String.UTF8.decode(pathArrBuf);
    const origin = countrySpecificOrigin === "" ? defaultOrigin : countrySpecificOrigin;
    // remove trailing slashes from the origin
    const cleanedOrigin = origin.endsWith("/") ? origin.slice(0, -1) : origin;

    const requestUrl = `${cleanedOrigin}${path}`;

    log(LogLevelValues.info, `request-url: ${requestUrl}`);

    set_property("request.url", String.UTF8.encode(requestUrl));

    return FilterHeadersStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => {
  return new GeoRedirectRoot(context_id);
}, "geoRedirect");
```


### FILE: examples/geoRedirect/package.json

```json
{
  "name": "fastedge-as-example-georedirect",
  "version": "1.0.0",
  "description": "FastEdge AssemblyScript example: Geo Redirect",
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


### FILE: examples/geoRedirect/README.md

```
[← Back to examples](../README.md)

# Geo Redirect

This application redirects requests to different origin URLs based on the client's country code.

## What it does

In `onRequestHeaders`, the app reads the client's country code from the `request.country` runtime property (populated by FastEdge's Geo-IP data) and looks up a matching environment variable by that country code. The `request.url` runtime property is then set to route the upstream fetch to the corresponding origin.

- If a country-specific origin is configured (e.g. env var `DE=https://de.example.com`), the request is routed there.
- Otherwise it falls back to the `DEFAULT` origin.
- Uses [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2) country codes.

> **Routing mechanism:** This is not an HTTP redirect (no `Location` header, no 302 response). Setting `request.url` rewrites the upstream fetch target transparently — the client sees a normal 200 response from the matched origin.

> **Observability:** The app logs the country code, matched origin, and final request URL at INFO level, visible in the FastEdge application logs.

## Configuration

Set the following environment variables on your FastEdge application:

| Variable | Example | Description |
|----------|---------|-------------|
| `DEFAULT` | `https://origin.example.com` | Fallback origin URL (required) |
| `<COUNTRY_CODE>` | `DE=https://de.example.com` | Per-country origin URL (optional, one per country) |

## Build

```sh
pnpm install
pnpm run asbuild
```

Build output:

| File | Description |
|------|-------------|
| `build/geoRedirect.wasm` | Optimised release binary — upload this to FastEdge |
| `build/geoRedirect-debug.wasm` | Debug binary with source maps |

## Deploy

Upload `build/geoRedirect.wasm` to the FastEdge portal and attach it to your CDN application. Configure the `DEFAULT` environment variable and any per-country overrides in the application settings.
```
