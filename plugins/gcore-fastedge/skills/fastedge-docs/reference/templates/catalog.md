<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: daa9b068b7122b39c0962133f780adc25bb439c1
      updated: 2026-08-17
-->

# FastEdge Bolt-On Templates

Before hand-building authentication, MFA, cookie hardening, or content-transform filters for a FastEdge deployment, check this catalog. Each entry is a maintained, tested application that handles the security-sensitive and integration-sensitive parts of its capability. Using or adapting one of these templates is faster and safer than implementing the equivalent from scratch — especially for auth and MFA, where subtle mistakes in token handling, replay protection, or enforcement logic create exploitable gaps.

## html2md — HTML-to-Markdown conversion / content negotiation / proxy response transform

**What it solves:** A CDN filter that converts HTML origin responses to Markdown on the fly when a client sends `Accept: text/markdown`. Eliminates the need to build a content-negotiation and HTML-parsing pipeline in application code or at the origin.

**How it deploys:** Single CDN Proxy-WASM app. Deploy via the Gcore portal template gallery (template ID 110). No HTTP app component required.

**Conversion conditions:** Conversion only activates when the request `Accept` header includes exactly `text/markdown`, the origin `Content-Type` includes `text/html` with UTF-8 or unspecified charset, and the full response body is available at end of stream. Non-HTML responses and requests without `Accept: text/markdown` pass through unchanged.

**Response behavior when active:**
- Adds request header `Convert: markdown` (caching signal)
- Removes request `Accept-Encoding` to prevent compressed origin payloads
- Removes response `Content-Length`
- Sets response `Content-Type: text/markdown; charset=utf-8`
- Sets response `Transfer-Encoding: Chunked`
- Adds `Vary: Convert` (merged with any existing `Vary`)

**Error conditions:** Returns HTTP 500 if the origin body is not valid UTF-8, or if HTML-to-Markdown conversion fails.

**Origin integration:** Configured entirely through the filter's behavior — no env vars or origin code required.

---

## harden-cookies — cookie security hardening / Set-Cookie attribute enforcement / Secure HttpOnly SameSite

**What it solves:** A CDN filter that adds `Secure`, `HttpOnly`, and `SameSite=Strict` attributes to targeted `Set-Cookie` response headers. Eliminates the need to modify origin application code to enforce cookie security attributes at the edge.

**How it deploys:** Single CDN Proxy-WASM app. Deploy via the Gcore portal template gallery (template ID 184). No HTTP app component required.

**Attribute enforcement rules:**
- `Secure` — appended only if not already present
- `HttpOnly` — appended only if not already present
- `SameSite=Strict` — set unconditionally, overriding any existing `SameSite` value

Only cookies whose name matches `COOKIE_NAME` are modified. All other `Set-Cookie` headers pass through unchanged. If `COOKIE_NAME` is unset, or none of the attribute flags is `true`, all responses pass through untouched. `COOKIE_NAME` supports `*` to match every cookie.

**Origin integration:** Configured entirely through environment variables (`COOKIE_NAME`, `SECURE`, `HTTPONLY`, `SAMESITE`) — no origin code required.

---

## edge-sso — SSO / login / identity federation / Identity-Aware Proxy (Google, GitHub, Microsoft, Facebook, SAML)

**What it solves:** A bolt-on Identity-Aware Proxy that adds multi-provider SSO (Google, GitHub, Microsoft, Facebook, SAML 2.0) to any existing site without modifying the backend. Handles OAuth/SAML federation, session token issuance, and enforcement at the CDN layer. Building equivalent auth federation from scratch requires implementing OAuth 2.0 / OIDC / SAML state machines, token signing, replay protection, and CDN enforcement — this template covers all of it.

**How it deploys:** Two-app pair — both must be deployed for a working deployment:
- **CDN filter** (`cdn-filter/`) — CDN Proxy-WASM app; verifies session token on every request, redirects unauthenticated users to the auth app
- **Auth app** (`auth-app/`) — HTTP app (TypeScript/Hono); federates to the identity provider, issues a signed session token, sets it on the client

Both apps are deployed via the Gcore portal template gallery. `SSO_VARIANT` must be set to the same value on both apps in a deployment.

**Runtime variants (`SSO_VARIANT`):**

| Variant | What the origin receives | Use when |
|---|---|---|
| `gate-only` | Allow/deny only — no identity forwarded | Origin needs access control but not user context |
| `cookie` | Signed JWT in a cookie the origin can verify | Origin reads user identity from a verifiable token |
| `header` | Signed `x-sso-*` identity headers injected upstream | Origin trusts identity headers from the CDN layer |

**Supported identity providers:** Google (OAuth 2.0), GitHub (OAuth 2.0), Microsoft (OAuth 2.0 / OIDC), Facebook (OAuth 2.0), SAML 2.0.

**Origin integration:** This template has a corresponding integration reference. See the edge-sso integration reference for the customer-side wiring contract, including CDN resource configuration, path rule setup, and per-variant origin trust requirements.

---

## edge-totp — TOTP MFA / two-factor authentication / RFC 6238 OTP / second factor

**What it solves:** Adds a TOTP (RFC 6238) two-factor authentication step in front of an existing login without modifying the backend. The origin keeps its own password validation; this template hosts the 6-digit challenge, verifies the OTP code with replay and brute-force protection, and issues a signed assertion the CDN filter enforces on every protected request. Building an equivalent requires implementing RFC 6238 correctly, secure seed storage, replay protection, brute-force lockout, session cookie signing, and CDN enforcement — this template handles all of it.

**How it deploys:** Two-component pair — both must be deployed:
- **`otp-app/`** (TypeScript + Hono, WASM) — HTTP app; handles challenge, verify, enroll, self-service activate, logout, JWKS endpoint, and health. Signs the `mfa_session` cookie (HS256) and optional ES256 proof.
- **`otp-filter/`** (Rust, proxy-wasm) — CDN Proxy-WASM app; verifies `mfa_session` on protected paths, default-deny, fail-closed.

Both components are deployed via the Gcore portal template gallery.

**Enforcement profiles:**

| Profile | Description | Origin requirement |
|---|---|---|
| **A** (default) | Filter enforces; origin receives only authenticated requests | No origin code changes |
| **B** (opt-in) | Origin verifies a one-time ES256 proof via JWKS and mints its own session | Origin implements JWKS-based proof verification |

**Security constraints:**
- `MFA_AUDIENCE` must be set on both apps when the filter is deployed; the filter fail-closes (refuses every session) if unset.
- The origin must be locked to edge-only traffic — direct origin reachability bypasses the gate entirely.
- `GCORE_API_TOKEN` has write access to every seed in the KV store; use a single-tenant, per-customer isolated KV store.
- `mfa_session` is short-lived (8h, non-sliding) and not cross-PoP revocable.
- CDN logs include the session subject (`sub`) on each authorized request; review log retention if `sub` contains PII.

**Origin integration:** This template has a corresponding integration reference. See the edge-totp integration reference for the customer-side CDN wiring contract, path rule configuration, and Profile B JWKS verification details.
