<!--
  auto-updated: true
  sources:
    - id: proxy-wasm-sdk-as
      ref: master
      commit: 60f25c7bd35564e5bafb421be7f37aa4acf1bf81
      updated: 2026-05-20
-->

---
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [auth, jwt]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/jwt
---

# Feature Blueprint: JWT Authentication (AssemblyScript, CDN)

## When to Use

Use this blueprint when the user wants to validate JWT Bearer tokens on every incoming request and enforce authentication at the CDN layer before traffic reaches the origin.

## New Dependencies

This feature requires one dependency beyond the base CDN skeleton:

| Package | Version | Purpose |
|---|---|---|
| `@gcoredev/as-jwt` | `^1.0.3` | JWT signature verification and expiry validation |

Add to `package.json` `dependencies`:
```json
"@gcoredev/as-jwt": "^1.0.3"
```

## Required Secrets

| Secret name | Description |
|---|---|
| `SECRET` | HMAC-SHA256 signing secret — minimum 256 bits (32 characters) |

Configure this secret variable on the FastEdge application before deployment.

## Imports

```typescript
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
import {
  Context,
  FilterHeadersStatusValues,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
  send_http_response,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import {
  getSecret,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
import { jwtVerify, JwtValidation } from "@gcoredev/as-jwt/assembly";
```

## Constants

```typescript
const UNAUTHORIZED: u32 = 401;
const FORBIDDEN: u32 = 403;
const INTERNAL_SERVER_ERROR: u32 = 500;
```

## Class Structure

### RootContext subclass

```typescript
class AuthRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new Auth(context_id, this);
  }
}
```

- Calls `setLogLevel(LogLevelValues.info)` on each context creation. Default level; present for demonstration purposes.
- Returns a new `Auth` context per request.

### Context subclass

```typescript
class Auth extends Context {
  constructor(context_id: u32, root_context: AuthRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues { ... }
}
```

## JWT Validation Flow (`onRequestHeaders`)

All logic executes in `onRequestHeaders`. The method returns `FilterHeadersStatusValues.StopIteration` on any failure (blocking the request) and `FilterHeadersStatusValues.Continue` on success (passing the request to origin).

### Step 1 — Read signing secret

```typescript
const secret = getSecret("SECRET");
if (!secret) {
  send_http_response(
    INTERNAL_SERVER_ERROR,
    "internal server error",
    String.UTF8.encode("App misconfigured"),
    [],
  );
  return FilterHeadersStatusValues.StopIteration;
}
```

- `getSecret(name: string): string | null` — reads a FastEdge secret variable by name.
- Secret variable name is `"SECRET"` (uppercase).
- Returns `500 Internal Server Error` with body `"App misconfigured"` if secret is absent.

### Step 2 — Extract Authorization header

```typescript
const authHeader = stream_context.headers.request.get("Authorization");
if (!authHeader) {
  send_http_response(
    UNAUTHORIZED,
    "unauthorized",
    String.UTF8.encode("No Authorization header"),
    [],
  );
  return FilterHeadersStatusValues.StopIteration;
}
```

- Returns `401 Unauthorized` with body `"No Authorization header"` if the header is absent.

### Step 3 — Enforce Bearer scheme

```typescript
if (!authHeader.startsWith("Bearer ")) {
  send_http_response(
    UNAUTHORIZED,
    "unauthorized",
    String.UTF8.encode("Authorization header must use Bearer scheme"),
    [],
  );
  return FilterHeadersStatusValues.StopIteration;
}
```

- Validates that the Authorization header begins with `"Bearer "`.
- Returns `401 Unauthorized` with body `"Authorization header must use Bearer scheme"` if the scheme does not match.

### Step 4 — Strip Bearer prefix

```typescript
const token = authHeader.slice(7); // strip "Bearer " prefix
if (!token) {
  send_http_response(
    UNAUTHORIZED,
    "unauthorized",
    String.UTF8.encode("Token not found"),
    [],
  );
  return FilterHeadersStatusValues.StopIteration;
}
```

- Strips the `"Bearer "` prefix using `.slice(7)`.
- Returns `401 Unauthorized` with body `"Token not found"` if the result is null/empty.

### Step 5 — Verify JWT

```typescript
const jwtResult = jwtVerify(token, secret);
if (jwtResult !== JwtValidation.Ok) {
  if (jwtResult === JwtValidation.Expired) {
    log(LogLevelValues.info, "Token Expired");
    send_http_response(FORBIDDEN, "forbidden", String.UTF8.encode("Expired token"), []);
  } else {
    log(LogLevelValues.info, "Bad Token");
    send_http_response(FORBIDDEN, "forbidden", String.UTF8.encode("Invalid token"), []);
  }
  return FilterHeadersStatusValues.StopIteration;
}
return FilterHeadersStatusValues.Continue;
```

- `jwtVerify(token: string, secret: string): JwtValidation` — verifies signature and expiry.
- `JwtValidation.Ok` — token is valid; request continues.
- `JwtValidation.Expired` — returns `403 Forbidden` with body `"Expired token"`.
- Any other non-Ok result — returns `403 Forbidden` with body `"Invalid token"`.
- Both failure branches log at `LogLevelValues.info` before responding.

## `send_http_response` Signature

```typescript
send_http_response(
  status_code: u32,
  status_text: string,
  body: ArrayBuffer,
  headers: string[][],
): void
```

- `body` must be encoded: `String.UTF8.encode("text")`.
- `headers` is an array of `[name, value]` pairs; pass `[]` for no additional headers.

## Registration

```typescript
registerRootContext((context_id: u32) => {
  return new AuthRoot(context_id);
}, "auth");
```

- Root context name: `"auth"`.

## Response Summary

| Condition | Status | Body |
|---|---|---|
| Secret not configured | 500 | `App misconfigured` |
| Authorization header missing | 401 | `No Authorization header` |
| Authorization header not using Bearer scheme | 401 | `Authorization header must use Bearer scheme` |
| Token not found after stripping prefix | 401 | `Token not found` |
| Token expired | 403 | `Expired token` |
| Token invalid (any other error) | 403 | `Invalid token` |
| Token valid | — | Pass-through (`Continue`) |

## Build Output

| File | Description |
|---|---|
| `build/jwt.wasm` | Optimised release binary — upload to FastEdge |
| `build/jwt-debug.wasm` | Debug binary with source maps |

Build commands:
```sh
pnpm install
pnpm run asbuild
```

## See Also

- FastEdge secrets documentation (secret variables and rotation slots)
- `@gcoredev/as-jwt` npm package
- proxy-wasm-sdk-as host services reference (getSecret, send_http_response, stream_context)
- cdn-base skeleton blueprint
