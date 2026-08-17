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
capabilities: [header-manipulation]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/headers
---

# Feature: Header Manipulation (AssemblyScript)

## When to Use

Use this feature when you need to add, remove, or modify HTTP headers on requests or responses at the CDN layer, or when you need to validate that specific headers are present after mutation.

## Overview

This feature demonstrates the complete header manipulation API available via `stream_context.headers.request` and `stream_context.headers.response`. It covers reading, adding, replacing, removing, and validating headers in both the `onRequestHeaders` and `onResponseHeaders` lifecycle hooks. It also demonstrates cross-phase response header writes from within the request phase.

## Package

```
@gcoredev/proxy-wasm-sdk-as
```

Package name for this example: `fastedge-as-example-headers`

## Imports Required

```typescript
import {
  Context,
  FilterHeadersStatusValues,
  Headers,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
  send_http_response,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import { setLogLevel } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
```

Export required for proxy interaction:

```typescript
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
```

## Header API

All header operations are accessed via `stream_context.headers.request` or `stream_context.headers.response`.

### `get(name: string): string`

Returns the value of the named header. Returns an empty string if the header is not present.

```typescript
const hostHeader = stream_context.headers.request.get("host");
```

### `get_headers(): Headers`

Returns all headers as a `Headers` array. Each element has `.key` and `.value` as `ArrayBuffer` (decode with `String.UTF8.decode`).

```typescript
const headers: Headers = stream_context.headers.request.get_headers();
for (let i = 0; i < headers.length; i++) {
  const name = String.UTF8.decode(headers[i].key);
  const value = String.UTF8.decode(headers[i].value);
}
```

### `add(name: string, value: string): void`

Adds a header. Multiple calls with the same name produce multiple header entries (multi-value header).

```typescript
stream_context.headers.request.add("new-header-03", "value-03");
stream_context.headers.request.add("new-header-03", "value-03-a");
// Results in two entries for new-header-03
```

### `replace(name: string, value: string): void`

Replaces the value of an existing header. On FastEdge, `replace()` upserts — it will create the header if absent. Guard with a presence check when you only want to modify an existing header.

```typescript
const cacheControl = stream_context.headers.response.get("cache-control");
if (cacheControl.length > 0) {
  stream_context.headers.response.replace("cache-control", "");
}
```

### `remove(name: string): void`

Attempts to remove a header by name.

**Known constraint**: Nginx does not allow deleting headers. Calling `remove()` sets the header value to an empty string rather than removing it entirely.

```typescript
stream_context.headers.request.remove("new-header-01");
// new-header-01 remains present with value ""
```

## Lifecycle Constraints

| Operation | `onRequestHeaders` | `onResponseHeaders` |
|---|---|---|
| Read/write request headers | Supported | Not applicable |
| Read/write response headers | Partially supported — `add()` works; `get()`/`replace()` may return empty or be a no-op if headers are not yet available | Supported |
| `get` on unavailable headers | Returns empty string | Returns empty string |

Attempting to call `stream_context.headers.response.get(...)` or `.replace(...)` in `onRequestHeaders` will not panic but may return empty or be silently ignored if the response headers are not yet available. Always guard with a length check:

```typescript
const newResponseHeader = stream_context.headers.response.get("new-response-header");
if (newResponseHeader.length > 0) {
  stream_context.headers.response.replace("new-response-header", "value-02");
}
```

### Cross-Phase Response Header Writes

`stream_context.headers.response.add(...)` can be called from `onRequestHeaders`. Headers written in the request phase appear in the final response alongside those set in `onResponseHeaders`. This is an advanced technique; read/replace on response headers in the request phase is guarded by a presence check.

## Return Values

Both `onRequestHeaders` and `onResponseHeaders` return `FilterHeadersStatusValues`:

| Value | Meaning |
|---|---|
| `FilterHeadersStatusValues.Continue` | Pass the request/response downstream |
| `FilterHeadersStatusValues.StopIteration` | Halt processing; typically paired with `send_http_response` |

## Error Response Pattern

```typescript
send_http_response(
  550,                                          // HTTP status code
  "internal server error",                      // status message
  String.UTF8.encode("Internal server error"),  // body as ArrayBuffer
  [],                                           // additional headers
);
return FilterHeadersStatusValues.StopIteration;
```

Error codes used in this example:

| Code | Condition |
|---|---|
| 550 | No headers present (empty header set) |
| 551 | Required header present but empty |
| 552 | Unexpected headers found after mutation (missing or extra) |

## Header Validation Pattern

Use a `HeaderDiff` class with `missing` and `extra` sets to perform a symmetric diff. Validation is scoped to `new-header-*` prefixed entries — other headers are deliberately ignored so application-style headers (e.g. `set-cookie`) do not need to be enumerated in the expected set.

```typescript
class HeaderDiff {
  missing: Set<string>;
  extra: Set<string>;

  constructor() {
    this.missing = new Set<string>();
    this.extra = new Set<string>();
  }
}

function collectHeaders(headers: Headers, logHeaders: bool = true): Set<string> {
  const set = new Set<string>();
  for (let i = 0; i < headers.length; i++) {
    const name = String.UTF8.decode(headers[i].key);
    const value = String.UTF8.decode(headers[i].value);
    if (logHeaders) log(LogLevelValues.info, `#header -> ${name}: ${value}`);
    set.add(`${name}:${value}`);
  }
  return set;
}

function validateHeaders(headers: Headers, expectedHeaders: Set<string>): HeaderDiff {
  const result = new HeaderDiff();
  const headersArr = collectHeaders(headers, false).values();
  const actualNewHeaders = new Set<string>();

  for (let i = 0; i < headersArr.length; i++) {
    const header = headersArr[i];
    if (header.startsWith("new-header-")) {
      actualNewHeaders.add(header);
      if (!expectedHeaders.has(header)) result.extra.add(header);
    }
  }

  const expectedArr = expectedHeaders.values();
  for (let i = 0; i < expectedArr.length; i++) {
    const e = expectedArr[i];
    if (!actualNewHeaders.has(e)) result.missing.add(e);
  }

  return result;
}
```

Usage:

```typescript
// Note: remove() sets value to "" (nginx cannot delete) — include "name:" in expected set
const expectedHeaders = new Set<string>();
expectedHeaders.add("new-header-01:");
expectedHeaders.add("new-header-02:new-value-02");
expectedHeaders.add("new-header-03:value-03");
expectedHeaders.add("new-header-03:value-03-a");

const diff = validateHeaders(
  stream_context.headers.request.get_headers(),
  expectedHeaders,
);

if (diff.missing.size > 0 || diff.extra.size > 0) {
  log(
    LogLevelValues.warn,
    `Request header mismatch | missing: ${diff.missing.values().join(", ")} | extra: ${diff.extra.values().join(", ")}`,
  );
  send_http_response(552, "internal server error", String.UTF8.encode("Internal server error"), []);
  return FilterHeadersStatusValues.StopIteration;
}
```

## Complete Mutation Sequence (Request Phase)

```typescript
// Add headers
stream_context.headers.request.add("new-header-01", "value-01");
stream_context.headers.request.add("new-header-02", "value-02");
stream_context.headers.request.add("new-header-03", "value-03");

// Remove (sets to empty string in nginx — does not delete)
stream_context.headers.request.remove("new-header-01");

// Replace value
stream_context.headers.request.replace("new-header-02", "new-value-02");

// Add a second value for the same header name
stream_context.headers.request.add("new-header-03", "value-03-a");

// Cross-phase: write a response header from the request phase
stream_context.headers.response.add("new-response-header", "value-01");

// Guard replace with presence check — replace() upserts, so without this
// an absent header would be created with an empty value
const cacheControlHeader = stream_context.headers.response.get("cache-control");
if (cacheControlHeader.length > 0) {
  stream_context.headers.response.replace("cache-control", "");
}

const newResponseHeader = stream_context.headers.response.get("new-response-header");
if (newResponseHeader.length > 0) {
  stream_context.headers.response.replace("new-response-header", "value-02");
}
```

Resulting effective request headers after mutation:

| Header | Value |
|---|---|
| `new-header-01` | `""` (empty — nginx cannot delete) |
| `new-header-02` | `new-value-02` |
| `new-header-03` | `value-03` and `value-03-a` (multi-value) |

The same add/remove/replace sequence is repeated identically in `onResponseHeaders` for response headers.

## Complete Mutation Sequence (Response Phase)

```typescript
// Add headers
stream_context.headers.response.add("new-header-01", "value-01");
stream_context.headers.response.add("new-header-02", "value-02");
stream_context.headers.response.add("new-header-03", "value-03");

// Remove (sets to empty string in nginx — does not delete)
stream_context.headers.response.remove("new-header-01");

// Replace value
stream_context.headers.response.replace("new-header-02", "new-value-02");

// Add a second value for the same header name
stream_context.headers.response.add("new-header-03", "value-03-a");
```

Resulting effective response headers after mutation:

| Header | Value |
|---|---|
| `new-header-01` | `""` (empty — nginx cannot delete) |
| `new-header-02` | `new-value-02` |
| `new-header-03` | `value-03` and `value-03-a` (multi-value) |

## Class Structure

```typescript
class HttpHeadersRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new HttpHeaders(context_id, this);
  }
}

class HttpHeaders extends Context {
  constructor(context_id: u32, root_context: HttpHeadersRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues { ... }
  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues { ... }
}

registerRootContext((context_id: u32) => {
  return new HttpHeadersRoot(context_id);
}, "httpheaders");
```

## Logging

```typescript
setLogLevel(LogLevelValues.info); // Set in createContext; reduce to .debug for verbose output

log(LogLevelValues.info, `#header -> ${name}: ${value}`);
log(LogLevelValues.debug, "onRequestHeaders >> ");
log(LogLevelValues.debug, "onResponseHeaders >> ");
log(LogLevelValues.warn, `Request header mismatch | missing: ${diff.missing.values().join(", ")} | extra: ${diff.extra.values().join(", ")}`);
log(LogLevelValues.warn, `Response header mismatch | missing: ${diff.missing.values().join(", ")} | extra: ${diff.extra.values().join(", ")}`);
log(LogLevelValues.debug, `onRequestHeaders: OK!`);
log(LogLevelValues.debug, `onResponseHeaders: OK!`);
```

## Build Output

| File | Description |
|---|---|
| `build/headers.wasm` | Optimised release binary — upload to FastEdge |
| `build/headers-debug.wasm` | Debug binary with source maps |

Build commands:

```sh
pnpm install
pnpm run asbuild          # builds both debug and release
pnpm run asbuild:release  # release only
pnpm run asbuild:debug    # debug only
```

## Deployment

Upload `build/headers.wasm` to the FastEdge portal and attach it to your CDN application. No environment variables are required.

## See Also

- proxy-wasm-sdk-as SDK reference
- cdn-base skeleton
- platform-overview (lifecycle hook execution order)
- host-services reference (send_http_response, log)
