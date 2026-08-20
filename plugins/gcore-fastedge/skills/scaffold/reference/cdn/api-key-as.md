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
capabilities: [auth, api-key]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/apiKey
---

# API Key Validation (AssemblyScript, CDN)

Validates incoming requests by checking the `X-API-Key` request header against a stored secret. All validation runs in `onRequestHeaders`. Blocks the request before it reaches the upstream origin if validation fails.

**When to use:** You need to gate CDN-layer access with a static shared key and do not require token expiry, claims, or cryptographic signing (see the `jwt` feature for those requirements).

---

## Imports

```typescript
// Core proxy-wasm types and functions
import {
  Context,
  FilterHeadersStatusValues,
  HeaderPair,
  log,
  LogLevelValues,
  makeHeaderPair,
  registerRootContext,
  RootContext,
  send_http_response,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";

// FastEdge platform extensions
import {
  getSecret,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
```

---

## Configuration

| Name | Type | Description |
|------|------|-------------|
| `API_KEY` | Secret | Expected API key value; configured on the FastEdge application |

---

## Implementation

### Root context

```typescript
class ApiKeyRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new ApiKeyContext(context_id, this);
  }
}
```

`setLogLevel` is called once per root context creation. Log level is set to `info`.

### Request context

```typescript
class ApiKeyContext extends Context {
  constructor(context_id: u32, root_context: ApiKeyRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    // 1. Retrieve expected key from secret store
    const expectedKey = getSecret("API_KEY");
    if (expectedKey === "") {
      log(LogLevelValues.error, "API_KEY secret not configured");
      send_http_response(
        INTERNAL_SERVER_ERROR,
        "internal server error",
        String.UTF8.encode("App misconfigured"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    // 2. Read key from request header
    const providedKey = stream_context.headers.request.get("X-API-Key");

    if (providedKey === "") {
      const authHeaders = new Array<HeaderPair>();
      authHeaders.push(makeHeaderPair("WWW-Authenticate", "API-Key"));
      send_http_response(
        UNAUTHORIZED,
        "unauthorized",
        String.UTF8.encode("Missing X-API-Key header"),
        authHeaders,
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    if (providedKey !== expectedKey) {
      log(LogLevelValues.info, "API key validation failed");
      send_http_response(
        FORBIDDEN,
        "forbidden",
        String.UTF8.encode("Invalid API key"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    // 3. Strip key before forwarding to upstream
    // .remove() sets the header value to "" rather than deleting it entirely —
    // the upstream will see X-API-Key: "" rather than a missing header.
    stream_context.headers.request.remove("X-API-Key");

    log(LogLevelValues.info, "API key validated successfully");
    return FilterHeadersStatusValues.Continue;
  }
}
```

### Registration

```typescript
registerRootContext((context_id: u32) => {
  return new ApiKeyRoot(context_id);
}, "apiKey");
```

---

## Validation Logic

Three-branch validation, all in `onRequestHeaders`:

| Condition | Response | Headers | Body | Return |
|-----------|----------|---------|------|--------|
| `getSecret("API_KEY")` returns `""` | `500 Internal Server Error` | none | `App misconfigured` | `StopIteration` |
| `X-API-Key` header absent or empty | `401 Unauthorized` | `WWW-Authenticate: API-Key` | `Missing X-API-Key header` | `StopIteration` |
| Header present but does not match secret | `403 Forbidden` | none | `Invalid API key` | `StopIteration` |
| Header matches secret | — | `X-API-Key` stripped | — | `Continue` |

---

## Key API Details

### `getSecret(name: string): string`
- **Source:** `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`
- Returns the secret value as a string.
- Returns `""` (empty string) when the secret is not configured — never returns `null`.

### `stream_context.headers.request.get(name: string): string`
- Returns the header value as a string.
- Returns `""` when the header is absent.

### `stream_context.headers.request.remove(name: string): void`
- **Platform behavior:** Sets the header value to `""` rather than deleting the header entry. The upstream origin receives `X-API-Key:` (empty value), not a missing header.

### `send_http_response(status: u32, statusText: string, body: ArrayBuffer, headers: Array<HeaderPair>): void`
- Sends an immediate response to the client, bypassing the upstream.
- Body must be encoded: `String.UTF8.encode(body)`.
- Pass `[]` for `headers` when no custom response headers are needed.

### `makeHeaderPair(name: string, value: string): HeaderPair`
- **Source:** `@gcoredev/proxy-wasm-sdk-as/assembly`
- Constructs a `HeaderPair` for use in the `headers` array of `send_http_response`.

### Status code constants

```typescript
const UNAUTHORIZED: u32 = 401;
const FORBIDDEN: u32 = 403;
const INTERNAL_SERVER_ERROR: u32 = 500;
```

---

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output file | Description |
|-------------|-------------|
| `build/apiKey.wasm` | Optimised release binary — upload to FastEdge |
| `build/apiKey-debug.wasm` | Debug binary with source maps |

Build scripts (`package.json`):

| Script | Command |
|--------|---------|
| `asbuild:debug` | `asc assembly/index.ts --target debug` |
| `asbuild:release` | `asc assembly/index.ts --target release` |
| `asbuild` | Runs both debug and release |

**Package:** `@gcoredev/proxy-wasm-sdk-as` `^1.2.3`

---

## Security Notes

- The key comparison (`providedKey !== expectedKey`) is **not constant-time**. This creates a timing side-channel exploitable by a high-volume attacker. For production deployments requiring timing-safe comparison, replace with a constant-time HMAC equality check or use the `jwt` feature.
- `remove()` does not delete the `X-API-Key` header — it sets the value to an empty string. Upstream services must treat an empty `X-API-Key` header as absent.

---

## See Also

- jwt feature (CDN AssemblyScript) — token-based auth with expiry and claims
- cdn-base skeleton — base wiring for CDN AssemblyScript apps
- proxy-wasm-sdk-as reference — full SDK API surface
