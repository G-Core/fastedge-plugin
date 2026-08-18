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
capabilities: [request-properties, property-rewrite]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/properties
---

# Request Properties — AssemblyScript (CDN Feature Blueprint)

Read and rewrite request runtime properties (URL, host, path, scheme, query, geo-IP metadata) at the CDN layer using the proxy-wasm ABI.

---

## When to Use

- User wants to read per-request metadata (URL, path, host, scheme, query string, file extension) at the CDN layer
- User wants to read geo-IP data (country code, city, client IP) at the CDN layer
- User wants to rewrite the request URL, host, or path before upstream processing
- User wants to forward raw property values as response headers for debugging or downstream inspection

---

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
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import { setLogLevel } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
```

---

## Available Request Property Paths

All property keys are plain strings passed to `get_property` / `set_property`.

| Constant | Property Path | Response Header | Required |
|---|---|---|---|
| `REQUEST_URI` | `"request.url"` | `request-uri` | Yes |
| `REQUEST_HOST` | `"request.host"` | *(validated only — not exposed)* | Yes |
| `REQUEST_PATH` | `"request.path"` | `request-path` | Yes |
| `REQUEST_SCHEME` | `"request.scheme"` | `request-scheme` | Yes |
| `REQUEST_EXTENSION` | `"request.extension"` | `request-extension` | No (optional) |
| `REQUEST_QUERY` | `"request.query"` | `request-query` | No (optional) |
| `REQUEST_X_REAL_IP` | `"request.x_real_ip"` | `request-x-real-ip` | Yes |
| `REQUEST_COUNTRY` | `"request.country"` | `request-country` | Yes |
| `REQUEST_CITY` | `"request.city"` | `request-city` | Yes |

`request.host` is validated for presence but not logged and not exposed as a response header — it must be non-empty for upstream routing.

`request.extension` and `request.query` are optional: if absent (`byteLength === 0`), the property is logged with an empty value and processing continues without adding an empty response header.

---

## Reading a Property

`get_property(key: string)` returns an `ArrayBuffer`. An absent property returns an `ArrayBuffer` with `byteLength === 0`.

```typescript
const valueArr = get_property("request.country");
if (valueArr.byteLength === 0) {
  // property absent — handle error or skip
}
const value = String.UTF8.decode(valueArr);
```

**Signature:** `get_property(key: string): ArrayBuffer`

- Returns `ArrayBuffer` — always check `byteLength === 0` before decoding
- Decode to string with `String.UTF8.decode(valueArr)`
- Call within `onRequestHeaders`

---

## Forwarding a Property as a Response Header

Use `stream_context.headers.response.add` to attach a property value as a response header.

```typescript
const value = String.UTF8.decode(get_property("request.url"));
stream_context.headers.response.add("request-uri", value);
```

**Signature:** `stream_context.headers.response.add(name: string, value: string): void`

---

## Rewriting a Property

Use `set_property` to overwrite a request property before upstream processing.

```typescript
set_property("request.url", String.UTF8.encode(newUrl));
set_property("request.host", String.UTF8.encode(newHost));
set_property("request.path", String.UTF8.encode(newPath));
```

**Signature:** `set_property(key: string, value: ArrayBuffer): void`

- Encode string values with `String.UTF8.encode(value)` before passing
- Writable properties: `request.url`, `request.host`, `request.path`
- Geo and metadata properties (`request.country`, `request.city`, `request.x_real_ip`, etc.) are read-only

---

## Rewriting from Query Parameters

Parse the raw query string and rewrite properties based on matching parameter keys.

```typescript
const query = get_property(REQUEST_QUERY);
if (query.byteLength !== 0) {
  const queryString = String.UTF8.decode(query);
  const params = queryString
    .split("&")
    .map<Array<string>>((pair) => pair.split("="));

  for (let i = 0; i < params.length; i++) {
    const param = params[i];
    if (param.length !== 2) {
      continue; // skip invalid pairs
    }
    const key = param[0];
    const value = param[1];
    if (key.toLowerCase() === "url") {
      set_property(REQUEST_URI, String.UTF8.encode(value));
    } else if (key.toLowerCase() === "host") {
      set_property(REQUEST_HOST, String.UTF8.encode(value));
    } else if (key.toLowerCase() === "path") {
      set_property(REQUEST_PATH, String.UTF8.encode(value));
    }
  }
}
```

---

## Optional vs Required Properties

Properties that may legitimately be absent must be handled with `allowEmpty = true` logic — log the empty value and continue without adding a response header or returning an error.

| Property | Behavior when absent |
|---|---|
| `request.extension` | Log empty value, continue (no error) |
| `request.query` | Log empty value, continue (no error) |
| All others | Send error response, stop iteration |

---

## Private Handler Method Pattern

Encapsulate the read-log-add-header logic in a private class method to avoid closures over mutable state and to keep `onRequestHeaders` readable.

```typescript
private handleProperty(
  propertyKey: string,
  errorCode: u32,
  propertyName: string = "",
  headerName: string = "",
  allowEmpty: boolean = false
): boolean {
  const valueArr = get_property(propertyKey);
  if (valueArr.byteLength === 0) {
    if (allowEmpty) {
      if (propertyName.length > 0) {
        log(LogLevelValues.info, "onRequestHeaders >> " + propertyName + ": ");
      }
      return true;
    }
    send_http_response(
      errorCode,
      "internal server error",
      String.UTF8.encode("Internal server error"),
      []
    );
    return false;
  }
  const value = String.UTF8.decode(valueArr);
  if (propertyName.length > 0) {
    log(LogLevelValues.info, "onRequestHeaders >> " + propertyName + ": " + value);
  }
  if (headerName.length > 0) {
    stream_context.headers.response.add(headerName, value);
  }
  return true;
}
```

Parameters:
- `propertyKey` — runtime property path string
- `errorCode` — HTTP status code to send if property is absent and not optional
- `propertyName` — log label; pass `""` to suppress logging
- `headerName` — response header name; pass `""` to suppress header
- `allowEmpty` — if `true`, absent value logs empty and returns `true`; no error response sent

Return value: `true` if processing should continue; `false` if an error response was sent and iteration must stop.

---

## Class Structure

```typescript
class PropertiesRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new Properties(context_id, this);
  }
}

class Properties extends Context {
  constructor(context_id: u32, root_context: PropertiesRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    if (!this.handleProperty("request.url", 551, "uri", "request-uri")) {
      return FilterHeadersStatusValues.StopIteration;
    }
    if (!this.handleProperty("request.host", 552)) {
      return FilterHeadersStatusValues.StopIteration;
    }
    // ... additional properties ...
    return FilterHeadersStatusValues.Continue;
  }

  private handleProperty(
    propertyKey: string,
    errorCode: u32,
    propertyName: string = "",
    headerName: string = "",
    allowEmpty: boolean = false
  ): boolean { /* see above */ }
}

registerRootContext((context_id: u32) => {
  return new PropertiesRoot(context_id);
}, "properties");
```

---

## Complete Example

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
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import { setLogLevel } from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

const REQUEST_URI = "request.url";
const REQUEST_HOST = "request.host";
const REQUEST_PATH = "request.path";
const REQUEST_SCHEME = "request.scheme";
const REQUEST_EXTENSION = "request.extension";
const REQUEST_QUERY = "request.query";
const REQUEST_X_REAL_IP = "request.x_real_ip";
const REQUEST_COUNTRY = "request.country";
const REQUEST_CITY = "request.city";

class PropertiesRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new Properties(context_id, this);
  }
}

class Properties extends Context {
  constructor(context_id: u32, root_context: PropertiesRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    if (!this.handleProperty(REQUEST_URI, 551, "uri", "request-uri")) {
      return FilterHeadersStatusValues.StopIteration;
    }
    if (!this.handleProperty(REQUEST_HOST, 552)) {
      return FilterHeadersStatusValues.StopIteration;
    }
    if (!this.handleProperty(REQUEST_PATH, 553, "path", "request-path")) {
      return FilterHeadersStatusValues.StopIteration;
    }
    if (!this.handleProperty(REQUEST_SCHEME, 554, "scheme", "request-scheme")) {
      return FilterHeadersStatusValues.StopIteration;
    }
    if (!this.handleProperty(REQUEST_EXTENSION, 555, "extension", "request-extension", true)) {
      return FilterHeadersStatusValues.StopIteration;
    }
    if (!this.handleProperty(REQUEST_QUERY, 556, "query", "request-query", true)) {
      return FilterHeadersStatusValues.StopIteration;
    }
    if (!this.handleProperty(REQUEST_X_REAL_IP, 557, "client_ip", "request-x-real-ip")) {
      return FilterHeadersStatusValues.StopIteration;
    }
    if (!this.handleProperty(REQUEST_COUNTRY, 558, "country", "request-country")) {
      return FilterHeadersStatusValues.StopIteration;
    }
    if (!this.handleProperty(REQUEST_CITY, 559, "city", "request-city")) {
      return FilterHeadersStatusValues.StopIteration;
    }

    const query = get_property(REQUEST_QUERY);
    if (query.byteLength !== 0) {
      const queryString = String.UTF8.decode(query);
      log(LogLevelValues.info, "query=" + queryString);
      const params = queryString
        .split("&")
        .map<Array<string>>((pair) => pair.split("="));

      for (let i = 0; i < params.length; i++) {
        const param = params[i];
        if (param.length !== 2) {
          continue;
        }
        const key = param[0];
        const value = param[1];
        if (key.toLowerCase() === "url") {
          log(LogLevelValues.info, `change url to: ${value}`);
          set_property(REQUEST_URI, String.UTF8.encode(value));
        } else if (key.toLowerCase() === "host") {
          log(LogLevelValues.info, `change host to: ${value}`);
          set_property(REQUEST_HOST, String.UTF8.encode(value));
        } else if (key.toLowerCase() === "path") {
          log(LogLevelValues.info, `change path to: ${value}`);
          set_property(REQUEST_PATH, String.UTF8.encode(value));
        }
      }
    }

    return FilterHeadersStatusValues.Continue;
  }

  private handleProperty(
    propertyKey: string,
    errorCode: u32,
    propertyName: string = "",
    headerName: string = "",
    allowEmpty: boolean = false
  ): boolean {
    const valueArr = get_property(propertyKey);
    if (valueArr.byteLength === 0) {
      if (allowEmpty) {
        if (propertyName.length > 0) {
          log(LogLevelValues.info, "onRequestHeaders >> " + propertyName + ": ");
        }
        return true;
      }
      send_http_response(
        errorCode,
        "internal server error",
        String.UTF8.encode("Internal server error"),
        []
      );
      return false;
    }
    const value = String.UTF8.decode(valueArr);
    if (propertyName.length > 0) {
      log(LogLevelValues.info, "onRequestHeaders >> " + propertyName + ": " + value);
    }
    if (headerName.length > 0) {
      stream_context.headers.response.add(headerName, value);
    }
    return true;
  }
}

registerRootContext((context_id: u32) => {
  return new PropertiesRoot(context_id);
}, "properties");
```

---

## Error Handling

| Status Code | Property | Notes |
|---|---|---|
| 551 | `request.url` | Required — absent triggers error |
| 552 | `request.host` | Required — validated but not logged or exposed as header |
| 553 | `request.path` | Required |
| 554 | `request.scheme` | Required |
| 555 | `request.extension` | Optional — `allowEmpty=true`; error never triggered in practice |
| 556 | `request.query` | Optional — `allowEmpty=true`; error never triggered in practice |
| 557 | `request.x_real_ip` | Required |
| 558 | `request.country` | Required |
| 559 | `request.city` | Required |

When an absent required property is detected:
1. `send_http_response(errorCode, "internal server error", String.UTF8.encode("Internal server error"), [])` is called
2. `handleProperty` returns `false`
3. `onRequestHeaders` returns `FilterHeadersStatusValues.StopIteration`

---

## `send_http_response` Signature

```typescript
send_http_response(
  status_code: u32,
  status_message: string,
  body: ArrayBuffer,
  headers: Array<[string, string]>
): void
```

---

## Logging

```typescript
setLogLevel(LogLevelValues.info); // set in createContext

log(LogLevelValues.info, "onRequestHeaders >> uri: " + value);
log(LogLevelValues.info, "query=" + queryString);
log(LogLevelValues.info, `change url to: ${value}`);
```

Logs are visible in the FastEdge application logs panel.

---

## Expected Log Output

For a request to `/page.html?test=value` with geo properties populated:

```
onRequestHeaders >> uri: https://example.com/page.html?test=value
onRequestHeaders >> path: /page.html?test=value
onRequestHeaders >> scheme: https
onRequestHeaders >> extension: html
onRequestHeaders >> query: test=value
onRequestHeaders >> client_ip: 203.0.113.1
onRequestHeaders >> country: LU
onRequestHeaders >> city: Luxembourg
query=test=value
```

---

## Constraints

- All property reads and writes must occur within `onRequestHeaders`
- `get_property` returns `ArrayBuffer` — always check `byteLength === 0` before calling `String.UTF8.decode`
- `set_property` requires value encoded as `ArrayBuffer` via `String.UTF8.encode(value)`
- Writable properties: `request.url`, `request.host`, `request.path` only
- Geo and metadata properties (`request.country`, `request.city`, `request.x_real_ip`) are read-only
- `request.host` must be validated (non-empty) for upstream routing; it is not surfaced as a log entry or response header
- `request.extension` is absent when the request path has no file extension; treat as optional
- `request.query` is absent when there is no query string; treat as optional
- Do not add a response header when the property value is empty (optional properties)

---

## Package Dependencies

| Package | Role |
|---|---|
| `@gcoredev/proxy-wasm-sdk-as` | Core proxy-wasm SDK for AssemblyScript |
| `@assemblyscript/wasi-shim` | WASI compatibility shim (dev) |
| `assemblyscript` | AssemblyScript compiler (dev) |

Package name for this example: `fastedge-as-example-properties`

---

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output File | Description |
|---|---|
| `build/properties.wasm` | Optimised release binary — upload to FastEdge |
| `build/properties-debug.wasm` | Debug binary with source maps |

Build scripts defined in `package.json`:
- `asbuild:debug` — `asc assembly/index.ts --target debug`
- `asbuild:release` — `asc assembly/index.ts --target release`
- `asbuild` — runs both debug and release

---

## Deployment

Upload `build/properties.wasm` to the FastEdge portal and attach it to your CDN application. No environment variables are required.

---

## See Also

- proxy-wasm-sdk-as SDK reference (AssemblyScript)
- cdn-base skeleton blueprint
- platform-overview (CDN app request lifecycle, available runtime properties)
- host-services reference (get_property, set_property, send_http_response, log)
- CDN Properties list (full list of available runtime property paths)
