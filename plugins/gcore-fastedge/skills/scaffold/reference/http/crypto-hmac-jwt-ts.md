<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: b78b2a80317bb632af88010816d3e54afd3bd72d
      updated: 2026-06-16
-->

---
type: feature
app_type: http
languages: [javascript]
capabilities: [auth, jwt, crypto]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/crypto-hmac-jwt
---

# Feature Blueprint: crypto-hmac-jwt

Verify HS256 JWTs at the edge using only the FastEdge runtime's built-in WebCrypto API. The signing secret is stored in FastEdge secrets — no third-party JWT library required.

## When to Use

Use this blueprint when the app must authenticate requests by verifying HS256-signed JWTs, the signing secret is managed as a FastEdge secret, and no external JWT library should be bundled into the WASM binary.

## Dependencies

```json
{
  "@gcoredev/fastedge-sdk-js": "^2.2.2"
}
```

Build script: `fastedge-build src/index.js dist/crypto-hmac-jwt.wasm`

## Imports

```js
import { getSecret } from 'fastedge::secret';
```

`TextEncoder` and `TextDecoder` are globals available in the FastEdge runtime. Instantiate them once as top-level singletons:

```js
const encoder = new TextEncoder();
const decoder = new TextDecoder();
```

## Helper: base64urlToBytes

Base64url decode is not built into the runtime. This helper must be included verbatim:

```js
function base64urlToBytes(str) {
  const padded = str.replace(/-/gu, '+').replace(/_/gu, '/') + '='.repeat((4 - (str.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.codePointAt(i);
  }
  return bytes;
}
```

- Replaces `-` → `+` and `_` → `/` (URL-safe alphabet normalization)
- Adds standard base64 padding before `atob`
- Returns `Uint8Array`

## JWT Verification Function

### Signature

```js
async function verifyJwtHs256(token, secret)
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `token` | `string` | Raw JWT string (three base64url segments joined by `.`) |
| `secret` | `string` | HMAC-SHA256 signing secret as a UTF-8 string |

### Returns

Decoded and validated JWT claims as a plain object.

### Throws

| Error message | Condition |
|---|---|
| `'malformed token: expected three segments'` | Token does not split into exactly three `.`-separated parts |
| `'invalid signature'` | `crypto.subtle.verify` returns `false` |
| `'token expired'` | `claims.exp` is a number and current Unix time ≥ `claims.exp` |

### Implementation

```js
async function verifyJwtHs256(token, secret) {
  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new Error('malformed token: expected three segments');
  }
  const [encodedHeader, encodedPayload, encodedSignature] = parts;

  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify'],
  );

  const signature = base64urlToBytes(encodedSignature);
  const signedData = encoder.encode(`${encodedHeader}.${encodedPayload}`);

  const valid = await crypto.subtle.verify('HMAC', key, signature, signedData);
  if (!valid) {
    throw new Error('invalid signature');
  }

  const claims = JSON.parse(decoder.decode(base64urlToBytes(encodedPayload)));

  if (typeof claims.exp === 'number' && Math.floor(Date.now() / 1000) >= claims.exp) {
    throw new Error('token expired');
  }

  return claims;
}
```

#### WebCrypto call details

**`crypto.subtle.importKey`**

| Argument | Value |
|---|---|
| format | `'raw'` |
| keyData | `encoder.encode(secret)` — UTF-8 bytes of the secret string |
| algorithm | `{ name: 'HMAC', hash: 'SHA-256' }` |
| extractable | `false` |
| keyUsages | `['verify']` |

**`crypto.subtle.verify`**

| Argument | Value |
|---|---|
| algorithm | `'HMAC'` |
| key | imported `CryptoKey` |
| signature | `base64urlToBytes(encodedSignature)` |
| data | `encoder.encode(`${encodedHeader}.${encodedPayload}`)` |

Returns `boolean`. Throw `'invalid signature'` when `false`.

#### Expiry check

```js
if (typeof claims.exp === 'number' && Math.floor(Date.now() / 1000) >= claims.exp) {
  throw new Error('token expired');
}
```

Only checked when `claims.exp` is present and is a `number`. Uses `Math.floor(Date.now() / 1000)` for current Unix time.

## Request Handler

### Authorization Header Parsing

```js
const auth = event.request.headers.get('authorization') ?? '';
const match = auth.match(/^Bearer\s+(.+)$/iu);
```

- Header name: `authorization` (case-insensitive by spec)
- Regex: `/^Bearer\s+(.+)$/iu` — case-insensitive, Unicode
- `match[1]` contains the raw JWT string
- If `match` is `null`: return 401 with `{ ok: false, error: 'missing or malformed Authorization header' }`

### Secret Retrieval

```js
const secret = getSecret('JWT_SECRET');
if (!secret) {
  return Response.json({ ok: false, error: 'JWT_SECRET is not configured' }, { status: 500 });
}
```

- Secret name: `JWT_SECRET`
- If the secret is not configured (returns falsy): return 500 — this is a server misconfiguration, not an auth failure

### Response Envelopes

| Condition | Status | Body |
|---|---|---|
| Missing or malformed `Authorization` header | 401 | `{ ok: false, error: 'missing or malformed Authorization header' }` |
| `JWT_SECRET` not configured | 500 | `{ ok: false, error: 'JWT_SECRET is not configured' }` |
| `verifyJwtHs256` throws any error | 401 | `{ ok: false, error: error.message }` |
| Verification succeeds | 200 | `{ ok: true, claims }` |

All responses use `Response.json(...)`.

### Full Handler

```js
async function app(event) {
  const auth = event.request.headers.get('authorization') ?? '';
  const match = auth.match(/^Bearer\s+(.+)$/iu);
  if (!match) {
    return Response.json(
      { ok: false, error: 'missing or malformed Authorization header' },
      { status: 401 },
    );
  }

  const secret = getSecret('JWT_SECRET');
  if (!secret) {
    return Response.json({ ok: false, error: 'JWT_SECRET is not configured' }, { status: 500 });
  }

  try {
    const claims = await verifyJwtHs256(match[1], secret);
    return Response.json({ ok: true, claims });
  } catch (error) {
    return Response.json({ ok: false, error: error.message }, { status: 401 });
  }
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

## Build Notes

Build command: `fastedge-build src/index.js dist/crypto-hmac-jwt.wasm`

Entry point: `src/index.js`
Output: `dist/crypto-hmac-jwt.wasm`

## Secrets Configuration

| Secret name | Type | Description |
|---|---|---|
| `JWT_SECRET` | string | HMAC-SHA256 signing secret; must be set before deployment |

Configure via the FastEdge secrets API or the manage skill before deploying.

## Error Handling Summary

| Error source | Status code | Distinguishing rule |
|---|---|---|
| Missing/malformed `Authorization` header | 401 | No Bearer token present |
| `verifyJwtHs256` throws | 401 | Auth-layer errors: bad signature, expired token, malformed token |
| `JWT_SECRET` not configured | 500 | Infrastructure/config fault — not a client error |

## See Also

- fastedge::secret reference (getSecret API)
- WebCrypto API (crypto.subtle) — available as a global in the FastEdge JS runtime
- http-base skeleton (base event listener and Response patterns)
- FastEdge deploy skill (building and uploading WASM, configuring secrets)

## Source Material

### FILE: examples/crypto-hmac-jwt/src/index.js

```js
import { getSecret } from 'fastedge::secret';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function base64urlToBytes(str) {
  const padded = str.replace(/-/gu, '+').replace(/_/gu, '/') + '='.repeat((4 - (str.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.codePointAt(i);
  }
  return bytes;
}

async function verifyJwtHs256(token, secret) {
  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new Error('malformed token: expected three segments');
  }
  const [encodedHeader, encodedPayload, encodedSignature] = parts;

  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify'],
  );

  const signature = base64urlToBytes(encodedSignature);
  const signedData = encoder.encode(`${encodedHeader}.${encodedPayload}`);

  const valid = await crypto.subtle.verify('HMAC', key, signature, signedData);
  if (!valid) {
    throw new Error('invalid signature');
  }

  const claims = JSON.parse(decoder.decode(base64urlToBytes(encodedPayload)));

  if (typeof claims.exp === 'number' && Math.floor(Date.now() / 1000) >= claims.exp) {
    throw new Error('token expired');
  }

  return claims;
}

async function app(event) {
  const auth = event.request.headers.get('authorization') ?? '';
  const match = auth.match(/^Bearer\s+(.+)$/iu);
  if (!match) {
    return Response.json(
      { ok: false, error: 'missing or malformed Authorization header' },
      { status: 401 },
    );
  }

  const secret = getSecret('JWT_SECRET');
  if (!secret) {
    return Response.json({ ok: false, error: 'JWT_SECRET is not configured' }, { status: 500 });
  }

  try {
    const claims = await verifyJwtHs256(match[1], secret);
    return Response.json({ ok: true, claims });
  } catch (error) {
    return Response.json({ ok: false, error: error.message }, { status: 401 });
  }
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

### FILE: examples/crypto-hmac-jwt/package.json

```json
{
  "name": "fastedge-example-crypto-hmac-jwt",
  "version": "1.0.0",
  "description": "FastEdge JS example: verify HS256 JWTs with the Web Crypto API",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/crypto-hmac-jwt.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.2"
  }
}
```
