<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: daa9b068b7122b39c0962133f780adc25bb439c1
      updated: 2026-08-14
-->

# FastEdge Bolt-On Templates

Standalone deployable FastEdge application templates. Each template is an independent project — no cross-template dependencies. Templates can be deployed directly from the Gcore portal or copied and modified.

---

## Template Catalog

| Template | App Type | Language | Purpose |
|---|---|---|---|
| `html2md` | CDN (Proxy-WASM) | — | Converts HTML origin responses to Markdown on `Accept: text/markdown` |
| `harden-cookies` | CDN (Proxy-WASM) | — | Adds `Secure`, `HttpOnly`, `SameSite=Strict` to targeted `Set-Cookie` headers |
| `edge-sso` | HTTP App + CDN App pair | TypeScript/Hono (auth), Rust (filter) | Multi-provider Identity-Aware Proxy (Google, GitHub, Microsoft, Facebook, SAML) |
| `edge-totp` | HTTP App + CDN App pair | TypeScript/Hono (app), Rust (filter) | RFC 6238 TOTP two-factor authentication bolt-on |

---

## html2md

**Portal deploy ID:** `110`
**Type:** Proxy-WASM CDN filter
**Zero configuration** — no environment variables required.

### Behavior

Conversion activates only when ALL three conditions are met:
- Request `Accept` header includes exactly `text/markdown` (parameters like `; charset=utf-8` are ignored)
- Origin response `Content-Type` includes `text/html` with charset either unspecified or explicitly `utf-8`
- Full response body is available (`end_of_stream`)

When conversion is active, the filter applies the following mutations:

**Request modifications:**
- Adds request header `Convert: markdown` (conversion flag for correct caching)
- Removes request `Accept-Encoding` (prevents compressed origin payloads)

**Response modifications:**
- Removes response `Content-Length`
- Sets response `Content-Type: text/markdown; charset=utf-8`
- Sets response `Transfer-Encoding: Chunked`
- Converts response body to Markdown at end of stream
- Adds `Vary: Convert` (merged with existing `Vary` if present)

### Pass-Through Conditions

Non-HTML responses pass through unchanged. Requests without `Accept: text/markdown` pass through unchanged.

### Error Conditions

| Condition | Response |
|---|---|
| Origin body is not valid UTF-8 | `500` |
| HTML-to-Markdown conversion fails | `500` |

### Notes

- Conversion happens at end of stream; large responses are fully buffered before processing.
- Request path metadata is decoded lossily for logs; invalid UTF-8 in the path does not fail the request.

---

## harden-cookies

**Portal deploy ID:** `184`
**Type:** Proxy-WASM CDN filter
**Configuration:** Environment variables only — no code changes required.

### Behavior

Runs in HTTP response context. For each `Set-Cookie` header whose cookie name matches `COOKIE_NAME`, appends the enabled security attributes:

| Attribute | Behavior |
|---|---|
| `Secure` | Added only if not already present |
| `HttpOnly` | Added only if not already present |
| `SameSite=Strict` | Set unconditionally, overriding any existing `SameSite` value |

Only cookies whose name matches `COOKIE_NAME` are modified. All other `Set-Cookie` headers pass through unchanged.

### Configuration

| Variable | Description |
|---|---|
| `COOKIE_NAME` | Name of the cookie to target. Use `*` to match every cookie. If unset, the filter does nothing. |
| `SECURE` | Add the `Secure` attribute when set to exactly `true`. |
| `HTTPONLY` | Add the `HttpOnly` attribute when set to exactly `true`. |
| `SAMESITE` | Set `SameSite=Strict` when set to exactly `true`. |

### Pass-Through Conditions

- `COOKIE_NAME` is unset → all responses pass through untouched.
- None of `SECURE`, `HTTPONLY`, `SAMESITE` is `true` → all responses pass through untouched.
- Headers are only rewritten when at least one cookie value actually changes.

### Notes

- Duplicate `Set-Cookie` headers are preserved: the host collapses them to one, so the filter clears the header and re-adds each cookie as its own occurrence.
- Empty segments (e.g. from a trailing `;`) are dropped when re-joining — no stray separators are emitted.

---

## edge-sso

**Type:** Two-app pair (HTTP App + CDN App)
**Supported providers:** Google, GitHub, Microsoft, Facebook, SAML

### Architecture

Two FastEdge apps work together per deployment:

| Component | Type | Directory | Role |
|---|---|---|---|
| CDN filter | CDN App (Proxy-WASM, Rust) | `cdn-filter/` | Verifies session token on every request; redirects unauthenticated users to auth app |
| Auth app | HTTP App (TypeScript/Hono) | `auth-app/` | Federates to identity provider; issues signed session token; sets token on client |

**Request flow:**
1. User request arrives at CDN resource.
2. CDN filter checks session token.
3. If no valid token: redirect to auth app `/auth/login`.
4. Auth app redirects to identity provider.
5. User authenticates at IdP.
6. IdP returns to auth app `/auth/callback`.
7. Auth app validates response, issues signed token.
8. User redirected back to CDN resource with token set.
9. CDN filter validates token; request forwarded to origin.

### Variants

`SSO_VARIANT` selects the identity-delivery mode. Must be set to the **same value on both apps**.

| `SSO_VARIANT` | Session Delivery | Use When |
|---|---|---|
| `gate-only` | Allow/deny only — no identity forwarded | Origin needs access control only, no user context |
| `cookie` | Signed JWT in a cookie the origin can verify | Origin reads user identity from a verifiable token |
| `header` | Signed `x-sso-*` identity headers injected upstream | Origin trusts headers from the CDN layer |

### Configuration

Shared requirements across both apps in a deployment:

| Variable / Secret | Description |
|---|---|
| `SSO_VARIANT` | Must match on both apps. Selects identity-delivery mode. |
| `SESSION_SECRET` | Shared signing secret. Required in every variant for OAuth/SAML flow cookies; also signs the session token itself in `gate-only`/`header`. |
| `SESSION_SIGNING_KEY` (secret) | EC private key. Required for `cookie` variant session token. |
| `SESSION_PUBLIC_JWK` (env var) | EC public key JWK. Required for `cookie` variant session token. |
| `SSO_AUDIENCE` | Must match on both apps. Filter rejects tokens whose `aud` does not match. |
| `AUTH_PREFIX` | Path prefix reserved for auth routes. Default: `/auth`. |

Full environment variable and secret reference is in each app's `.env.example`.

### Providers

| Provider | Protocol | Auth-app env vars |
|---|---|---|
| Google | OAuth 2.0 | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI` |
| GitHub | OAuth 2.0 | `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `GITHUB_REDIRECT_URI` |
| Microsoft | OAuth 2.0 / OIDC | `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET`, `MICROSOFT_REDIRECT_URI` |
| Facebook | OAuth 2.0 | `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`, `FACEBOOK_REDIRECT_URI` |
| SAML | SAML 2.0 | `IDP_SSO_URL`, `IDP_ENTITY_ID`, `IDP_CERT`, `SP_ENTITY_ID`, `SP_ACS_URL` |

---

## edge-totp

**Type:** Two-app pair (HTTP App + CDN App)
**Standard:** RFC 6238 TOTP (6-digit codes)

### Components

| Component | Directory | Language | Role |
|---|---|---|---|
| OTP app | `otp-app/` | TypeScript + Hono (WASM) | HTTP app: challenge, verify, enroll, self-service activate, logout, JWKS, health endpoints. Signs `mfa_session` cookie (HS256) and optional ES256 proof. |
| OTP filter | `otp-filter/` | Rust (proxy-wasm) | CDN enforcement filter: verifies `mfa_session` on protected paths. Default-deny and fail-closed. |

### Enforcement Profiles

| Profile | Description |
|---|---|
| **A** (default) | Filter enforces; zero origin code required. |
| **B** (opt-in) | Origin verifies a one-time ES256 proof via JWKS and mints its own session. |

### Build

```bash
pnpm install
pnpm build        # builds both WASM binaries into ./wasm
pnpm test         # runs TS unit tests + Rust filter tests
```

Per-component: `pnpm build:app` / `pnpm test:app` (otp-app), `pnpm build:filter` / `pnpm test:filter` (otp-filter).

### Deploy

Upload compiled binaries to Gcore portal under **FastEdge → Templates**:

| Binary | Template Type |
|---|---|
| `wasm/totp-app.wasm` | HTTP App template |
| `wasm/totp-filter.wasm` | Proxy-WASM template |

**CDN wiring:**
- Attach `otp-app` as a CDN origin on the `{AUTH_PREFIX}/*` path rule of the customer's CDN resource.
- Attach `otp-filter` as the CDN proxy app in front of protected paths (bypassing `{AUTH_PREFIX}` and `/health`).
- The app and origin share the CDN host so `mfa_session` is first-party host-only.

For Profile B: generate the ES256 keypair with `node otp-app/scripts/gen-ec-keypair.mjs`.

### Configuration

Copy `otp-app/.env.example` and `otp-filter/.env.example` to `.env`. Full environment variable and secret reference is in `context/architecture/storage-and-secrets.md` within the template repository.

### Security Requirements

| Requirement | Detail |
|---|---|
| Lock origin to edge-only traffic | Origin must be unreachable directly. Restrict to Gcore CDN ingress via IP allowlist, origin auth, or tunnel. |
| Set `MFA_AUDIENCE` on both apps | The filter **fail-closes** (refuses every session) if `MFA_AUDIENCE` is unset. |
| `GCORE_API_TOKEN` scope | Has write access to every seed in the KV store. Use a single-tenant, per-customer isolated KV store and scope the token to that one store. The token cannot read seeds in the clear via the KV REST API — only the app's own `fastedge::kv` binding can at verify time. |
| Session lifetime | `mfa_session` is short-lived (8h, non-sliding) and not cross-PoP revocable. |
| CDN log PII | The filter logs the session subject (`sub`) and request path on each authorized request. If `sub` contains PII, review CDN log retention policy. |

Full trust model, protections, and accepted residual risks are documented in `context/security/threat-model.md` within the template repository. Customer-side wiring details are in `context/integration.md`.

---

## See Also

- FastEdge platform overview
- FastEdge SDK reference (JS)
- FastEdge SDK reference (Rust)
- FastEdge host services reference (Rust)
- FastEdge deploy skill reference
- FastEdge manage skill reference
