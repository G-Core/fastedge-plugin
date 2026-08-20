<!--
  auto-updated: true
  sources:
    - id: proxy-wasm-sdk-as
      ref: master
      commit: 8e3bb621bc013a0aed7e52122066b417ad62a207
      updated: 2026-08-20
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
