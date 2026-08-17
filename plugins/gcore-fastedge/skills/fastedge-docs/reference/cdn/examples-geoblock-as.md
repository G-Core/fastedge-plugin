<!--
  auto-updated: true
  sources:
    - id: proxy-wasm-sdk-as
      ref: master
      commit: 8e3bb621bc013a0aed7e52122066b417ad62a207
      updated: 2026-08-17
-->

---
type: example
app_type: cdn
languages: [assemblyscript]
capabilities: [geoblock, geo-filtering, country-detection, access-control]
---

# Geoblock — CDN App Example (AssemblyScript)

Country-based request blocking for CDN apps using the proxy-wasm AssemblyScript SDK. Reads the client country from a request property, checks it against a configurable blacklist, and blocks matching requests before they reach origin. Both blocked and allowed requests are logged at INFO level for audit purposes.

---

## Overview

- **App type**: CDN (proxy-wasm `Context`)
- **Language**: AssemblyScript
- **Package**: `@gcoredev/proxy-wasm-sdk-as`
- **Entry export**: `export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy"`
- **Root context name**: `"geoBlock"` (passed to `registerRootContext`)

---

## Environment Variables

| Variable | Required | Type | Description |
|---|---|---|---|
| `BLACKLIST` | Yes | `string` | Comma-separated list of ISO 3166-1 alpha-2 country codes to block (e.g. `RU,CN,KP`) |

If `BLACKLIST` is absent or parses to zero entries, the app returns 500 and halts the request.

---

## Request Property

| Property path | Type | Description |
|---|---|---|
| `request.country` | `ArrayBuffer` (UTF-8 bytes) | Two-letter ISO country code injected by the CDN edge from Geo-IP data — no additional configuration required |

Retrieved via `get_property("request.country")`. Returns an `ArrayBuffer` with `byteLength === 0` if the property is absent.

Decode to string: `String.UTF8.decode(country)`.

---

## Context Types

### `GeoBlockRoot`

Extends `RootContext`.

| Method | Return | Description |
|---|---|---|
| `createContext(context_id: u32)` | `Context` | Sets log level to `LogLevelValues.info` via `setLogLevel`, then returns a new `GeoBlock` instance for each request |

### `GeoBlock`

Extends `Context`.

| Method | Signature | Description |
|---|---|---|
| `constructor` | `(context_id: u32, root_context: GeoBlockRoot)` | Calls `super(context_id, root_context)` |
| `onRequestHeaders` | `(a: u32, end_of_stream: bool): FilterHeadersStatusValues` | Main filter hook — all blocking logic executes here |

---

## Control Flow

### `onRequestHeaders`

Executes on every inbound request before forwarding to origin.

1. Read `BLACKLIST` env var via `getEnv("BLACKLIST")`. If falsy (null/empty) → send 500 `App misconfigured`, return `FilterHeadersStatusValues.StopIteration`.
2. Split blacklist on `","` → `Array<string>`. Map each entry through `.trim()`.
3. If parsed array length is 0 → send 500 `App misconfigured`, return `FilterHeadersStatusValues.StopIteration`.
4. Read `request.country` via `get_property("request.country")`. Returns `ArrayBuffer`. If `byteLength === 0` → send 502 `Missing country information`, return `FilterHeadersStatusValues.StopIteration`.
5. Decode country bytes: `String.UTF8.decode(country)` → `countryStr`.
6. If `blacklistedCountries.includes(countryStr)` → emit INFO log `"geoBlock: blocked request from " + countryStr`, send 403 `Request blacklisted`, return `FilterHeadersStatusValues.StopIteration`.
7. Otherwise → emit INFO log `"geoBlock: allowed request from " + countryStr`, return `FilterHeadersStatusValues.Continue`.

---

## Response Codes

| Condition | HTTP Status | Reason phrase | Body |
|---|---|---|---|
| `BLACKLIST` env var missing or falsy | 500 | `"internal server error"` | `App misconfigured` |
| `BLACKLIST` parses to zero entries | 500 | `"internal server error"` | `App misconfigured` |
| `request.country` property absent (`byteLength === 0`) | 502 | `"internal server error"` | `Missing country information` |
| Country code matches blacklist | 403 | `"forbidden"` | `Request blacklisted` |
| Country code not in blacklist | — | — | Request forwarded (`Continue`) |

`send_http_response` signature: `send_http_response(status: u32, reason: string, body: Uint8Array, headers: Array<...>)`. Body is encoded via `String.UTF8.encode(...)`.

---

## Constants

```typescript
const BAD_GATEWAY: u32 = 502;
const FORBIDDEN: u32 = 403;
const INTERNAL_SERVER_ERROR: u32 = 500;
```

---

## Registration

```typescript
registerRootContext((context_id: u32) => {
  return new GeoBlockRoot(context_id);
}, "geoBlock");
```

The second argument `"geoBlock"` is the filter name used by the proxy runtime.

---

## Build

```sh
npm install
npm run asbuild:release
```

| Script | Command |
|---|---|
| `asbuild:debug` | `asc assembly/index.ts --target debug` |
| `asbuild:release` | `asc assembly/index.ts --target release` |
| `asbuild` | Runs both debug and release |

Build outputs:

| File | Description |
|---|---|
| `build/geoBlock.wasm` | Optimised release binary — upload to FastEdge |
| `build/geoBlock-debug.wasm` | Debug binary with source maps |

---

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

---

## Gotchas

- **Property type is `ArrayBuffer`**: `get_property("request.country")` returns an `ArrayBuffer`, not a string. Always check `byteLength === 0` for absence, then decode with `String.UTF8.decode(...)`.
- **Country code format**: The runtime injects a 2-letter ISO 3166-1 alpha-2 code from Geo-IP data (e.g. `RU`, `CN`). FastEdge always provides uppercase codes. Matching is case-sensitive — `includes()` does exact string comparison. Ensure blacklist entries use uppercase codes.
- **Whitespace trimming**: The blacklist parser calls `.trim()` on each split token, so `"RU, CN, KP"` is handled correctly. However, the decoded `countryStr` from the property is not trimmed — trailing bytes in the property would cause a mismatch.
- **`send_http_response` + `StopIteration`**: All blocking paths call `send_http_response` then return `StopIteration`. The request is halted and the synthetic response is sent to the client; origin is never contacted.
- **Log level initialization**: `setLogLevel(LogLevelValues.info)` is called in `createContext` (root context), not in `onRequestHeaders`. This sets the log level once per context lifecycle, not per request.
- **Audit logging**: Both blocked and allowed requests emit an INFO log entry. This provides a full audit trail of all geoblock decisions.
- **No time-window support**: Unlike the Rust geoblock example, this AssemblyScript implementation does not support time-bounded blocking. The blacklist applies unconditionally.

---

## See Also

- proxy-wasm-sdk-as SDK reference (AssemblyScript host API, `get_property`, `send_http_response`, `FilterHeadersStatusValues`, `getEnv`, `setLogLevel`)
- FastEdge CDN app platform overview (available request properties, country detection)
- FastEdge environment variable configuration (setting `BLACKLIST` at deploy time)
- examples-geoblock-rust reference (equivalent Rust implementation with time-window support)
- FastEdge error codes reference (530–533 runtime errors)

## Source Material

### FILE: examples/geoBlock/assembly/index.ts

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
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import {
  getEnv,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

const BAD_GATEWAY: u32 = 502;
const FORBIDDEN: u32 = 403;
const INTERNAL_SERVER_ERROR: u32 = 500;

class GeoBlockRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new GeoBlock(context_id, this);
  }
}

class GeoBlock extends Context {
  constructor(context_id: u32, root_context: GeoBlockRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    const blacklist = getEnv("BLACKLIST");
    if (!blacklist) {
      send_http_response(
        INTERNAL_SERVER_ERROR,
        "internal server error",
        String.UTF8.encode("App misconfigured"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    const blacklistedCountries = blacklist
      .split(",")
      .map<string>((c) => c.trim());

    if (blacklistedCountries.length === 0) {
      send_http_response(
        INTERNAL_SERVER_ERROR,
        "internal server error",
        String.UTF8.encode("App misconfigured"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    const country = get_property("request.country");
    if (country.byteLength === 0) {
      send_http_response(
        BAD_GATEWAY,
        "internal server error",
        String.UTF8.encode("Missing country information"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    const countryStr = String.UTF8.decode(country);
    if (blacklistedCountries.includes(countryStr)) {
      log(LogLevelValues.info, "geoBlock: blocked request from " + countryStr);
      send_http_response(
        FORBIDDEN,
        "forbidden",
        String.UTF8.encode("Request blacklisted"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    log(LogLevelValues.info, "geoBlock: allowed request from " + countryStr);
    return FilterHeadersStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => {
  return new GeoBlockRoot(context_id);
}, "geoBlock");
```


### FILE: examples/geoBlock/package.json

```json
{
  "name": "fastedge-as-example-geoblock",
  "version": "1.0.0",
  "description": "FastEdge AssemblyScript example: Geo Block",
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


### FILE: examples/geoBlock/README.md

```
[← Back to examples](../README.md)

# Geo Block

This application blocks incoming requests based on the client's country code.

## What it does

In `onRequestHeaders`, the app reads a `BLACKLIST` environment variable containing a comma-separated list of [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2) country codes (e.g. `RU,CN,KP`). The request's country code is obtained from the `request.country` runtime property, which FastEdge populates from its Geo-IP data — no additional configuration is required to access it.

- If the country code appears in the blacklist, an INFO log is emitted and the request is rejected with a `403 Forbidden`.
- Allowed requests are also logged at INFO level, providing an audit trail for both blocked and permitted traffic.
- If the `BLACKLIST` env var is missing or the country cannot be determined, an appropriate error is returned.

> **Note on country code matching:** Comparison is exact-match and case-sensitive. FastEdge always provides uppercase ISO 3166-1 alpha-2 codes (e.g. `CN`, `RU`). Ensure your `BLACKLIST` values use uppercase accordingly.

## Configuration

Set the following environment variable on your FastEdge application:

| Variable    | Example    | Description                                   |
| ----------- | ---------- | --------------------------------------------- |
| `BLACKLIST` | `RU,CN,KP` | Comma-separated list of blocked country codes |

## Build

```sh
pnpm install
pnpm run asbuild
```

Build output:

| File                        | Description                                        |
| --------------------------- | -------------------------------------------------- |
| `build/geoBlock.wasm`       | Optimised release binary — upload this to FastEdge |
| `build/geoBlock-debug.wasm` | Debug binary with source maps                      |

## Deploy

Upload `build/geoBlock.wasm` to the FastEdge portal and attach it to your CDN application. Configure the `BLACKLIST` environment variable in the application settings.
```
