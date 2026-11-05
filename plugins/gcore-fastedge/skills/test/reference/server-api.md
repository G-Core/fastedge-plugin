<!--
  auto-updated: true
  sources:
    - id: fastedge-test
      ref: v0.2.8
      commit: 81ae6516cac618afe50414ca97c579c11df28e7e
      updated: 2026-11-05
-->

# Server API — REST and WebSocket Endpoints

The `@gcoredev/fastedge-test` debugger server exposes REST and WebSocket interfaces for loading WASM modules, executing requests, and streaming real-time events.

**Base URL:** `http://localhost:5179`

The port can be overridden via the `PORT` environment variable. When `WORKSPACE_PATH` is set, the active port is written to `$WORKSPACE_PATH/.fastedge-debug/.debug-port` on startup and deleted on shutdown. The file contains `PORT:SHA256_HASH`, where `PORT` is the decimal port number and `SHA256_HASH` is the hex-encoded SHA-256 of the session token. Consumers that only need the port should parse the prefix up to the first colon (e.g. `parseInt(content.split(":")[0], 10)`).

JSON request bodies are limited to 20 MB.

> **Note on header values.** Response-side and hook-result headers use `Record<string, string | string[]>` — single-valued headers are a `string`, multi-valued headers (notably `Set-Cookie` per RFC 6265) are a `string[]`. HTTP-WASM response headers additionally allow `undefined` values (`Record<string, string | string[] | undefined>`), though `undefined` entries are dropped during JSON serialization. Request-side header inputs are single-valued `Record<string, string>`.

---

## Authentication

The debugger server requires a session token on all `/api/*` requests. `/health` is the only unauthenticated endpoint.

When started from the CLI (`npx fastedge-debug`), the server generates a random 32-byte hex token and prints the full browser URL to stderr:

```
Open: http://localhost:5179/#token=<hex>
```

The fragment after `#token=` is your session token.

**HTTP requests** — send the token as a header on every `/api/*` call:

```
x-fastedge-token: <token>
```

A missing or incorrect token returns `401`.

**WebSocket** — two mechanisms exist, tried in preference order:

1. **`Sec-WebSocket-Protocol: fastedge-token.<token>`** (preferred) — the token is embedded in the subprotocol list rather than the URL, keeping it out of proxy and server access logs. The server echoes the subprotocol back on accept.
2. **`?token=<token>` query parameter** (fallback) — for legacy or non-browser tooling that cannot set subprotocols. Avoid this form in new consumers: the token appears in server and proxy logs.

```javascript
const ws = new WebSocket(
  `ws://127.0.0.1:5179/ws`,
  [`fastedge-token.${token}`],
);
```

All `/api/*` requests also validate the `Host` header. Requests whose `Host` is not a loopback name (or the host configured through `FASTEDGE_EXPECTED_HOST`) return `403` with `Invalid Host`.

**Environment variables related to authentication and binding:**

| Variable | Default | Description |
|---|---|---|
| `PORT` | `5179` | Preferred starting port; the next 49 ports are tried if it is in use. |
| `FASTEDGE_DEBUG_TOKEN` | unset | Inject a known token instead of generating one. When set, the `Open:` URL is not printed to stderr. |
| `FASTEDGE_BIND_HOST` | `127.0.0.1` | Interface the HTTP server binds to. |
| `FASTEDGE_EXPECTED_HOST` | unset | Extra hostname (suffix match) allowed in `Host` / `Origin` headers — for Codespaces forwarded URLs. |
| `WORKSPACE_PATH` | `process.cwd()` | Workspace root; affects `.env` resolution, port file, and config file placement. |

---

## REST Endpoints

### Common Headers

#### X-Source

Accepted by `POST /api/execute`, `POST /api/send`, and `POST /api/config`. Tags the origin of the operation in WebSocket broadcast events.

| Value | Description |
|---|---|
| `ui` | Web UI (default if omitted) |
| `ai_agent` | AI agent |
| `api` | Direct API usage |
| `system` | Automated system |

```http
X-Source: ai_agent
```

---

### Health

#### GET /health

Returns server status and service identity. Does not require authentication.

**Response**

```typescript
{
  status: "ok";
  service: "fastedge-debugger";
}
```

**Example**

```bash
curl http://localhost:5179/health
```

```json
{
  "status": "ok",
  "service": "fastedge-debugger"
}
```

---

#### GET /api/client-count

Returns the number of currently connected WebSocket clients. Useful in CI tooling to wait until the UI has connected before proceeding.

**Response**

```typescript
{
  count: number;
}
```

**Example**

```bash
curl -H "x-fastedge-token: <token>" http://localhost:5179/api/client-count
```

```json
{
  "count": 1
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `401` | Missing or invalid `x-fastedge-token` |
| `403` | `Host` header not allowed |

---

### WASM Loading

#### POST /api/load

Loads a WASM binary into the runner. Accepts a file path or base64-encoded binary. Automatically detects `http-wasm` or `proxy-wasm` type. Any previously loaded module is cleaned up first.

**Request Body** — exactly one of `wasmPath` or `wasmBase64` must be provided; providing neither or both returns `400`.

```typescript
{
  wasmPath?: string;    // Path to a .wasm file; must resolve inside the workspace root
                        // (WORKSPACE_PATH if set, otherwise the server's working directory)
  wasmBase64?: string;  // Base64-encoded WASM binary; mutually exclusive with wasmPath
  dotenv?: {
    enabled?: boolean;  // Whether to load .env files for this module (default: false)
    path?: string;      // Directory containing .env files. Relative paths resolve against the
                        // workspace root and must stay inside it. Defaults to the workspace root.
  };
  httpPort?: number;    // HTTP-WASM only. Pin the runner subprocess to this port (1024–65535).
                        // Load fails immediately if the port is already in use.
                        // Ignored for proxy-wasm modules.
}
```

**Response**

```typescript
{
  ok: true;
  wasmType: "http-wasm" | "proxy-wasm";
  resolvedPath?: string;  // Normalized absolute path; present only when wasmPath was provided
}
```

**Example — load from path**

```bash
curl -X POST http://localhost:5179/api/load \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -d '{
    "wasmPath": "/home/user/project/build/module.wasm",
    "dotenv": { "enabled": true }
  }'
```

```json
{
  "ok": true,
  "wasmType": "proxy-wasm",
  "resolvedPath": "/home/user/project/build/module.wasm"
}
```

**Example — load from base64**

```bash
curl -X POST http://localhost:5179/api/load \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -d '{
    "wasmBase64": "AGFzbQEAAAA...",
    "dotenv": { "enabled": false }
  }'
```

```json
{
  "ok": true,
  "wasmType": "http-wasm"
}
```

**Example — pin HTTP-WASM to a specific port**

```bash
curl -X POST http://localhost:5179/api/load \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -d '{
    "wasmPath": "/home/user/project/build/app.wasm",
    "httpPort": 8100
  }'
```

```json
{
  "ok": true,
  "wasmType": "http-wasm",
  "resolvedPath": "/home/user/project/build/app.wasm"
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `400` | Body failed validation (neither or both of `wasmPath` and `wasmBase64`, or `httpPort` out of range) |
| `400` | `wasmPath` is invalid, does not exist, is outside the workspace root, or does not end in `.wasm` |
| `400` | `dotenv.path` resolves outside the workspace root or contains a symlink that escapes it |
| `500` | WASM load or runner initialization failed, including `httpPort` already in use |

If a load fails with `500`, the previously loaded module is discarded and no module is loaded.

---

#### PATCH /api/dotenv

Applies updated dotenv settings to the currently loaded WASM module without reloading the binary. For Proxy-WASM: resets stores and reloads dotenv in-place. For HTTP-WASM: restarts the underlying process with updated flags.

Requires a WASM module already loaded via `POST /api/load`.

**Request Body**

```typescript
{
  dotenv: {
    enabled: boolean;   // Whether dotenv loading should be enabled
    path?: string;      // Directory containing .env files. Relative paths resolve against the
                        // workspace root and must stay inside it. Defaults to the workspace root.
  };
}
```

**Response**

```typescript
{
  ok: true;
}
```

**Example**

```bash
curl -X PATCH http://localhost:5179/api/dotenv \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -d '{
    "dotenv": { "enabled": true, "path": "/home/user/project" }
  }'
```

```json
{
  "ok": true
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `400` | Body failed validation (`dotenv.enabled` missing or not a boolean) |
| `400` | No WASM module is loaded |
| `400` | `dotenv.path` resolves outside the workspace root or contains an escaping symlink |
| `500` | Failed to apply dotenv settings |

---

### Test Execution

#### POST /api/execute

Executes a request through the loaded WASM module. Behavior differs by runner type. Does not use schema validation — fields are read directly from the request body.

Requires a WASM module loaded via `POST /api/load`. Accepts optional `X-Source` header.

**Request Body**

The server destructures `{ url, path, method, headers, body }` from the top level of the body. For Proxy-WASM it additionally reads `{ request, properties }`. Fields that do not apply to the loaded runner type are ignored.

```typescript
{
  // HTTP-WASM
  path?: string;                     // Request path and query string (preferred)
  method?: string;                   // HTTP method (default: "GET")
  headers?: Record<string, string>;  // Request headers (default: {})
  body?: string;                     // Request body (default: "")

  // Both runner types
  url?: string;                      // HTTP-WASM: absolute URL, path and query extracted
                                     //   (legacy fallback when path is absent).
                                     // Proxy-WASM: request URL, or "built-in" (required).

  // Proxy-WASM
  request?: {
    method?: string;                    // HTTP method (default: "GET")
    headers?: Record<string, string>;   // Request headers (default: {})
    body?: string;                      // Request body (default: "")
  };
  properties?: Record<string, unknown>; // CDN properties (default: {})
}
```

| Field | HTTP-WASM | Proxy-WASM |
|---|---|---|
| `path` | Used (preferred over `url`) | Ignored |
| `url` | Used if `path` is absent | Required |
| `method` | Used | Ignored (use `request.method`) |
| `headers` | Used | Ignored (use `request.headers`) |
| `body` | Used | Ignored (use `request.body`) |
| `request` | Ignored | Used |
| `properties` | Ignored | Used |

For HTTP-WASM, when `path` is given it is used directly as the request path (e.g. `/api/hello?q=1`). When only `url` is given, the path and query string are extracted from it.

For Proxy-WASM, the upstream response is generated at runtime — either by a real fetch against `url`, or by the built-in responder when `url === "built-in"`.

**Response — HTTP-WASM**

```typescript
{
  ok: true;
  result: {
    status: number;
    statusText: string;
    headers: Record<string, string | string[]>;  // Node's IncomingHttpHeaders shape
    body: string;
    contentType: string | null;
    isBase64?: boolean;
    logs: Array<{ level: number; message: string }>;
  };
}
```

**Response — Proxy-WASM**

```typescript
{
  ok: true;
  hookResults: Record<string, HookResult>;  // Keyed by hook name (e.g. "onRequestHeaders")
  finalResponse: {
    status: number;
    statusText: string;
    headers: Record<string, string | string[]>;
    body: string;
    contentType: string;
    isBase64?: boolean;
  };
  calculatedProperties?: Record<string, unknown>;
}
```

`calculatedProperties` keys: `request.url`, `request.host`, `request.path`, `request.query`, `request.scheme`, `request.extension`, `request.method`. `request.path` includes the query string; `request.query` is the query portion without the leading `?`.

**HookResult type** (used across multiple endpoints):

```typescript
type HookResult = {
  returnCode: number | null;
  logs: Array<{ level: number; message: string }>;
  input: {
    request: { headers: Record<string, string | string[]>; body: string };
    response: { headers: Record<string, string | string[]>; body: string };
    properties?: Record<string, unknown>;
  };
  output: {
    request: { headers: Record<string, string | string[]>; body: string };
    response: { headers: Record<string, string | string[]>; body: string };
    properties?: Record<string, unknown>;
  };
  properties: Record<string, unknown>;
};
```

**Example — HTTP-WASM**

```bash
curl -X POST http://localhost:5179/api/execute \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -H "X-Source: api" \
  -d '{
    "path": "/api/data?format=json",
    "method": "GET",
    "headers": { "accept": "application/json" }
  }'
```

```json
{
  "ok": true,
  "result": {
    "status": 200,
    "statusText": "OK",
    "headers": { "content-type": "application/json" },
    "body": "{\"hello\":\"world\"}",
    "contentType": "application/json",
    "isBase64": false,
    "logs": [
      { "level": 2, "message": "request received" }
    ]
  }
}
```

**Example — Proxy-WASM**

```bash
curl -X POST http://localhost:5179/api/execute \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -H "X-Source: api" \
  -d '{
    "url": "https://example.com/page",
    "request": {
      "method": "GET",
      "headers": { "host": "example.com" },
      "body": ""
    },
    "properties": {}
  }'
```

```json
{
  "ok": true,
  "hookResults": {
    "onRequestHeaders": {
      "returnCode": 0,
      "logs": [{ "level": 2, "message": "onRequestHeaders called" }],
      "input": {
        "request": { "headers": { "host": "example.com" }, "body": "" },
        "response": { "headers": {}, "body": "" },
        "properties": {}
      },
      "output": {
        "request": { "headers": { "host": "example.com", "x-added": "1" }, "body": "" },
        "response": { "headers": {}, "body": "" }
      },
      "properties": {}
    }
  },
  "finalResponse": {
    "status": 200,
    "statusText": "OK",
    "headers": { "content-type": "text/html" },
    "body": "<html/>",
    "contentType": "text/html"
  },
  "calculatedProperties": {
    "request.url": "https://example.com/page",
    "request.host": "example.com",
    "request.path": "/page",
    "request.query": "",
    "request.scheme": "https",
    "request.extension": "",
    "request.method": "GET"
  }
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `400` | No WASM module is loaded |
| `400` | HTTP-WASM: `path`/`url` missing, or `url` is not an absolute URL |
| `400` | Proxy-WASM: `url` missing or not a string |
| `500` | Execution failed |

---

#### POST /api/call

Calls a specific Proxy-WASM CDN hook directly. Only valid for Proxy-WASM modules.

Requires a WASM module loaded via `POST /api/load`.

**Request Body**

```typescript
{
  hook: "onRequestHeaders" | "onRequestBody" | "onResponseHeaders" | "onResponseBody";
  request?: {
    headers: Record<string, string>;  // default: {}
    body: string;                     // default: ""
  };
  response?: {
    headers: Record<string, string>;  // default: {}
    body: string;                     // default: ""
  };
  properties?: Record<string, unknown>; // defaults to {} when omitted
}
```

`request` and `response` default to `{ headers: {}, body: "" }` if omitted. The published `api-call` JSON schema lists `properties` as required; the server accepts a body without it and uses `{}`.

**Response**

```typescript
{
  ok: true;
  result: HookResult;
}
```

`HookResult` has the same shape as documented under `POST /api/execute`.

**Example**

```bash
curl -X POST http://localhost:5179/api/call \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -d '{
    "hook": "onRequestHeaders",
    "request": {
      "headers": { "host": "example.com", "user-agent": "curl/8.0" },
      "body": ""
    },
    "response": {
      "headers": {},
      "body": ""
    },
    "properties": {
      "client.geo.country": "US"
    }
  }'
```

```json
{
  "ok": true,
  "result": {
    "returnCode": 0,
    "logs": [
      { "level": 2, "message": "processing request headers" }
    ],
    "input": {
      "request": {
        "headers": { "host": "example.com", "user-agent": "curl/8.0" },
        "body": ""
      },
      "response": { "headers": {}, "body": "" },
      "properties": { "client.geo.country": "US" }
    },
    "output": {
      "request": {
        "headers": { "host": "example.com", "user-agent": "curl/8.0", "x-country": "US" },
        "body": ""
      },
      "response": { "headers": {}, "body": "" }
    },
    "properties": { "client.geo.country": "US" }
  }
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `400` | Body failed validation (invalid `hook`, malformed `request` or `response`) |
| `400` | No WASM module is loaded |
| `500` | Hook execution failed, including calling a hook on an HTTP-WASM module |

---

#### POST /api/send

Executes the full Proxy-WASM CDN request/response flow with stricter Zod schema validation than `POST /api/execute`. Only valid for Proxy-WASM modules.

The upstream response is generated at runtime — either by a real fetch against `url`, or by the built-in responder when `url === "built-in"`.

Requires a WASM module loaded via `POST /api/load`. Accepts optional `X-Source` header.

**Request Body**

```typescript
{
  url: string | "built-in";             // Full request URL, or "built-in" to use the built-in responder
  request?: {
    method?: string;                    // HTTP method (default: "GET")
    url?: string;
    headers?: Record<string, string>;   // Request headers (default: {})
    body?: string;                      // Request body (default: "")
  };
  properties?: Record<string, unknown>; // CDN properties; defaults to {} when omitted
}
```

The published `api-send` JSON schema lists `properties` as required; the server accepts a body without it and uses `{}`.

**Response**

```typescript
{
  ok: true;
  hookResults: Record<string, HookResult>;  // Keyed by hook name
  finalResponse: {
    status: number;
    statusText: string;
    headers: Record<string, string | string[]>;
    body: string;
    contentType: string;
    isBase64?: boolean;
  };
  calculatedProperties?: Record<string, unknown>;  // Keys follow request.* pattern
}
```

`HookResult` has the same shape as documented under `POST /api/execute`. `calculatedProperties` uses the same `request.*` keys listed under `POST /api/execute`.

**Example**

```bash
curl -X POST http://localhost:5179/api/send \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -H "X-Source: ai_agent" \
  -d '{
    "url": "https://example.com/api/resource",
    "request": {
      "method": "POST",
      "headers": { "content-type": "application/json" },
      "body": "{\"key\":\"value\"}"
    },
    "properties": {
      "client.geo.country": "DE"
    }
  }'
```

```json
{
  "ok": true,
  "hookResults": {
    "onRequestHeaders": {
      "returnCode": 0,
      "logs": [],
      "input": {
        "request": { "headers": { "content-type": "application/json" }, "body": "" },
        "response": { "headers": {}, "body": "" },
        "properties": { "client.geo.country": "DE" }
      },
      "output": {
        "request": { "headers": { "content-type": "application/json" }, "body": "" },
        "response": { "headers": {}, "body": "" }
      },
      "properties": { "client.geo.country": "DE" }
    },
    "onResponseHeaders": {
      "returnCode": 0,
      "logs": [],
      "input": {
        "request": { "headers": { "content-type": "application/json" }, "body": "" },
        "response": { "headers": { "content-type": "application/json" }, "body": "" },
        "properties": { "client.geo.country": "DE" }
      },
      "output": {
        "request": { "headers": { "content-type": "application/json" }, "body": "" },
        "response": { "headers": { "content-type": "application/json" }, "body": "" }
      },
      "properties": { "client.geo.country": "DE" }
    }
  },
  "finalResponse": {
    "status": 200,
    "statusText": "OK",
    "headers": { "content-type": "application/json" },
    "body": "{\"result\":\"ok\"}",
    "contentType": "application/json"
  },
  "calculatedProperties": {
    "request.url": "https://example.com/api/resource",
    "request.host": "example.com",
    "request.path": "/api/resource",
    "request.query": "",
    "request.scheme": "https",
    "request.extension": "",
    "request.method": "POST"
  }
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `400` | Body failed validation (`url` missing or neither `"built-in"` nor a valid URL) |
| `400` | No WASM module is loaded |
| `500` | Execution failed, including use against an HTTP-WASM module |

---

### Configuration

#### GET /api/config

Reads `fastedge-config.test.json` from the `.fastedge-debug/` directory (relative to `WORKSPACE_PATH` if set, otherwise the current working directory) and returns it with a validation result. A relative `dotenv.path` in the file is returned as an absolute path resolved against the config file's directory.

**Response**

```typescript
{
  ok: true;
  config: TestConfig;
  valid: boolean;
  validationErrors?: {
    formErrors: string[];
    fieldErrors: Record<string, string[]>;
  };
}
```

`config` is returned as stored, even when `valid` is `false`.

**TestConfig type** — discriminated union on `appType`:

```typescript
// Proxy-WASM config (appType defaults to "proxy-wasm")
type ProxyWasmConfig = {
  $schema?: string;
  description?: string;
  appType: "proxy-wasm";
  wasm?: { path: string; description?: string };
  request: {
    method: string;
    url: string;
    headers: Record<string, string>;
    body: string;
  };
  properties: Record<string, unknown>;
  dotenv?: { enabled?: boolean; path?: string };
};

// HTTP-WASM config
type HttpWasmConfig = {
  $schema?: string;
  description?: string;
  appType: "http-wasm";
  wasm?: { path: string; description?: string };
  httpPort?: number;  // Pin the runner subprocess to this port (1024–65535)
  request: {
    method: string;
    path: string;
    headers: Record<string, string>;
    body: string;
  };
  properties: Record<string, unknown>;
  dotenv?: { enabled?: boolean; path?: string };
};

type TestConfig = ProxyWasmConfig | HttpWasmConfig;
```

**Example**

```bash
curl -H "x-fastedge-token: <token>" http://localhost:5179/api/config
```

```json
{
  "ok": true,
  "config": {
    "$schema": "http://localhost:5179/api/schema/fastedge-config.test",
    "appType": "proxy-wasm",
    "request": {
      "method": "GET",
      "url": "https://example.com/",
      "headers": {},
      "body": ""
    },
    "properties": {}
  },
  "valid": true
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `404` | `fastedge-config.test.json` is missing or cannot be parsed |

---

#### POST /api/config

Saves the provided configuration to `.fastedge-debug/fastedge-config.test.json` (relative to `WORKSPACE_PATH` if set, otherwise the current working directory). The directory is created if it does not exist. If the config includes a `properties` field, a WebSocket event is broadcast to connected clients.

Accepts optional `X-Source` header.

**Request Body**

```typescript
{
  config: TestConfig; // See GET /api/config for the TestConfig type
}
```

The `config` object must match one of the two `TestConfig` variants. `appType` defaults to `"proxy-wasm"` when omitted. `request` is required and its shape depends on `appType`: `path` for `"http-wasm"`, `url` for `"proxy-wasm"`.

**Response**

```typescript
{
  ok: true;
}
```

**Example**

```bash
curl -X POST http://localhost:5179/api/config \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -H "X-Source: api" \
  -d '{
    "config": {
      "$schema": "http://localhost:5179/api/schema/fastedge-config.test",
      "appType": "proxy-wasm",
      "request": {
        "method": "GET",
        "url": "https://example.com/",
        "headers": { "accept": "text/html" },
        "body": ""
      },
      "properties": {
        "client.geo.country": "US"
      }
    }
  }'
```

```json
{
  "ok": true
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `400` | Body failed validation (`config` does not match either `TestConfig` variant) |
| `500` | File write failed |

---

#### POST /api/config/save-as

Saves the provided configuration to a file path previously approved by the host application's save dialog. Paths are single-use: each approved path is removed once consumed. Creates intermediate directories as needed.

Approved paths are only issued when the server runs inside a host application that provides a save dialog (Electron). In a plain Node.js or CLI session no path is ever approved, so every request to this endpoint with a valid body returns `403`. Use `POST /api/config` to save configuration programmatically.

**Request Body**

```typescript
{
  config: TestConfig;  // The configuration to serialize as JSON; same shape as POST /api/config
  filePath: string;    // A path previously approved by the host's save dialog
}
```

**Response**

```typescript
{
  ok: true;
  savedPath: string;  // The file path where the config was written
}
```

**Example**

```bash
curl -X POST http://localhost:5179/api/config/save-as \
  -H "Content-Type: application/json" \
  -H "x-fastedge-token: <token>" \
  -d '{
    "config": {
      "appType": "proxy-wasm",
      "request": {
        "method": "GET",
        "url": "https://example.com/",
        "headers": {},
        "body": ""
      },
      "properties": {}
    },
    "filePath": "/home/user/project/configs/staging.test.json"
  }'
```

```json
{
  "ok": true,
  "savedPath": "/home/user/project/configs/staging.test.json"
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `400` | Body failed validation (`config` invalid or `filePath` missing) |
| `403` | `filePath` was not approved by the host's save dialog, or was already used |
| `500` | File write or directory creation failed |

---

### Schema

#### GET /api/schema/:name

Serves a JSON Schema file by name. The `:name` parameter is the schema name without the `.schema.json` suffix. Returns the JSON Schema document with `Content-Type: application/json`.

**Request Schemas**

| Name | Description |
|---|---|
| `api-load` | Request body schema for `POST /api/load` |
| `api-send` | Request body schema for `POST /api/send` |
| `api-call` | Request body schema for `POST /api/call` |
| `api-config` | Request body schema for `POST /api/config` |

**Response / Type Schemas**

| Name | Description |
|---|---|
| `fastedge-config.test` | Schema for `fastedge-config.test.json` config files |
| `hook-result` | Shape of a single `HookResult` object |
| `hook-call` | Shape of a `HookCall` input object |
| `full-flow-result` | Shape of the `FullFlowResult` returned by full-flow endpoints |
| `http-request` | Shape of an `HttpRequest` for HTTP-WASM execution |
| `http-response` | Shape of an `HttpResponse` returned by HTTP-WASM execution |

**Example**

```bash
curl -H "x-fastedge-token: <token>" http://localhost:5179/api/schema/api-send
```

```bash
curl -H "x-fastedge-token: <token>" http://localhost:5179/api/schema/fastedge-config.test
```

**Using the schema in a config file**

```json
{
  "$schema": "http://localhost:5179/api/schema/fastedge-config.test",
  "appType": "proxy-wasm",
  "request": {
    "method": "GET",
    "url": "https://example.com/",
    "headers": {},
    "body": ""
  },
  "properties": {}
}
```

**Error Responses**

| Status | Condition |
|---|---|
| `404` | Schema name not found |

---

### Error Handling

All error responses follow a consistent shape:

```typescript
{
  ok: false;
  error: string | { formErrors: string[]; fieldErrors: Record<string, string[]> };
}
```

When a request body fails schema validation (Zod), `error` is a flattened Zod error object with `formErrors` and `fieldErrors`. For runtime errors, `error` is a plain string.

**Common status codes**

| Status | Meaning |
|---|---|
| `400` | Invalid request body, missing required fields, or precondition not met (e.g. no WASM loaded) |
| `401` | Missing or invalid `x-fastedge-token` header on an `/api/*` request |
| `403` | `Host` header not allowed, or a save-as path was not approved by the host's save dialog |
| `404` | Resource not found (config file, schema file) |
| `500` | Internal server error during execution or I/O |

---

## WebSocket Protocol

### Authentication

The server accepts the session token via two mechanisms, tried in this order:

1. **`Sec-WebSocket-Protocol: fastedge-token.<token>`** (preferred) — the token is embedded in the subprotocol list, keeping it out of URLs and proxy access logs. The server echoes the matching subprotocol back on accept.
2. **`?token=<token>` query parameter** (fallback) — for legacy or non-browser tooling that cannot set subprotocols. Avoid in new consumers: the token appears in server and proxy logs.

A handshake is rejected if the token is missing or incorrect, or if the client offers subprotocols and none of them starts with `fastedge-token.`.

**Preferred: subprotocol**

```javascript
const token = new URL(location.href).hash.slice("#token=".length);
const ws = new WebSocket("ws://localhost:5179/ws", [`fastedge-token.${token}`]);
```

**Fallback: query parameter**

```
ws://127.0.0.1:<port>/ws?token=<token>
```

### Connection

Connect to:

```
ws://localhost:{port}/ws
```

Default port: `5179`. Pass the token via one of the two mechanisms described above.

```javascript
const token = new URL(location.href).hash.slice("#token=".length);
const ws = new WebSocket("ws://localhost:5179/ws", [`fastedge-token.${token}`]);

ws.addEventListener("message", (event) => {
  const msg = JSON.parse(event.data);
  console.log(msg.type, msg.data);
});
```

Browser connections are subject to an origin check. Origins on `localhost`, `127.0.0.1`, and `vscode-webview://` are accepted. Other hosts are accepted only if they match the host configured via `FASTEDGE_EXPECTED_HOST`. Clients that send no `Origin` header (e.g. Node.js test tooling) are not subject to the origin check.

### Lifecycle

1. **Connect** — server validates the token and origin, then immediately sends a `connection_status` event to the new client with the current client count. It then broadcasts an updated `connection_status` to all connected clients, including the new one.
2. **Ping / pong** — server sends WebSocket `ping` frames every 15 seconds. Clients that have not responded within 30 seconds are terminated. Standard WebSocket clients handle pong automatically.
3. **Disconnect** — when a client disconnects, the server broadcasts an updated `connection_status` to remaining clients.
4. **Server shutdown** — the server closes all connections with close code `1000` and reason `Server shutting down`.

### Event Envelope

Every event shares a common envelope:

```typescript
interface BaseEvent {
  type: string;       // event discriminant
  timestamp: number;  // Unix ms
  source: "ui" | "ai_agent" | "api" | "system";
  data: object;       // event-specific payload
}
```

### Event Types

#### wasm_loaded

Fired when a WASM binary has been loaded and is ready to handle requests.

```typescript
{
  type: "wasm_loaded";
  timestamp: number;
  source: "ui" | "ai_agent" | "api" | "system";
  data: {
    filename: string;
    size: number;                          // File size in bytes
    runnerPort?: number | null;            // Port the runner is listening on, if applicable
    wasmType: "proxy-wasm" | "http-wasm";
    resolvedPath?: string | null;          // Absolute filesystem path to the loaded binary
  };
}
```

**Example**

```json
{
  "type": "wasm_loaded",
  "timestamp": 1742734800000,
  "source": "api",
  "data": {
    "filename": "filter.wasm",
    "size": 204800,
    "runnerPort": 8081,
    "wasmType": "proxy-wasm",
    "resolvedPath": "/workspace/filter.wasm"
  }
}
```

---

#### request_started

Fired when the server begins processing an incoming request through the WASM filter.

```typescript
{
  type: "request_started";
  timestamp: number;
  source: "ui" | "ai_agent" | "api" | "system";
  data: {
    url: string;
    method: string;
    headers: Record<string, string | string[]>;
  };
}
```

**Example**

```json
{
  "type": "request_started",
  "timestamp": 1742734800100,
  "source": "api",
  "data": {
    "url": "https://example.com/api/resource",
    "method": "GET",
    "headers": {
      "host": "example.com",
      "user-agent": "curl/8.0"
    }
  }
}
```

---

#### hook_executed

Fired after each individual Proxy-WASM hook completes. Multiple events are emitted per request — one per hook phase that runs. Hook names are camelCase: `onRequestHeaders`, `onRequestBody`, `onResponseHeaders`, `onResponseBody`.

```typescript
{
  type: "hook_executed";
  timestamp: number;
  source: "ui" | "ai_agent" | "api" | "system";
  data: {
    hook: string;               // e.g. "onRequestHeaders"
    returnCode: number | null;  // Return code from the WASM filter, or null if unavailable
    logCount: number;           // Number of log lines emitted during this hook
    input: {
      request: { headers: Record<string, string | string[]>; body: string };
      response: { headers: Record<string, string | string[]>; body: string };
    };
    output: {
      request: { headers: Record<string, string | string[]>; body: string };
      response: { headers: Record<string, string | string[]>; body: string };
    };
  };
}
```

**Example**

```json
{
  "type": "hook_executed",
  "timestamp": 1742734800200,
  "source": "api",
  "data": {
    "hook": "onRequestHeaders",
    "returnCode": 0,
    "logCount": 2,
    "input": {
      "request": { "headers": { "host": "example.com" }, "body": "" },
      "response": { "headers": {}, "body": "" }
    },
    "output": {
      "request": { "headers": { "host": "example.com", "x-injected": "true" }, "body": "" },
      "response": { "headers": {}, "body": "" }
    }
  }
}
```

---

#### request_completed

Fired when all hook phases have completed and a final response is available. `hookResults` keys are camelCase hook names.

```typescript
{
  type: "request_completed";
  timestamp: number;
  source: "ui" | "ai_agent" | "api" | "system";
  data: {
    hookResults: Record<string, any>;  // Keyed by hook name
    finalResponse: {
      status: number;
      statusText: string;
      headers: Record<string, string | string[]>;
      body: string;                    // May be base64 if isBase64 is true
      contentType: string;
      isBase64?: boolean;
    };
    calculatedProperties?: Record<string, unknown>;
  };
}
```

**Example**

```json
{
  "type": "request_completed",
  "timestamp": 1742734800500,
  "source": "api",
  "data": {
    "hookResults": {
      "onRequestHeaders": { "returnCode": 0 },
      "onResponseHeaders": { "returnCode": 0 }
    },
    "finalResponse": {
      "status": 200,
      "statusText": "OK",
      "headers": { "content-type": "application/json" },
      "body": "{\"ok\":true}",
      "contentType": "application/json",
      "isBase64": false
    },
    "calculatedProperties": {}
  }
}
```

---

#### request_failed

Fired when request processing fails before a response can be produced.

```typescript
{
  type: "request_failed";
  timestamp: number;
  source: "ui" | "ai_agent" | "api" | "system";
  data: {
    error: string;     // Short error message
    details?: string;  // Extended error detail or stack trace, if available
  };
}
```

**Example**

```json
{
  "type": "request_failed",
  "timestamp": 1742734800300,
  "source": "api",
  "data": {
    "error": "WASM execution error",
    "details": "RuntimeError: memory access out of bounds"
  }
}
```

---

#### properties_updated

Fired when the set of active properties changes (e.g. after a properties configuration update).

```typescript
{
  type: "properties_updated";
  timestamp: number;
  source: "ui" | "ai_agent" | "api" | "system";
  data: {
    properties: Record<string, string>;  // Full current property map after the update
  };
}
```

**Example**

```json
{
  "type": "properties_updated",
  "timestamp": 1742734800050,
  "source": "ui",
  "data": {
    "properties": {
      "plugin.name": "my-filter",
      "plugin.version": "1.0.0"
    }
  }
}
```

---

#### http_wasm_request_completed

Fired when an http-wasm filter finishes processing a request and a response is available.

`response.headers` mirrors Node's `IncomingHttpHeaders` — `undefined` values are dropped during JSON serialization and will not appear on the wire.

```typescript
{
  type: "http_wasm_request_completed";
  timestamp: number;
  source: "ui" | "ai_agent" | "api" | "system";
  data: {
    response: {
      status: number;
      statusText: string;
      headers: Record<string, string | string[] | undefined>;  // undefined values omitted in JSON
      body: string;                   // May be base64 if isBase64 is true
      contentType: string | null;
      isBase64?: boolean;
    };
  };
}
```

**Example**

```json
{
  "type": "http_wasm_request_completed",
  "timestamp": 1742734800600,
  "source": "api",
  "data": {
    "response": {
      "status": 200,
      "statusText": "OK",
      "headers": { "content-type": "text/plain" },
      "body": "Hello, world!",
      "contentType": "text/plain",
      "isBase64": false
    }
  }
}
```

---

#### http_wasm_log

Fired in real-time as the http-wasm filter emits log lines during execute and live modes. One event per log line.

```typescript
{
  type: "http_wasm_log";
  timestamp: number;
  source: "ui" | "ai_agent" | "api" | "system";
  data: {
    level: number;    // Log level (follows proxy-wasm log level conventions)
    message: string;
  };
}
```

**Example**

```json
{
  "type": "http_wasm_log",
  "timestamp": 1742734800250,
  "source": "api",
  "data": {
    "level": 2,
    "message": "processing request to /api/resource"
  }
}
```

---

#### connection_status

Fired in three situations: (1) immediately after a client connects (sent only to that client), (2) when any client connects or disconnects (broadcast to all clients), (3) in response to a client `ping` message. The server always sets `source` to `"system"` for this event.

```typescript
{
  type: "connection_status";
  timestamp: number;
  source: "system";
  data: {
    connected: boolean;  // Always true when received
    clientCount: number; // Total connected clients including this one
  };
}
```

**Example**

```json
{
  "type": "connection_status",
  "timestamp": 1742734800010,
  "source": "system",
  "data": {
    "connected": true,
    "clientCount": 1
  }
}
```

---

### Client Messages

The server accepts one client-to-server message type. Messages must be JSON text. Unparseable messages and unrecognised message types are ignored.

#### ping

Requests a `connection_status` response from the server. Verifies the connection at the application level, independent of WebSocket ping/pong frames.

```json
{ "type": "ping" }
```

The server responds by sending a `connection_status` event to the requesting client.

All other operations (loading WASM, triggering requests, updating properties) are submitted via the REST API.

---

## Server Startup

Start the debugger server programmatically via the `@gcoredev/fastedge-test/server` export:

```javascript
import { startServer } from "@gcoredev/fastedge-test/server";
```

The server listens on port `5179` by default. Override with the `PORT` environment variable. When the preferred port is busy, the server tries the next ports in sequence (50 attempts in total) before failing.

When `WORKSPACE_PATH` is set, the active port is written to `$WORKSPACE_PATH/.fastedge-debug/.debug-port` on startup and removed on shutdown. The file contains `PORT:SHA256_HASH` — consumers that only need the port should parse the prefix up to the first colon (e.g. `parseInt(content.split(":")[0], 10)`). Use this file to discover the port dynamically in CI or multi-process tooling.

---

## See Also

- API reference: REST endpoints for triggering requests, loading WASM, and managing configuration
- WEBSOCKET reference: WebSocket protocol and event types
- DEBUGGER reference: Server startup, configuration, and environment variables
- TEST_FRAMEWORK reference: Programmatic test framework API
- RUNNER reference: Runner API and WASM type detection
