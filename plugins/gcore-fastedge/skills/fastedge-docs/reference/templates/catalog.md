<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: 87b7dc143db5e74cf0e7eb52f67484f6abc51c43
      updated: 2026-08-17
-->

# FastEdge Bolt-On Templates

Before writing custom auth middleware, cookie-hardening logic, or content-transform filters, check this catalog. These templates are maintained, production-ready FastEdge apps that handle security-sensitive logic (session signing, TOTP replay protection, provider federation, cookie attribute injection) that a hand-rolled equivalent would need to implement independently and correctly. Use or adapt these directly rather than building from scratch.

## html2md — HTML-to-Markdown conversion / content transformation / Accept header negotiation

**What it solves:** Converts HTML origin responses to Markdown on demand, transparently, when the client sends `Accept: text/markdown`. No origin changes required — drop it in front of any HTML-serving origin.

**How it deploys:** CDN Proxy-WASM (single app). Deployed via the Gcore portal template gallery (template ID 110).

**Runtime variants:** None — behavior is fully determined by the incoming `Accept` header and origin `Content-Type`. No environment variable configuration required.

**Origin integration:** This template is configured entirely through the presence of the Proxy-WASM filter; no env vars or secrets are required and no origin code changes are needed.

**Filter behavior:**
- Activates only when: request `Accept` includes `text/markdown`; origin `Content-Type` includes `text/html` with charset absent or `utf-8`; full response body is available at `end_of_stream`.
- When active: adds `Convert: markdown` request header (for cache key differentiation); removes `Accept-Encoding` from request; removes `Content-Length` from response; sets response `Content-Type: text/markdown; charset=utf-8` and `Transfer-Encoding: Chunked`; adds `Vary: Convert` (merged with existing `Vary`).
- Non-HTML responses and requests without `Accept: text/markdown` pass through unchanged.
- Returns HTTP 500 if origin body is not valid UTF-8 or if HTML-to-Markdown conversion fails.

---

## harden-cookies — Cookie security hardening / Secure / HttpOnly / SameSite attribute injection

**What it solves:** Adds `Secure`, `HttpOnly`, and `SameSite=Strict` attributes to targeted `Set-Cookie` response headers at the edge, without changing the backend. Targets cookies by name or applies to all cookies via wildcard.

**How it deploys:** CDN Proxy-WASM (single app). Deployed via the Gcore portal template gallery (template ID 184).

**Runtime variants:** None — behavior is controlled entirely via environment variables on the deployed filter.

**Origin integration:** This template is configured entirely through environment variables with no origin code required.

**Configuration (environment variables):**

| Variable | Description |
|---|---|
| `COOKIE_NAME` | Name of the cookie to target. Use `*` to match every cookie. If unset, the filter does nothing. |
| `SECURE` | Add the `Secure` attribute when set to exactly `true`. |
| `HTTPONLY` | Add the `HttpOnly` attribute when set to exactly `true`. |
| `SAMESITE` | Set `SameSite=Strict` when set to exactly `true`. |

**Behavior constraints:**
- `Secure` and `HttpOnly` are added only if not already present; `SameSite=Strict` is set unconditionally, overriding any existing `SameSite` value.
- Only cookies matching `COOKIE_NAME` are modified; all other `Set-Cookie` headers pass through unchanged.
- If `COOKIE_NAME` is unset or none of `SECURE`/`HTTPONLY`/`SAMESITE` is `true`, responses pass through untouched.
- Headers are only rewritten when at least one cookie value actually changes.

---

## edge-sso — SSO / login / identity federation / Identity-Aware Proxy (Google, GitHub, Microsoft, Facebook, SAML)

**What it solves:** Adds multi-provider SSO login (Google, GitHub, Microsoft, Facebook, SAML 2.0) to any existing site without changing the backend. Acts as an Identity-Aware Proxy at the edge — unauthenticated users are redirected to authenticate; authenticated users pass through with identity forwarded in the configured mode.

**How it deploys:** Two-app pair — both must be deployed together:
- `cdn-filter/` — CDN Proxy-WASM app; sits in the CDN proxy layer and verifies session tokens on every request.
- `auth-app/` — HTTP app (TypeScript/Hono); federates to the identity provider, issues signed session tokens.

Deployed via the Gcore portal template gallery.

**Runtime variants:** `SSO_VARIANT` selects the identity-delivery mode. The same value must be set on both apps in a deployment.

| `SSO_VARIANT` | Session delivery | Origin requirement |
|---|---|---|
| `gate-only` | Allow/deny only — no identity forwarded to origin | Origin needs no user context, just access control |
| `cookie` | Signed JWT in a cookie | Origin reads user identity from a verifiable token; requires EC key pair (`SESSION_SIGNING_KEY` secret + `SESSION_PUBLIC_JWK` env var) |
| `header` | Signed `x-sso-*` identity headers injected upstream | Origin trusts headers from the CDN layer |

**Shared configuration requirements (both apps):** `SSO_VARIANT` (must match), `SESSION_SECRET` (shared signing secret, required in all variants), `SSO_AUDIENCE` (must match; filter rejects tokens with mismatched `aud`), `AUTH_PREFIX` (path prefix for auth routes, default `/auth`). Per-provider OAuth credentials and SAML IdP settings are set on the auth app only.

**Origin integration:** This template has an integration reference. For the customer-side wiring contract (CDN resource setup, path rules, trust configuration), see the edge-sso integration reference.

---

## edge-totp — TOTP MFA / two-factor authentication / OTP / RFC 6238 second factor

**What it solves:** Adds a TOTP (RFC 6238) two-factor authentication step in front of an existing site's login without changing the backend authentication flow. The site keeps its own password login; this app owns the 6-digit OTP challenge, verifies the code with replay and brute-force protection, and issues a signed assertion the origin or CDN filter enforces on every protected request.

**How it deploys:** Two-app pair — both must be deployed together:
- `otp-app/` — HTTP app (TypeScript/Hono, WASM); handles challenge, verify, enroll, activate, logout, JWKS, and health endpoints. Signs `mfa_session` cookie (HS256) and optional ES256 proof.
- `otp-filter/` — CDN Proxy-WASM app (Rust); enforces `mfa_session` on protected paths; default-deny, fail-closed.

Deployed via the Gcore portal template gallery.

**Runtime variants:** Two enforcement profiles, selected at deploy configuration time:

| Profile | Description | Origin requirement |
|---|---|---|
| **A** (default) | CDN filter enforces the `mfa_session` cookie; origin receives no MFA-specific signal | No origin code changes required |
| **B** (opt-in) | Origin verifies a one-time ES256 proof via the app's JWKS endpoint and mints its own session | Origin must fetch JWKS and validate ES256 proof; requires EC keypair generation (`gen-ec-keypair.mjs`) |

**Security constraints (agent-relevant, not exhaustive):**
- Lock the origin to edge-only traffic — the gate is bypassed if the origin is directly reachable.
- `MFA_AUDIENCE` must be set on both apps when the filter is deployed; the filter fail-closes (refuses all sessions) if it is unset.
- `GCORE_API_TOKEN` has write access to every KV seed in the store — scope it to a single-tenant, per-customer isolated KV store.
- The edge `mfa_session` is short-lived (8 hours, non-sliding) and not cross-PoP revocable.

**Origin integration:** This template has an integration reference. For the customer-side wiring contract (CDN path rules, `AUTH_PREFIX` bypass, origin trust setup, and Profile B JWKS verification), see the edge-totp integration reference.
