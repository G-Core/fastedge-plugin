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
capabilities: [error-pages, response-body]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/customErrorPages
---

# Custom Error Pages (AssemblyScript)

Intercept 4xx and 5xx upstream responses and replace them with clean, branded HTML error pages at the CDN layer.

## When to Use

Use this feature when you want to replace default upstream 4xx/5xx error responses with a custom branded HTML error page, without modifying the origin server.

## Hooks Used

| Hook | Purpose |
|---|---|
| `onResponseHeaders` | Detect error status; set response headers for HTML body |
| `onResponseBody` | Buffer full response body; replace with generated HTML |

---

## Status Decoding

`get_property("response.status")` returns a **2-byte big-endian** `ArrayBuffer`. It is NOT a UTF-8 string.

```typescript
const statusBuf = get_property("response.status");
if (statusBuf.byteLength < 2) {
  return FilterHeadersStatusValues.Continue;
}
const bytes = Uint8Array.wrap(statusBuf);
const code: u32 = (u32(bytes[0]) << 8) | u32(bytes[1]);
```

**Critical**: The status must be re-read from the property in `onResponseBody`. Instance state set in `onResponseHeaders` does **not** survive the hop to `onResponseBody`.

---

## onResponseHeaders

Detects error status and prepares headers for HTML body replacement.

```typescript
onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
  const statusBuf = get_property("response.status");
  if (statusBuf.byteLength < 2) {
    return FilterHeadersStatusValues.Continue;
  }

  const bytes = Uint8Array.wrap(statusBuf);
  const code: u32 = (u32(bytes[0]) << 8) | u32(bytes[1]);

  if (code >= 400 && code < 600) {
    stream_context.headers.response.replace("Content-Type", "text/html");
    stream_context.headers.response.remove("Content-Length");
    stream_context.headers.response.replace("Transfer-Encoding", "Chunked");

    log(LogLevelValues.info, "Error response detected: " + code.toString());
  }

  return FilterHeadersStatusValues.Continue;
}
```

**Header operations on error (400–599):**

| Operation | Header | Value |
|---|---|---|
| `replace` | `Content-Type` | `text/html` |
| `remove` | `Content-Length` | — |
| `replace` | `Transfer-Encoding` | `Chunked` |

Note: `remove("Content-Length")` uses the FastEdge CDN platform's empty-string-set behavior — it is not a true header delete primitive.

---

## onResponseBody

Buffers the full body until `end_of_stream`, then replaces it with generated HTML.

```typescript
onResponseBody(
  body_buffer_length: usize,
  end_of_stream: bool,
): FilterDataStatusValues {
  // Re-read status — instance state from onResponseHeaders does not survive
  const statusBuf = get_property("response.status");
  if (statusBuf.byteLength < 2) {
    return FilterDataStatusValues.Continue;
  }

  const bytes = Uint8Array.wrap(statusBuf);
  const code: u32 = (u32(bytes[0]) << 8) | u32(bytes[1]);

  if (code < 400 || code >= 600) {
    return FilterDataStatusValues.Continue;
  }

  if (!end_of_stream) {
    return FilterDataStatusValues.StopIterationAndBuffer;
  }

  const title = this.getErrorTitle(code);
  const description = this.getErrorDescription(code);
  const category = code >= 500 ? "Server Error" : "Client Error";

  const html =
    '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' +
    "<title>" + code.toString() + " — " + title + "</title>" +
    "<style>" +
    "body{margin:0;font-family:-apple-system,BlinkMacSystemFont,sans-serif;" +
    "display:flex;align-items:center;justify-content:center;min-height:100vh;" +
    "background:#f8f9fa;color:#333}" +
    ".container{text-align:center;padding:2rem;max-width:480px}" +
    ".code{font-size:6rem;font-weight:700;color:#dee2e6;margin:0;line-height:1}" +
    ".title{font-size:1.5rem;font-weight:600;margin:1rem 0 .5rem}" +
    ".desc{color:#6c757d;line-height:1.6}" +
    ".category{font-size:.75rem;text-transform:uppercase;letter-spacing:.1em;color:#adb5bd;margin-top:2rem}" +
    "</style></head><body><div class='container'>" +
    "<p class='code'>" + code.toString() + "</p>" +
    "<h1 class='title'>" + title + "</h1>" +
    "<p class='desc'>" + description + "</p>" +
    "<p class='category'>" + category + "</p>" +
    "</div></body></html>";

  const body = String.UTF8.encode(html);
  // Replace the entire original body — pass body_buffer_length as the length
  // to replace, not body.byteLength. Otherwise any original bytes beyond the
  // new body's length survive at the tail of the response.
  set_buffer_bytes(
    BufferTypeValues.HttpResponseBody,
    0,
    body_buffer_length as u32,
    body,
  );

  return FilterDataStatusValues.Continue;
}
```

**Body replacement rule**: Pass `body_buffer_length as u32` (the original body length) as the replacement length argument to `set_buffer_bytes`, not the new body's `byteLength`. Using the new body's length leaves original bytes surviving at the tail of the response.

---

## Status Lookup Methods

Implement as **private class methods** — no closures, no default args on nested functions.

```typescript
private getErrorTitle(code: u32): string {
  if (code == 400) return "Bad Request";
  if (code == 401) return "Unauthorized";
  if (code == 403) return "Forbidden";
  if (code == 404) return "Not Found";
  if (code == 405) return "Method Not Allowed";
  if (code == 408) return "Request Timeout";
  if (code == 429) return "Too Many Requests";
  if (code == 500) return "Internal Server Error";
  if (code == 502) return "Bad Gateway";
  if (code == 503) return "Service Unavailable";
  if (code == 504) return "Gateway Timeout";
  if (code >= 500) return "Server Error";
  return "Error";
}

private getErrorDescription(code: u32): string {
  if (code == 400)
    return "The server could not understand the request due to invalid syntax.";
  if (code == 401)
    return "You need to authenticate to access this resource.";
  if (code == 403)
    return "You do not have permission to access this resource.";
  if (code == 404)
    return "The requested page could not be found. It may have been moved or deleted.";
  if (code == 405)
    return "The request method is not supported for this resource.";
  if (code == 408)
    return "The server timed out waiting for the request.";
  if (code == 429)
    return "You have sent too many requests. Please try again later.";
  if (code == 500)
    return "The server encountered an unexpected condition that prevented it from fulfilling the request.";
  if (code == 502)
    return "The server received an invalid response from the upstream server.";
  if (code == 503)
    return "The server is temporarily unavailable. Please try again later.";
  if (code == 504)
    return "The server did not receive a timely response from the upstream server.";
  if (code >= 500)
    return "The server encountered an error processing your request.";
  return "An error occurred processing your request.";
}
```

**Covered codes**: 400, 401, 403, 404, 405, 408, 429, 500, 502, 503, 504. All other codes fall back to generic messages.

---

## Class Structure

```typescript
class ErrorPagesRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new ErrorPagesContext(context_id, this);
  }
}

class ErrorPagesContext extends Context {
  constructor(context_id: u32, root_context: ErrorPagesRoot) {
    super(context_id, root_context);
  }

  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues { ... }
  onResponseBody(body_buffer_length: usize, end_of_stream: bool): FilterDataStatusValues { ... }

  private getErrorTitle(code: u32): string { ... }
  private getErrorDescription(code: u32): string { ... }
}

registerRootContext((context_id: u32) => {
  return new ErrorPagesRoot(context_id);
}, "customErrorPages");
```

---

## Imports

```typescript
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
import {
  Context,
  FilterDataStatusValues,
  FilterHeadersStatusValues,
  get_property,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
  set_buffer_bytes,
  BufferTypeValues,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import { setLogLevel } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
```

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

No dependencies beyond the base skeleton.

---

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output file | Description |
|---|---|
| `build/customErrorPages.wasm` | Optimised release binary — upload to FastEdge |
| `build/customErrorPages-debug.wasm` | Debug binary with source maps |

Build scripts defined in `package.json`:

| Script | Command |
|---|---|
| `asbuild:debug` | `asc assembly/index.ts --target debug` |
| `asbuild:release` | `asc assembly/index.ts --target release` |
| `asbuild` | runs both debug and release |

---

## Deploy

Upload `build/customErrorPages.wasm` to the FastEdge portal and attach it to your CDN application. No environment variables or secrets required.

---

## Key Constraints

- **No instance state between hooks**: `onResponseHeaders` and `onResponseBody` are separate invocations. Do not store the decoded status code on the instance — re-read `get_property("response.status")` in each hook.
- **Buffer entire body before replacing**: Return `FilterDataStatusValues.StopIterationAndBuffer` until `end_of_stream` is true, then replace.
- **Replace length must be `body_buffer_length`**: Using the new body's byte length as the replacement length will leave original response bytes at the tail.
- **Status buffer is big-endian 2 bytes**: Always check `byteLength >= 2` before decoding.
- **Status lookup methods must be private class methods**: No closures, no default args on nested functions.

---

## See Also

- proxy-wasm-sdk-as SDK reference (AssemblyScript)
- CDN base skeleton reference
- host-services-rust reference (for Rust equivalent patterns)
- FastEdge platform overview
