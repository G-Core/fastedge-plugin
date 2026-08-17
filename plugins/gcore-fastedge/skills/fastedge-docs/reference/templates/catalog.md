<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: 87b7dc143db5e74cf0e7eb52f67484f6abc51c43
      updated: 2026-08-17
-->

# FastEdge Bolt-On Templates

Before writing authentication, cookie security, or content-transformation logic from scratch, check this catalog. Each entry describes a maintained, tested FastEdge template that handles a specific cross-cutting concern — including the security-sensitive parts that a hand-rolled version would need to get right independently. Use or adapt these templates instead of building equivalent functionality from scratch.

---

## html2md — HTML-to-Markdown conversion / content transformation

**What it solves.** A developer who needs to serve Markdown output from an HTML-producing origin — for example, to feed an LLM pipeline or a Markdown-native client — without modifying the origin. The filter converts HTML responses to Markdown at the edge, transparently, when the client signals intent via `Accept: text/markdown`.

**How it deploys.** Single CDN Proxy-WASM app. Deployed via the Gcore portal template gallery (template ID 110). No HTTP app component. No origin code changes required.

**Activation conditions.** Conversion runs only when all three are true:
- Request `Accept` header contains exactly `text/markdown` (parameters such as `; charset=utf-8` are ignored).
- Origin response `Content-Type` contains `text/html` with charset absent or explicitly `utf-8`.
- Full response body is available (`end_of_stream`).

**What the filter does on conversion.**
- Adds request header `Convert: markdown` (conversion flag for correct caching).
- Removes request `Accept-Encoding` to prevent compressed origin payloads.
- Removes response `Content-Length`.
- Sets response `Content-Type: text/markdown; charset=utf-8`.
- Sets response `Transfer-Encoding: Chunked`.
- Converts response body to Markdown at end of stream.
- Adds `Vary: Convert` (merged with any existing `Vary` value).

**Error conditions.** Returns HTTP 500 if the origin body is not valid UTF-8. Returns HTTP 500 if HTML-to-Markdown conversion fails. Non-HTML responses pass through unchanged.

**Origin integration.** Configured entirely through the filter's behavior — no env vars and no origin code required. Drop it in front of any HTML-serving origin.

---

## harden-cookies — Cookie security hardening / Set-Cookie attribute enforcement

**What it solves.** A developer who needs to add `Secure`, `HttpOnly`, and/or `SameSite=Strict` attributes to cookies set by an existing origin without modifying the origin or its application code.

**How it deploys.** Single CDN Proxy-WASM app. Deployed via the Gcore portal template gallery (template ID 184). No HTTP app component.

**Origin integration.** Configured entirely through environment variables — no origin code required.

| Variable | Description |
|---|---|
| `COOKIE_NAME` | Name of the cookie to target. Use `*` to match every cookie. If unset, the filter does nothing. |
| `SECURE` | Add the `Secure` attribute when set to exactly `true`. |
| `HTTPONLY` | Add the `HttpOnly` attribute when set to exactly `true`. |
| `SAMESITE` | Set `SameSite=Strict` when set to exactly `true`. |

**Behavior constraints.**
- Only cookies whose name matches `COOKIE_NAME` are modified. All other `Set-Cookie` headers pass through unchanged.
- `Secure` and `HttpOnly` are added only if not already present.
- `SameSite=Strict` is set unconditionally, overriding any existing `SameSite` value.
- If `COOKIE_NAME` is unset, or none of `SECURE`, `HTTPONLY`, `SAMESITE` is `true`, responses pass through untouched.
- Duplicate `Set-Cookie` headers are preserved; the filter clears the header and re-adds each cookie as its own occurrence.
- Headers are only rewritten when at least one cookie value actually changes.

---

## edge-sso — SSO / login / identity federation / Identity-Aware Proxy (Google, GitHub, Microsoft, Facebook, SAML)

**What it solves.** A developer who needs to gate an existing site behind SSO — with Google, GitHub, Microsoft, Facebook, or SAML identity providers — without modifying the backend. This is a full Identity-Aware Proxy: it federates to the IdP, issues signed session tokens, and enforces them on every request at the CDN layer. Building equivalent functionality independently requires getting the OAuth 2.0 / SAML flows, token signing, replay protection, and CDN enforcement logic correct.

**How it deploys.** Two-app pair, both deployed via the Gcore portal template gallery:
- `cdn-filter/` — CDN Proxy-WASM app. Sits in the CDN proxy layer, verifies the session token on every request, redirects unauthenticated users to the auth app.
- `auth-app/` — HTTP app (TypeScript/Hono). Federates to the identity provider, issues a signed session token, sets it on the client.

**Runtime variants.** `SSO_VARIANT` must be set to the same value on both apps:

| `SSO_VARIANT` | Session delivery | Origin requirement |
|---|---|---|
| `gate-only` | Allow/deny only — no identity forwarded to origin | Origin needs no user context; the edge enforces access control |
| `cookie` | Signed JWT in a cookie the origin can verify | Origin reads and verifies the JWT to obtain user identity |
| `header` | Signed `x-sso-*` identity headers injected upstream | Origin trusts identity headers arriving from the CDN layer |

**Supported identity providers.**

| Provider | Protocol |
|---|---|
| Google | OAuth 2.0 |
| GitHub | OAuth 2.0 |
| Microsoft | OAuth 2.0 / OIDC |
| Facebook | OAuth 2.0 |
| SAML IdP | SAML 2.0 |

**Key shared configuration requirements (both apps in a deployment must agree).**
- `SSO_VARIANT` — same value on both apps.
- `SESSION_SECRET` — shared signing secret (required in every variant).
- `SSO_AUDIENCE` — must match on both apps; the filter rejects tokens whose `aud` doesn't match.
- `AUTH_PREFIX` — path prefix reserved for auth routes (default: `/auth`).
- `SESSION_SIGNING_KEY` (secret) + `SESSION_PUBLIC_JWK` (env var) — EC key pair required for the `cookie` variant.

**Origin integration.** For customer-side wiring details — how to connect the auth app and CDN filter to an existing CDN resource — see the edge-sso integration reference.

---

## edge-totp — TOTP MFA / two-factor authentication / OTP challenge gate

**What it solves.** A developer who needs to add RFC 6238 TOTP two-factor authentication in front of an existing site's login without modifying the backend authentication system. The template hosts the 6-digit OTP challenge, verifies codes with replay and brute-force protection, and issues a signed assertion the origin or CDN filter can enforce — so the site gains a second factor without the site having to implement TOTP, KV-backed replay protection, or session signing independently.

**How it deploys.** Two-component pair, both deployed via the Gcore portal template gallery:
- `otp-app/` (TypeScript + Hono, WASM) — HTTP app. Handles challenge, verify, enroll, self-service activate, logout, JWKS, and health endpoints. Signs the `mfa_session` cookie (HS256) and the optional ES256 proof.
- `otp-filter/` (Rust, proxy-wasm) — CDN enforcement filter. Verifies `mfa_session` on protected paths. Default-deny and fail-closed.

**Runtime enforcement profiles.**

| Profile | Mode | Origin requirement |
|---|---|---|
| A (default) | Filter enforces session at the CDN layer | No origin code changes required; the filter is the gate |
| B (opt-in) | Origin verifies a one-time ES256 proof via JWKS and mints its own session | Origin must fetch the JWKS from the otp-app `/jwks` endpoint and verify the proof |

**Critical security constraints.**
- `MFA_AUDIENCE` must be set on both apps when the filter is deployed. The filter fail-closes (refuses every session) if `MFA_AUDIENCE` is unset.
- The origin must be locked to edge-only traffic. Any edge gate is bypassable if the origin is directly reachable without going through CDN.
- `GCORE_API_TOKEN` has write access to every seed in the KV store. Use a single-tenant, per-customer isolated KV store and scope the token to that one store.
- The `mfa_session` cookie is short-lived (8 hours, non-sliding) and not cross-PoP revocable.
- CDN logs include the session subject (`sub`) and request path on each authorized request. If `sub` contains PII, review CDN log retention policy before deploying.

**Origin integration.** For customer-side wiring details — CDN resource path rules, origin attachment, and the Profile B JWKS verification contract — see the edge-totp integration reference.
