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
capabilities: [cache-control, caching]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/cacheControl
---

# Cache Control (AssemblyScript)

Sets `Cache-Control` response headers based on response status and content type. Provides content-type-tiered caching policies with configurable max-age values via environment variables.

## When to Use

Use this feature when you want to set content-type-aware `Cache-Control` headers on responses at the CDN layer, overriding or replacing whatever upstream sends.

## Hook

`onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues`

All logic runs here. No request-phase hooks are used.

## Status Decoding

`get_property("response.status")` returns a 2-byte big-endian `ArrayBuffer`. Decode it as:

```assemblyscript
const statusBuf = get_property("response.status");
let statusCode: u32 = 200;
if (statusBuf.byteLength >= 2) {
  const bytes = Uint8Array.wrap(statusBuf);
  statusCode = (u32(bytes[0]) << 8) | u32(bytes[1]);
}
```

Do NOT attempt to parse this as a UTF-8 string.

## Cache Policy Logic

### Error short-circuit

If `statusCode < 200 || statusCode >= 400`, set `Cache-Control: no-store` and return immediately:

```assemblyscript
stream_context.headers.response.replace("Cache-Control", "no-store");
return FilterHeadersStatusValues.Continue;
```

### Content-type tiers

Read the content type:

```assemblyscript
const contentType = stream_context.headers.response.get("Content-Type");
```

| Condition | `Cache-Control` value | Additional header |
|---|---|---|
| `isStaticAsset(contentType)` | `public, max-age=<STATIC_MAX_AGE>, immutable` | — |
| `contentType.includes("text/html")` | `public, max-age=<HTML_MAX_AGE>, must-revalidate` | `Vary: Accept-Encoding` |
| JSON/XML and `API_MAX_AGE == "0"` | `no-cache, no-store, must-revalidate` | — |
| JSON/XML and `API_MAX_AGE != "0"` | `private, max-age=<API_MAX_AGE>, must-revalidate` | `Vary: Accept, Authorization` |
| Default (all other types) | `public, max-age=600` | — |

JSON/XML applies when `contentType.includes("application/json") || contentType.includes("application/xml")`.

Use `stream_context.headers.response.replace(...)` (not `add`) so any existing upstream `Cache-Control` header is overwritten.

Use `stream_context.headers.response.add(...)` for `Vary` headers.

## Static Asset Detection

Implemented as a **private class method** (not a closure — closures are not supported in AssemblyScript):

```assemblyscript
private isStaticAsset(contentType: string): bool {
  return (
    contentType.includes("image/") ||
    contentType.includes("font/") ||
    contentType.includes("application/javascript") ||
    contentType.includes("text/css") ||
    contentType.includes("text/javascript") ||
    contentType.includes("application/wasm")
  );
}
```

## Environment Variables

Read with `getEnv`. Use an explicit empty-string check (not `||`) because an empty string is pointer-truthy in AssemblyScript:

```assemblyscript
const rawStaticMaxAge = getEnv("STATIC_MAX_AGE");
const staticMaxAge = rawStaticMaxAge === "" ? "31536000" : rawStaticMaxAge;

const rawHtmlMaxAge = getEnv("HTML_MAX_AGE");
const htmlMaxAge = rawHtmlMaxAge === "" ? "3600" : rawHtmlMaxAge;

const rawApiMaxAge = getEnv("API_MAX_AGE");
const apiMaxAge = rawApiMaxAge === "" ? "0" : rawApiMaxAge;
```

| Variable | Default | Description |
|---|---|---|
| `STATIC_MAX_AGE` | `31536000` | Max-age for static assets (seconds) — 1 year |
| `HTML_MAX_AGE` | `3600` | Max-age for HTML responses (seconds) — 1 hour |
| `API_MAX_AGE` | `0` | Max-age for API responses (`0` = no-cache) |

All variables are optional. Defaults are applied when the variable is unset or empty.

## Class Structure

```
CacheControlRoot extends RootContext
  createContext(context_id: u32): Context
    → instantiates CacheControlContext
    → calls setLogLevel(LogLevelValues.info)

CacheControlContext extends Context
  constructor(context_id: u32, root_context: CacheControlRoot)
  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues
  private isStaticAsset(contentType: string): bool

registerRootContext(factory, "cacheControl")
```

No additional dependencies beyond the base CDN skeleton imports.

## Imports Required

```assemblyscript
import {
  Context,
  FilterHeadersStatusValues,
  get_property,
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
```

## Build Output

| File | Description |
|---|---|
| `build/cacheControl.wasm` | Optimised release binary — upload to FastEdge |
| `build/cacheControl-debug.wasm` | Debug binary with source maps |

Build commands:

```sh
pnpm install
pnpm run asbuild
```

Scripts defined in `package.json`:
- `asbuild:debug` — `asc assembly/index.ts --target debug`
- `asbuild:release` — `asc assembly/index.ts --target release`
- `asbuild` — runs both debug and release

## Dependencies

| Package | Version constraint |
|---|---|
| `@gcoredev/proxy-wasm-sdk-as` | `^1.2.3` |
| `assemblyscript` (dev) | `^0.28.9` |
| `@assemblyscript/wasi-shim` (dev) | `^0.1.0` |

## See Also

- cdn-base skeleton (base class structure and proxy-wasm lifecycle)
- sdk-reference assemblyscript (full API surface for stream_context, get_property, getEnv)
- platform-overview (CDN app deployment and environment variable configuration)

## Source Material

### FILE: examples/cacheControl/assembly/index.ts

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
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import {
  getEnv,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

class CacheControlRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new CacheControlContext(context_id, this);
  }
}

class CacheControlContext extends Context {
  constructor(context_id: u32, root_context: CacheControlRoot) {
    super(context_id, root_context);
  }

  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    const statusBuf = get_property("response.status");
    let statusCode: u32 = 200;
    if (statusBuf.byteLength >= 2) {
      const bytes = Uint8Array.wrap(statusBuf);
      statusCode = (u32(bytes[0]) << 8) | u32(bytes[1]);
    }

    // Only cache successful responses
    if (statusCode < 200 || statusCode >= 400) {
      stream_context.headers.response.replace(
        "Cache-Control",
        "no-store",
      );
      return FilterHeadersStatusValues.Continue;
    }

    // Determine cache policy based on content type
    const contentType = stream_context.headers.response.get("Content-Type");

    const rawStaticMaxAge = getEnv("STATIC_MAX_AGE");
    const staticMaxAge = rawStaticMaxAge === "" ? "31536000" : rawStaticMaxAge;
    const rawHtmlMaxAge = getEnv("HTML_MAX_AGE");
    const htmlMaxAge = rawHtmlMaxAge === "" ? "3600" : rawHtmlMaxAge;
    const rawApiMaxAge = getEnv("API_MAX_AGE");
    const apiMaxAge = rawApiMaxAge === "" ? "0" : rawApiMaxAge;

    let cacheControl: string;

    if (this.isStaticAsset(contentType)) {
      // Static assets: long cache, immutable
      cacheControl = "public, max-age=" + staticMaxAge + ", immutable";
    } else if (contentType.includes("text/html")) {
      // HTML: short cache, must revalidate
      cacheControl = "public, max-age=" + htmlMaxAge + ", must-revalidate";
      stream_context.headers.response.add("Vary", "Accept-Encoding");
    } else if (
      contentType.includes("application/json") ||
      contentType.includes("application/xml")
    ) {
      // API responses: configurable, private by default
      if (apiMaxAge === "0") {
        cacheControl = "no-cache, no-store, must-revalidate";
      } else {
        cacheControl = "private, max-age=" + apiMaxAge + ", must-revalidate";
      }
      stream_context.headers.response.add("Vary", "Accept, Authorization");
    } else {
      // Default: moderate cache
      cacheControl = "public, max-age=600";
    }

    stream_context.headers.response.replace("Cache-Control", cacheControl);

    log(
      LogLevelValues.info,
      "Cache-Control: " + cacheControl + " (content-type: " + contentType + ")",
    );

    return FilterHeadersStatusValues.Continue;
  }

  private isStaticAsset(contentType: string): bool {
    return (
      contentType.includes("image/") ||
      contentType.includes("font/") ||
      contentType.includes("application/javascript") ||
      contentType.includes("text/css") ||
      contentType.includes("text/javascript") ||
      contentType.includes("application/wasm")
    );
  }
}

registerRootContext((context_id: u32) => {
  return new CacheControlRoot(context_id);
}, "cacheControl");
```

### FILE: examples/cacheControl/package.json

```json
{
  "name": "fastedge-as-example-cache-control",
  "version": "1.0.0",
  "description": "FastEdge AssemblyScript example: Cache Control — content-type-aware cache headers",
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

### FILE: examples/cacheControl/README.md

```
[← Back to examples](../README.md)

# Cache Control

This application sets `Cache-Control` response headers based on the content type and response status, giving you fine-grained control over CDN caching behaviour.

## What it does

In `onResponseHeaders`, the app inspects the `Content-Type` and `response.status` to apply an appropriate caching policy:

| Content Type | Cache Policy | Default Max-Age |
|---|---|---|
| Images, fonts, JS, CSS, WASM | `public, max-age=<STATIC_MAX_AGE>, immutable` | 1 year (31536000s) |
| `text/html` | `public, max-age=<HTML_MAX_AGE>, must-revalidate` | 1 hour (3600s) |
| `application/json`, `application/xml` | `private, max-age=<API_MAX_AGE>, must-revalidate` or `no-cache, no-store` | 0 (no cache) |
| Other | `public, max-age=600` | 10 minutes |
| Error responses (4xx/5xx) | `no-store` | — |

Also adds `Vary` headers where appropriate (`Accept-Encoding` for HTML, `Accept, Authorization` for API responses).

## Configuration

All environment variables are optional — sensible defaults are applied when unset.

| Variable | Default | Description |
|----------|---------|-------------|
| `STATIC_MAX_AGE` | `31536000` | Max-age for static assets (seconds) |
| `HTML_MAX_AGE` | `3600` | Max-age for HTML responses (seconds) |
| `API_MAX_AGE` | `0` | Max-age for API responses (0 = no-cache) |

## Build

```sh
pnpm install
pnpm run asbuild
```

Build output:

| File | Description |
|------|-------------|
| `build/cacheControl.wasm` | Optimised release binary — upload this to FastEdge |
| `build/cacheControl-debug.wasm` | Debug binary with source maps |

## Deploy

Upload `build/cacheControl.wasm` to the FastEdge portal and attach it to your CDN application. Optionally configure the max-age environment variables.
```
