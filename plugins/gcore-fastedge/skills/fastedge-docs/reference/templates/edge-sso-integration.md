<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: daa9b068b7122b39c0962133f780adc25bb439c1
      updated: 2026-08-14
-->

# edge-sso — Origin Integration

## Overview

`edge-sso` is a bolt-on Identity-Aware Proxy for Gcore FastEdge. Adds SSO (Google, GitHub, Microsoft, Facebook, SAML) to any existing site without modifying the backend. Configured per deployment via `SSO_VARIANT`.

## Architecture

Two FastEdge apps work together per deployment:

1. **CDN filter** (`cdn-filter/`) — Proxy-WASM, Rust. Sits in the CDN proxy layer. Verifies session token on every request. Redirects unauthenticated users to the auth app.
2. **Auth app** (`auth-app/`) — HTTP app, TypeScript/Hono. Federates to the identity provider, issues a signed session token, sets it on the client.

```
User → CDN resource (filter checks session token)
              ↓ no valid token
       Auth app /auth/login → Identity Provider
                                   ↓ (user authenticates)
       Auth app /auth/callback ← IdP response
              ↓ (validates, issues signed token)
       Back to CDN resource (token set) → origin
```

**Deploy structure:**

```
edge-sso/
├── auth-app/     ← deploy as HTTP App
└── cdn-filter/   ← deploy as CDN App (Proxy-WASM)
```

## Variants

`SSO_VARIANT` selects identity delivery mode. Must be set to the same value on both apps.

| `SSO_VARIANT` | Session delivery | Use when |
|---|---|---|
| `gate-only` | Allow/deny only — no identity forwarded | Origin needs no user context, just access control |
| `cookie` | Signed JWT in a cookie the origin can verify | Origin reads user identity from a verifiable token |
| `header` | Signed `x-sso-*` identity headers injected upstream | Origin trusts a header from the CDN layer |

## Shared Configuration

Required across both apps in a deployment:

| Variable | Type | Required | Description |
|---|---|---|---|
| `SSO_VARIANT` | env var | Yes | Must match on both apps. Selects identity-delivery mode. |
| `SESSION_SECRET` | secret | Yes | Shared signing secret. Required in every variant for OAuth/SAML flow cookies; also signs the session token in gate-only/header variants. |
| `SESSION_SIGNING_KEY` | secret | cookie variant | EC private key for signing session tokens. |
| `SESSION_PUBLIC_JWK` | env var | cookie variant | EC public key for verifying session tokens. |
| `SSO_AUDIENCE` | env var | Yes | Must match on both apps. CDN filter rejects tokens whose `aud` claim does not match. |
| `AUTH_PREFIX` | env var | No | Path prefix reserved for auth routes. Default: `/auth`. |

See each app's `.env.example` for the full variable list including per-provider OAuth credentials and SAML IdP settings.

## Providers

| Provider | Protocol | Auth-app env vars |
|---|---|---|
| Google | OAuth 2.0 | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI` |
| GitHub | OAuth 2.0 | `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `GITHUB_REDIRECT_URI` |
| Microsoft | OAuth 2.0 / OIDC | `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET`, `MICROSOFT_REDIRECT_URI` |
| Facebook | OAuth 2.0 | `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`, `FACEBOOK_REDIRECT_URI` |
| SAML | SAML 2.0 | `IDP_SSO_URL`, `IDP_ENTITY_ID`, `IDP_CERT`, `SP_ENTITY_ID`, `SP_ACS_URL` |

The enabled provider set is resolved at runtime: `SSO_PROVIDERS` ∩ providers-whose-credentials-are-present. The hosted login page and `/auth/providers` endpoint are driven by the same `selectProviders` resolution and are always consistent.

## Auth App HTTP Surface

Under single-domain routing, the CDN routes `/auth/**` to the auth app as an origin — all routes are on the customer's own domain. The CDN filter bypasses `/auth/**`; all other paths are gated.

| Route | Method | Purpose |
|---|---|---|
| `/auth/` (and `/auth`) | GET | Hosted login page — server-rendered, branded, provider buttons. Accepts `?redirect=`. |
| `/auth/providers` | GET | Provider data (JSON) — enabled provider set with login URLs. Accepts `?redirect=`. |
| `/auth/branding` | GET | Branding config (JSON) — current `LOGIN_PAGE_*` env var values. |
| `/auth/login/google` | GET | Start Google OIDC flow. Accepts `?redirect=`. |
| `/auth/login/github` | GET | Start GitHub OAuth flow. Accepts `?redirect=`. |
| `/auth/login/microsoft` | GET | Start Microsoft OIDC flow. Accepts `?redirect=`. |
| `/auth/login/facebook` | GET | Start Facebook OAuth flow. Accepts `?redirect=`. |
| `/auth/login` | GET | Start SAML SSO flow. Accepts `?redirect=`. |
| `/auth/logout` | GET | Sign out — clears `sso_session` cookie (`Max-Age=0`), redirects to validated `?redirect=` (defaults to `/`). Not gated by the filter. |
| `/auth/callback/<provider>` | GET | OAuth IdP callback (used by IdP, not called directly). |
| `/auth/callback` | GET | SAML IdP callback (used by IdP, not called directly). |

`?redirect=<url>` — post-login destination. After successful federation, auth app sets the `sso_session` cookie and issues a 302 redirect to that URL.

## `GET /auth/providers` Response Contract

```jsonc
// GET /auth/providers?redirect=/cart
{
  "providers": [
    { "id": "google", "label": "Google", "loginUrl": "/auth/login/google?redirect=%2Fcart" },
    { "id": "github", "label": "GitHub", "loginUrl": "/auth/login/github?redirect=%2Fcart" },
    { "id": "saml",   "label": "SSO",    "loginUrl": "/auth/login?redirect=%2Fcart" }
  ]
}
```

**Fields:**

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable provider identifier. Matches `SSO_PROVIDERS` allowlist values. |
| `label` | string | Human-readable label. SAML label is overridden by `IDP_LABEL` env var. |
| `loginUrl` | string | Relative path including encoded `redirect` parameter. |

Order is stable (registry order), not dependent on allowlist order.

## `GET /auth/branding` Response Contract

```jsonc
{
  "title": "Sign in",
  "subtitle": "Choose a sign-in method",
  "logoUrl": "https://cdn.example.com/logo.png",
  "faviconUrl": null,
  "accentColor": "#e00",
  "backgroundColor": "#f0f2f5",
  "cssUrl": null
}
```

Returns the current `LOGIN_PAGE_*` env var values as a JSON object. Custom login pages can fetch `/auth/branding` to auto-style themselves consistently without duplicating env var configuration.

## Login Page Customization

Three tiers:

### Tier 1 — Env var branding (default)

Built-in hosted login page reads these env vars per-request. No code changes required.

| Env var | Default | Effect |
|---|---|---|
| `LOGIN_PAGE_TITLE` | `"Sign in"` | `<title>` and `<h1>` text |
| `LOGIN_PAGE_SUBTITLE` | `"Choose a sign-in method"` | Subheading below title |
| `LOGIN_PAGE_LOGO_URL` | — | Logo image above title |
| `LOGIN_PAGE_FAVICON_URL` | — | Tab favicon |
| `LOGIN_PAGE_ACCENT_COLOR` | `#0066cc` | Button/focus-ring color (CSS `--lp-accent`) |
| `LOGIN_PAGE_BACKGROUND_COLOR` | `#f0f2f5` | Page background (CSS `--lp-bg`) |
| `LOGIN_PAGE_CSS_URL` | — | Customer stylesheet linked last — overrides any built-in style |
| `IDP_LABEL` | `"SSO"` | Display name for the SAML provider button |
| `IDP_ICON_URL` | — | Icon URL for the SAML provider button |

`LOGIN_PAGE_CSS_URL` injects a `<link rel="stylesheet">` after built-in styles. CSS variables `--lp-accent` and `--lp-bg` are intentional override points.

### Tier 2 — Fully custom login page

Set `LOGIN_PAGE_URL` on the **CDN filter** to redirect unauthenticated users to a page you own instead of the built-in hosted page. Default value is `/auth/`.

```
LOGIN_PAGE_URL=https://shop.example.com/my-login
```

That page calls `GET /auth/providers` for login URLs and, optionally, `GET /auth/branding` for branding tokens. Clicking a provider's `loginUrl` navigates to the standard federation flow.

### Tier 3 — Embed sign-in buttons on existing page

**Static links:**
```html
<a href="/auth/login/google?redirect=/account">Sign in with Google</a>
<a href="/auth/login/github?redirect=/account">Sign in with GitHub</a>
<a href="/auth/login?redirect=/account">Single Sign-On</a>
```

**Dynamic widget (fetches enabled providers at runtime):**
```js
const { providers } = await fetch("/auth/providers?redirect=/account").then(r => r.json());
for (const p of providers) {
  const a = document.createElement("a");
  a.href = p.loginUrl;  // relative, same-origin, redirect already encoded
  a.textContent = `Sign in with ${p.label}`;
  loginContainer.append(a);
}
```

Adding or removing a provider (credential or `SSO_PROVIDERS` change) updates the widget automatically with no code change on the customer's side.

## Security — `?redirect=` Validation

The `redirect` parameter is validated against `SSO_ALLOWED_ORIGINS`.

- Relative URLs (starting with `/`) are always permitted.
- Off-origin absolute URLs are silently dropped — post-login redirect falls back to `/`.
- Set `SSO_ALLOWED_ORIGINS` to a comma-separated list of allowed origins to permit absolute redirects.

```
SSO_ALLOWED_ORIGINS=https://shop.example.com
```

## See Also

- edge-sso architecture overview
- edge-sso CDN filter reference
- edge-sso auth app environment variable reference
- FastEdge HTTP app deployment reference
- FastEdge CDN app (Proxy-WASM) deployment reference
