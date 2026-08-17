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

## Testing Tokens

Both tokens use the secret `a-string-secret-at-least-256-bits-long-thats-hard-to-break`.

**Expired token** (returns `403 Forbidden`):
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjk3ODMxMDg2MX0.egSSDoDdAHz8Kqee7be9N168CDEwOiOej96Idm2c1yQ
```

**Valid token** (expiry: 2035-01-01, returns `200 OK`):
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjIwNTEyMjYwNjF9.zn_pSdcBo8T3SvNgMVYzWc5CU_MKqOlms7TpZXhPtJU
```

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

## Source Material

### FILE: examples/jwt/assembly/index.ts

```ts
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy"; // this exports the required functions for the proxy to interact with us.
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

const UNAUTHORIZED: u32 = 401;
const FORBIDDEN: u32 = 403;
const INTERNAL_SERVER_ERROR: u32 = 500;

class AuthRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info); // Set log level to info is the default setting. This is purely here for demonstration purposes
    return new Auth(context_id, this);
  }
}

class Auth extends Context {
  constructor(context_id: u32, root_context: AuthRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
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

    if (!authHeader.startsWith("Bearer ")) {
      send_http_response(
        UNAUTHORIZED,
        "unauthorized",
        String.UTF8.encode("Authorization header must use Bearer scheme"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

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

    // Decode the JWT token
    const jwtResult = jwtVerify(token, secret);
    if (jwtResult !== JwtValidation.Ok) {
      if (jwtResult === JwtValidation.Expired) {
        log(LogLevelValues.info, "Token Expired");
        send_http_response(
          FORBIDDEN,
          "forbidden",
          String.UTF8.encode("Expired token"),
          [],
        );
      } else {
        log(LogLevelValues.info, "Bad Token");
        send_http_response(
          FORBIDDEN,
          "forbidden",
          String.UTF8.encode("Invalid token"),
          [],
        );
      }
      return FilterHeadersStatusValues.StopIteration;
    }
    return FilterHeadersStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => {
  return new AuthRoot(context_id);
}, "auth");
```

### FILE: examples/jwt/package.json

```json
{
  "name": "fastedge-as-example-jwt",
  "version": "1.0.0",
  "description": "FastEdge AssemblyScript example: JWT validation",
  "scripts": {
    "asbuild:debug": "asc assembly/index.ts --target debug",
    "asbuild:release": "asc assembly/index.ts --target release",
    "asbuild": "npm run asbuild:debug && npm run asbuild:release"
  },
  "dependencies": {
    "@gcoredev/as-jwt": "^1.0.3",
    "@gcoredev/proxy-wasm-sdk-as": "^1.2.3",
    "assemblyscript-json": "^1.1.0"
  },
  "devDependencies": {
    "@assemblyscript/wasi-shim": "^0.1.0",
    "assemblyscript": "^0.28.9"
  }
}
```

### FILE: examples/jwt/README.md

```
[← Back to examples](../README.md)

# JWT Validation

This application validates a JWT Bearer token on every incoming request using the [`@gcoredev/as-jwt`](https://www.npmjs.com/package/@gcoredev/as-jwt) library.

## What it does

In `onRequestHeaders`, the app:

1. Reads the HMAC secret from a FastEdge secret variable named `SECRET`.
2. Checks that the `Authorization` header uses the `Bearer` scheme; rejects other schemes with `401`.
3. Verifies the token signature and expiry using `jwtVerify()`.
4. Allows the request through on a valid token, or returns `401`/`403` on missing, invalid scheme, expired, or invalid tokens.

## Configuration

Set the following secret variable on your FastEdge application:

| Secret   | Description                                                        |
| -------- | ------------------------------------------------------------------ |
| `SECRET` | The HMAC-SHA256 signing secret (at least 256 bits / 32 characters) |

## Testing tokens

**Expired token** (will return `403 Forbidden`):

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjk3ODMxMDg2MX0.egSSDoDdAHz8Kqee7be9N168CDEwOiOej96Idm2c1yQ
```

**Valid token** (expiry: 2035-01-01, will return `200 OK`):

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjIwNTEyMjYwNjF9.zn_pSdcBo8T3SvNgMVYzWc5CU_MKqOlms7TpZXhPtJU
```

Both tokens use the secret `a-string-secret-at-least-256-bits-long-thats-hard-to-break`.

## Build

```sh
pnpm install
pnpm run asbuild
```

Build output:

| File                   | Description                                        |
| ---------------------- | -------------------------------------------------- |
| `build/jwt.wasm`       | Optimised release binary — upload this to FastEdge |
| `build/jwt-debug.wasm` | Debug binary with source maps                      |

## Deploy

Upload `build/jwt.wasm` to the FastEdge portal and attach it to your CDN application. Configure the `SECRET` secret variable in the application settings.

For more on secrets and secret rotation slots, see the FastEdge secrets documentation.
```
