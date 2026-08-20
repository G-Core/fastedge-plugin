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
capabilities: [body-manipulation]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/body
---

# Body Manipulation — AssemblyScript (CDN)

## When to Use

Use this feature when you need to inspect, modify, or redact request or response bodies at the CDN layer before forwarding or returning content. Examples: redacting PII from request payloads, logging response bodies, rewriting upstream responses.

## Package

```
@gcoredev/proxy-wasm-sdk-as
```

Entry point: `examples/body/assembly/index.ts`

## Required Imports

```typescript
import {
  BufferTypeValues,
  Context,
  FilterDataStatusValues,
  FilterHeadersStatusValues,
  get_buffer_bytes,
  get_property,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
  set_buffer_bytes,
  set_property,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import { setLogLevel } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
```

Also required at the top of the file:

```typescript
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
```

## Class Structure

```
RootContext subclass  →  createContext() returns Context subclass
Context subclass      →  implements lifecycle hooks
registerRootContext() →  registers the root context factory with a plugin name
```

### RootContext Implementation

```typescript
class HttpBodyRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info); // reduce to LogLevelValues.debug for more logging
    return new HttpBody(context_id, this);
  }
}
```

- `setLogLevel(LogLevelValues.info)` — sets the log verbosity. Reduce to `LogLevelValues.debug` for more detailed output.

### Context Implementation

```typescript
class HttpBody extends Context {
  constructor(context_id: u32, root_context: HttpBodyRoot) {
    super(context_id, root_context);
  }
  // lifecycle hooks ...
}
```

## Lifecycle Hooks

### `onRequestHeaders(headers: u32, end_of_stream: bool): FilterHeadersStatusValues`

Called when request headers arrive. Must remove `content-length` before the body is modified, because the modified body will have a different size.

```typescript
onRequestHeaders(headers: u32, end_of_stream: bool): FilterHeadersStatusValues {
  log(LogLevelValues.debug, "onRequestHeaders >>");
  stream_context.headers.request.remove("content-length");
  return FilterHeadersStatusValues.Continue;
}
```

**Return value**: `FilterHeadersStatusValues.Continue` to proceed.

---

### `onRequestBody(body_buffer_length: usize, end_of_stream: bool): FilterDataStatusValues`

Called (possibly multiple times) as request body chunks arrive. Buffer until `end_of_stream` before acting.

```typescript
onRequestBody(body_buffer_length: usize, end_of_stream: bool): FilterDataStatusValues {
  log(LogLevelValues.debug, "onRequestBody >>");
  if (!end_of_stream) {
    return FilterDataStatusValues.StopIterationAndBuffer;
  }

  const bodyBytes = get_buffer_bytes(
    BufferTypeValues.HttpRequestBody,
    0,
    <u32>body_buffer_length
  );

  if (bodyBytes.byteLength > 0) {
    const bodyStr = String.UTF8.decode(bodyBytes);
    log(LogLevelValues.debug, "onRequestBody >> bodyStr: " + bodyStr);
    if (bodyStr.includes("Client")) {
      const newBody = `Original message body (${body_buffer_length.toString()} bytes) redacted.\n`;
      set_buffer_bytes(
        BufferTypeValues.HttpRequestBody,
        0,
        <u32>body_buffer_length,
        String.UTF8.encode(newBody)
      );
    }
  }
  return FilterDataStatusValues.Continue;
}
```

**Parameters**:
- `body_buffer_length: usize` — total bytes buffered so far
- `end_of_stream: bool` — `true` when the full body is available

**Return values**:
- `FilterDataStatusValues.StopIterationAndBuffer` — pause and accumulate more data
- `FilterDataStatusValues.Continue` — forward the (possibly modified) body

**Body read**: `get_buffer_bytes(BufferTypeValues.HttpRequestBody, offset: u32, max_size: u32): ArrayBuffer`

**Body write**: `set_buffer_bytes(BufferTypeValues.HttpRequestBody, offset: u32, size: u32, data: ArrayBuffer): void`

---

### `onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues`

Called when response headers arrive. Must remove `content-length` and set chunked transfer encoding before the response body is modified. Captures the `content-type` header into a runtime property for use in `onResponseBody`.

```typescript
onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
  log(LogLevelValues.debug, "onResponseHeaders >>");
  stream_context.headers.response.remove("content-length");
  stream_context.headers.response.replace("transfer-encoding", "Chunked");

  const contentType = stream_context.headers.response.get("content-type");
  if (contentType.length > 0) {
    set_property("response.content_type", String.UTF8.encode(contentType));
  }

  return FilterHeadersStatusValues.Continue;
}
```

**Header operations** via `stream_context.headers.response`:
- `.remove(name: string): void` — removes the named header
- `.replace(name: string, value: string): void` — sets or overwrites a header
- `.get(name: string): string` — reads a header value; returns empty string if absent

**Cross-hook coordination**: `set_property("response.content_type", ...)` stores the content type so it can be retrieved in `onResponseBody` via `get_property("response.content_type")`.

---

### `onResponseBody(body_buffer_length: usize, end_of_stream: bool): FilterDataStatusValues`

Called (possibly multiple times) as response body chunks arrive. Buffer until `end_of_stream` before acting.

```typescript
onResponseBody(body_buffer_length: usize, end_of_stream: bool): FilterDataStatusValues {
  log(LogLevelValues.debug, "onResponseBody >>" + end_of_stream.toString());

  if (!end_of_stream) {
    return FilterDataStatusValues.StopIterationAndBuffer;
  }

  log(
    LogLevelValues.debug,
    "onResponseBody >> body_buffer_length: " + body_buffer_length.toString()
  );

  const urlBytes = get_property("request.url");
  const url = urlBytes.byteLength === 0 ? "" : String.UTF8.decode(urlBytes);
  if (url !== "") {
    log(LogLevelValues.info, `url=${url}`);
  }

  const contentTypeBytes = get_property("response.content_type");
  const contentType =
    contentTypeBytes.byteLength === 0
      ? ""
      : String.UTF8.decode(contentTypeBytes);
  if (contentType !== "") {
    log(LogLevelValues.info, `contentType=${contentType}`);
  }

  const bodyBytes = get_buffer_bytes(
    BufferTypeValues.HttpResponseBody,
    0,
    <u32>body_buffer_length
  );

  if (bodyBytes.byteLength > 0) {
    const bodyStr = String.UTF8.decode(bodyBytes);
    log(LogLevelValues.info, "onResponseBody >> bodyStr: " + bodyStr);
  }
  return FilterDataStatusValues.Continue;
}
```

**Body read**: `get_buffer_bytes(BufferTypeValues.HttpResponseBody, offset: u32, max_size: u32): ArrayBuffer`

**Property read**: `get_property(path: string): ArrayBuffer` — returns zero-length buffer if the property is absent.

---

### `onLog(): void`

Called at the end of the request lifecycle. Inherited from `Context`. Used for final audit logging. Not implemented in this example's source.

## Registration

```typescript
registerRootContext((context_id: u32) => {
  return new HttpBodyRoot(context_id);
}, "httpbody");
```

The second argument (`"httpbody"`) is the plugin name string used to match this plugin in the proxy configuration.

## Body Buffering Pattern

```
Return StopIterationAndBuffer on every call where end_of_stream === false
↓
When end_of_stream === true, the full body is in the buffer
↓
Call get_buffer_bytes to read it
↓
Optionally call set_buffer_bytes to overwrite it
↓
Return Continue
```

This pattern applies identically to both `onRequestBody` and `onResponseBody`.

## Header Constraints for Body Modification

When modifying a body, the following header adjustments are required:

| Action | Header | Hook |
|---|---|---|
| Remove | `content-length` | `onRequestHeaders` (for request body changes) |
| Remove | `content-length` | `onResponseHeaders` (for response body changes) |
| Set | `transfer-encoding: Chunked` | `onResponseHeaders` (for response body changes) |

Failure to remove `content-length` will cause downstream length mismatch errors.

## API Reference

### `get_buffer_bytes`

```typescript
get_buffer_bytes(type: BufferTypeValues, start: u32, length: u32): ArrayBuffer
```

- `type`: `BufferTypeValues.HttpRequestBody` or `BufferTypeValues.HttpResponseBody`
- `start`: byte offset (typically `0`)
- `length`: number of bytes to read (use `<u32>body_buffer_length`)
- Returns: `ArrayBuffer` — zero-length if the buffer is empty

### `set_buffer_bytes`

```typescript
set_buffer_bytes(type: BufferTypeValues, start: u32, length: u32, data: ArrayBuffer): void
```

- `type`: `BufferTypeValues.HttpRequestBody` or `BufferTypeValues.HttpResponseBody`
- `start`: byte offset (typically `0`)
- `length`: number of bytes to replace (pass original `body_buffer_length` to replace entire body)
- `data`: new body content as `ArrayBuffer`

### `get_property`

```typescript
get_property(path: string): ArrayBuffer
```

Returns zero-length `ArrayBuffer` if the property does not exist. Decode with `String.UTF8.decode(bytes)`.

### `set_property`

```typescript
set_property(path: string, value: ArrayBuffer): void
```

Stores a value accessible in subsequent hooks within the same request context.

### `log`

```typescript
log(level: LogLevelValues, message: string): void
```

Log levels: `LogLevelValues.debug`, `LogLevelValues.info`, `LogLevelValues.warn`, `LogLevelValues.error`.

### `setLogLevel`

```typescript
setLogLevel(level: LogLevelValues): void
```

Set in `createContext`. Default in this example: `LogLevelValues.info`. Use `LogLevelValues.debug` to enable debug-level output.

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output file | Description |
|---|---|
| `build/body.wasm` | Optimised release binary — upload to FastEdge |
| `build/body-debug.wasm` | Debug binary with source maps |

Build scripts defined in `package.json`:
- `asbuild:debug` — `asc assembly/index.ts --target debug`
- `asbuild:release` — `asc assembly/index.ts --target release`
- `asbuild` — runs both (`npm run asbuild:debug && npm run asbuild:release`)

## Deploy

Upload `build/body.wasm` via the FastEdge portal and attach it to your CDN application.

## See Also

- proxy-wasm-sdk-as SDK reference
- cdn-base skeleton
- FastEdge portal deployment guide
- fastedge-test reference (for testing body manipulation logic)
