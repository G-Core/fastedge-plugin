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
capabilities: [http-call, async-dispatch, outbound]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/httpCall
---

# HTTP Call — AssemblyScript (CDN)

Dispatches an asynchronous outbound HTTP request from within a CDN filter using the proxy-wasm HTTP dispatch API. The hook pauses until the response arrives; a re-dispatch latch ensures the second invocation of `onRequestHeaders` continues the request instead of firing another call.

## When to Use

Use this pattern when you need to make async outbound HTTP calls to external services from a CDN filter at the CDN layer — for example, to enrich request context, call a backend API, or validate credentials before forwarding the request.

---

## API Reference

### `httpCall(upstream, headers, body, trailers, timeoutMs, ctx, callback)`

Dispatched from the root context (not the stream context). Sends an asynchronous outbound HTTP request.

**Call site:**
```assemblyscript
const result = (this.root_context as HttpCallRoot).httpCall(
  "httpbin.org",           // upstream: string — cluster/host name
  headers,                 // headers: Array<HeaderPair> — pseudo-headers + custom headers
  new ArrayBuffer(0),      // body: ArrayBuffer — request body (empty if none)
  new Array<HeaderPair>(), // trailers: Array<HeaderPair>
  3000,                    // timeoutMs: u32 — timeout in milliseconds
  this,                    // ctx: Context — originating context
  handleHttpCallResponse,  // callback: (ctx: BaseContext, hdrs: u32, bodySize: usize, trls: u32) => void
);
```

**Parameters:**

| Parameter    | Type                  | Description |
|--------------|-----------------------|-------------|
| `upstream`   | `string`              | Cluster/host name for the outbound request |
| `headers`    | `Array<HeaderPair>`   | Request headers including required pseudo-headers |
| `body`       | `ArrayBuffer`         | Request body; pass `new ArrayBuffer(0)` for no body |
| `trailers`   | `Array<HeaderPair>`   | Request trailers; pass `new Array<HeaderPair>()` if none |
| `timeoutMs`  | `u32`                 | Timeout in milliseconds for the outbound call |
| `ctx`        | `Context`             | Originating context instance |
| `callback`   | function              | Response callback — see signature below |

**Returns:** `WasmResultValues` — `WasmResultValues.Ok` on successful dispatch; any other value indicates failure (invalid arguments, etc.).

---

### Pseudo-header Construction

Required pseudo-headers must be pushed to an `Array<HeaderPair>` using `makeHeaderPair`:

```assemblyscript
const headers = new Array<HeaderPair>();
headers.push(makeHeaderPair(":scheme", "https"));
headers.push(makeHeaderPair(":authority", "httpbin.org"));
headers.push(makeHeaderPair(":path", "/ip"));
headers.push(makeHeaderPair(":method", "GET"));
headers.push(makeHeaderPair("User-Agent", "fastedge")); // optional custom headers
```

Required pseudo-headers: `:scheme`, `:authority`, `:path`, `:method`.

---

### Response Callback Signature

```assemblyscript
function handleHttpCallResponse(
  ctx: BaseContext,
  hdrs: u32,
  bodySize: usize,
  trls: u32,
): void
```

**Parameters:**

| Parameter  | Type        | Description |
|------------|-------------|-------------|
| `ctx`      | `BaseContext` | Originating context |
| `hdrs`     | `u32`       | Number of response headers; `0` indicates failure (timeout, DNS error, etc.) |
| `bodySize` | `usize`     | Size of the response body in bytes |
| `trls`     | `u32`       | Number of response trailers |

---

### Reading Response Headers Inside the Callback

```assemblyscript
const userAgent = stream_context.headers.http_callback.get("user-agent");
```

`stream_context.headers.http_callback` provides access to HTTP call response headers inside the callback. The SDK sets the effective context before the callback fires so lookups resolve against the originating request.

---

### Reading the Response Body Inside the Callback

```assemblyscript
if (bodySize > 0) {
  const bodyBytes = get_buffer_bytes(
    BufferTypeValues.HttpCallResponseBody,
    0,
    bodySize as u32,
  );
  const bodyStr = String.UTF8.decode(bodyBytes);
}
```

Use `get_buffer_bytes(BufferTypeValues.HttpCallResponseBody, 0, bodySize as u32)` to read the response body. Only call this when `bodySize > 0`.

---

## Re-dispatch Latch Pattern

FastEdge re-invokes `onRequestHeaders` on the same `Context` instance after the HTTP call response callback completes. Without a latch, this re-invocation would dispatch another HTTP call, creating an infinite loop.

**Pattern:** Declare a `bool` instance field on the `Context` class. On first invocation, return `StopIteration`. After the callback fires and FastEdge re-enters the hook, the latch is `true` — return `Continue`.

```assemblyscript
class HttpCallContext extends Context {
  httpCallDispatched: bool = false;

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    if (this.httpCallDispatched) {
      // Second invocation — response callback has run; continue the request.
      return FilterHeadersStatusValues.Continue;
    }

    // First invocation — dispatch the HTTP call.
    // ... build headers, call httpCall() ...

    this.httpCallDispatched = true;
    return FilterHeadersStatusValues.StopIteration; // pause until response arrives
  }
}
```

**FastEdge resume model:** Returning `FilterHeadersStatusValues.StopIteration` pauses the hook. The runtime processes the HTTP response, invokes the callback, then re-invokes `onRequestHeaders`. Calling `continueRequest()` is not required and has no effect on FastEdge (differs from canonical proxy-wasm).

---

## Error Handling

### Dispatch failure (dispatch returns non-Ok)

```assemblyscript
if (result != WasmResultValues.Ok) {
  log(
    LogLevelValues.error,
    "Failed to dispatch HTTP call: " + result.toString(),
  );
  send_http_response(
    INTERNAL_SERVER_ERROR,
    "internal server error",
    String.UTF8.encode("Failed to dispatch HTTP call"),
    [],
  );
  return FilterHeadersStatusValues.StopIteration;
}
```

When `httpCall()` returns anything other than `WasmResultValues.Ok`, return a 500 to the client via `send_http_response`.

### Callback: call failed (hdrs == 0)

```assemblyscript
if (hdrs == 0) {
  log(LogLevelValues.error, "HTTP call failed — no response received");
  return;
}
```

A `hdrs` value of `0` inside the callback indicates the call failed (timeout, DNS error, connection refused, etc.). Log the error and return early; do not attempt to read headers or body.

---

## Imports Required

```assemblyscript
import {
  BaseContext,
  BufferTypeValues,
  Context,
  FilterHeadersStatusValues,
  get_buffer_bytes,
  HeaderPair,
  log,
  LogLevelValues,
  makeHeaderPair,
  registerRootContext,
  RootContext,
  send_http_response,
  stream_context,
  WasmResultValues,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import { setLogLevel } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
```

---

## Class Structure

```assemblyscript
class HttpCallRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new HttpCallContext(context_id, this);
  }
}

class HttpCallContext extends Context {
  httpCallDispatched: bool = false;

  constructor(context_id: u32, root_context: HttpCallRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues { ... }
}

registerRootContext((context_id: u32) => {
  return new HttpCallRoot(context_id);
}, "httpCall");
```

`httpCall()` must be called on the root context — cast `this.root_context` to the concrete root type before calling.

---

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output file | Description |
|-------------|-------------|
| `build/httpCall.wasm` | Optimised release binary — upload this to FastEdge |
| `build/httpCall-debug.wasm` | Debug binary with source maps |

**Package:** `@gcoredev/proxy-wasm-sdk-as` `^1.2.3`

---

## Timeout Guidance

The example uses `3000` ms. This accommodates cold DNS lookup and variable network conditions. Tune per upstream in production — low-latency internal services can use a shorter timeout; high-latency external APIs may require more.

---

## Constraints

- `httpCall()` must be invoked from the root context, not the stream context.
- Pseudo-headers (`:scheme`, `:authority`, `:path`, `:method`) are required; omitting them causes dispatch failure.
- `get_buffer_bytes(BufferTypeValues.HttpCallResponseBody, ...)` is only valid inside the response callback.
- `stream_context.headers.http_callback` is only valid inside the response callback.
- Do not call `continueRequest()` — it has no effect on FastEdge and is not required.
- The re-dispatch latch (`httpCallDispatched`) is required to prevent infinite re-dispatch on the second `onRequestHeaders` invocation.

---

## See Also

- proxy-wasm-sdk-as SDK reference (AssemblyScript)
- CDN base skeleton reference
- Outbound HTTP section in the platform overview
- FastEdge error codes reference
