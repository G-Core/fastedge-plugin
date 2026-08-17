<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: 87b7dc143db5e74cf0e7eb52f67484f6abc51c43
      updated: 2026-08-17
-->

# edge-sso — Origin Integration Reference

## What `SSO_VARIANT` means for the origin

`SSO_VARIANT` selects how the CDN edge delivers identity to the origin. Set the same value on both the auth-app and the cdn-filter. The origin's responsibility differs per mode.

### `gate-only`

**What the origin receives:** A plain request with no identity context. The edge has already verified the session token and allowed the request through. The session cookie (`sso_session` by default) is **stripped** before the request reaches the origin — the origin never sees the raw JWT.

**Origin responsibility:** None. Access control is fully handled at the edge. The origin only needs to serve content; it receives no user identity.

**Signing algorithm:** HS256 (HMAC-SHA256) with `SESSION_SECRET`. Verification is done only by the cdn-filter; the origin does not verify anything.

---

### `cookie`

**What the origin receives:** The `sso_session` cookie (or the value of `SESSION_COOKIE`) is **passed through** to the origin intact. The cookie contains a signed JWT the origin can verify independently.

**Origin responsibility:** Verify the JWT signature using the JWKS endpoint published by the auth-app:

- **JWKS endpoint:** `GET /auth/.well-known/jwks.json` (mounted only when `SSO_VARIANT=cookie` and `SESSION_PUBLIC_JWK` is configured)
- Use a standard JWKS client (e.g. `createRemoteJWKSet` from the `jose` library) — do not implement raw EC key verification manually.
- The origin verifies the `sso_session` cookie against this endpoint using the published public JWK.

**Signing algorithm:** ES256 (ECDSA P-256). The auth-app signs with `SESSION_SIGNING_KEY` (a PKCS#8 EC private key stored as a secret). The public half is served at the JWKS endpoint from `SESSION_PUBLIC_JWK`. The origin holds only the public key and cannot forge tokens.

**JWT payload fields available after verification:**

```
sub, iat, exp, aud, iss?, email?, name?, picture?, given_name?, family_name?
```

**Cookie attributes:** `HttpOnly; Secure; SameSite=Lax`. No `Domain=` attribute under single-domain routing.

---

### `header`

**What the origin receives:** Verified identity injected as `x-sso-*` request headers. The session cookie is **stripped** before the request reaches the origin.

**Origin responsibility:** Read identity from the following headers. Treat an **empty** `x-sso-*` header as absent — the platform blanks a cleared header to empty rather than removing it, so an empty value means the claim was not present in the verified token.

**Injected headers (exact names):**

| Header | JWT claim | Notes |
|---|---|---|
| `x-sso-user` | `sub` | Subject identifier |
| `x-sso-email` | `email` | User email address |
| `x-sso-name` | `name` | Display name |
| `x-sso-picture` | `picture` | Profile picture URL |
| `x-sso-given-name` | `given_name` | First name |
| `x-sso-family-name` | `family_name` | Last name |

**Anti-spoofing contract:** The cdn-filter clears any client-supplied `x-sso-*` header before injecting only verified values from the validated token. A client cannot smuggle a spoofed header past the filter. The origin **must** treat an empty `x-sso-*` header as absent, not as a verified empty claim.

**Signing algorithm:** HS256 (HMAC-SHA256) with `SESSION_SECRET`. Verification is done only by the cdn-filter; the origin trusts the injected headers and does not verify the JWT itself.

---

## Routes Table

All routes are mounted under `AUTH_PREFIX` (default: `/auth`). The cdn-filter bypasses all requests to `AUTH_PREFIX/**` — these routes are never gated.

| Route | Method | Caller | Purpose |
|---|---|---|---|
| `/auth/` (and `/auth`) | GET | Browser | Hosted login page — server-rendered, branded, provider buttons. Honours `?redirect=`. |
| `/auth/providers` | GET | Browser / custom login UI | Provider data (JSON) — the enabled provider set, for customer-built login UIs. Honours `?redirect=`. |
| `/auth/branding` | GET | Browser / custom login UI | Branding config (JSON) — current `LOGIN_PAGE_*` values, for custom pages wanting consistent branding. |
| `/auth/login/google` | GET | Browser | Start Google OIDC. Honours `?redirect=`. |
| `/auth/login/github` | GET | Browser | Start GitHub OAuth. Honours `?redirect=`. |
| `/auth/login/microsoft` | GET | Browser | Start Microsoft OIDC. Honours `?redirect=`. |
| `/auth/login/facebook` | GET | Browser | Start Facebook OAuth. Honours `?redirect=`. |
| `/auth/login` | GET | Browser | Start SAML SSO. Honours `?redirect=`. |
| `/auth/logout` | GET | Browser | Sign out — clears `sso_session` (`Max-Age=0`), redirects to validated `?redirect=` (defaults to `/`). Not gated by the filter. |
| `/auth/.well-known/jwks.json` | GET | Origin / JWKS client | Public JWK endpoint — cookie variant only, requires `SESSION_PUBLIC_JWK`. Serves public key members only. |
| `/auth/callback/<provider>` | GET | IdP only | OAuth/OIDC callback per provider — used by the IdP, not called directly. |
| `/auth/callback` | POST | IdP only | SAML ACS endpoint — used by the IdP, not called directly. |

`?redirect=<url>` is the post-login destination. After successful federation the auth-app sets the `sso_session` cookie and 302s to that URL.

The enabled provider set is resolved at runtime from `SSO_PROVIDERS` intersected with providers whose credentials are present. The hosted page and `/auth/providers` are driven by the same resolution and are always consistent.

---

## Login Page Customization Tiers

### Tier 1 — Env var branding (recommended default)

The built-in hosted login page reads these env vars per-request. No code changes required.

| Env var | Default | Effect |
|---|---|---|
| `LOGIN_PAGE_TITLE` | `"Sign in"` | `<title>` and `<h1>` |
| `LOGIN_PAGE_SUBTITLE` | `"Choose a sign-in method"` | Subheading below the title |
| `LOGIN_PAGE_LOGO_URL` | — | Logo image above the title |
| `LOGIN_PAGE_FAVICON_URL` | — | Tab favicon |
| `LOGIN_PAGE_ACCENT_COLOR` | `#0066cc` | Button/focus-ring color (CSS `--lp-accent`) |
| `LOGIN_PAGE_BACKGROUND_COLOR` | `#f0f2f5` | Page background (CSS `--lp-bg`) |
| `LOGIN_PAGE_CSS_URL` | — | Customer stylesheet linked last — overrides any built-in style |
| `IDP_LABEL` | `"SSO"` | Display name for the SAML provider button |
| `IDP_ICON_URL` | — | Icon URL for the SAML provider button |

`LOGIN_PAGE_CSS_URL` is the deep-customization escape hatch — a `<link rel="stylesheet">` injected after built-in styles. CSS variables `--lp-accent` and `--lp-bg` are intentional override points.

### Tier 2 — Fully custom login page (`LOGIN_PAGE_URL`)

Set `LOGIN_PAGE_URL` on the **CDN filter** to redirect unauthenticated users to a page you own instead of the built-in one. That page calls `GET /auth/providers` for login URLs and, optionally, `GET /auth/branding` for consistent branding tokens.

```
LOGIN_PAGE_URL=https://shop.example.com/my-login
```

Your custom page handles the full UI; clicking a provider's button navigates to its `loginUrl` (relative, same-origin) which kicks off the standard federation flow. The default value of `LOGIN_PAGE_URL` is `/auth/` — set it only to opt out.

### Tier 3 — Embed sign-in buttons on an existing page

**Static links (simplest):** Hard-code the provider routes.

```html
<a href="/auth/login/google?redirect=/account">Sign in with Google</a>
<a href="/auth/login/github?redirect=/account">Sign in with GitHub</a>
<a href="/auth/login?redirect=/account">Single Sign-On</a>
```

**Dynamic widget:** Fetch `/auth/providers` and render whatever is enabled.

```js
const { providers } = await fetch("/auth/providers?redirect=/account").then(r => r.json());
for (const p of providers) {
  const a = document.createElement("a");
  a.href = p.loginUrl;                  // relative, same-origin, redirect already encoded
  a.textContent = `Sign in with ${p.label}`;
  loginContainer.append(a);
}
```

Adding or removing a provider (a secret or `SSO_PROVIDERS` change in the portal) updates the widget with no code change on the customer's side.

---

## `GET /auth/providers` JSON Contract

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

**Field definitions:**

| Field | Type | Description |
|---|---|---|
| `providers` | array | Ordered list of enabled providers |
| `providers[].id` | string | Stable identifier (also the value used in `SSO_PROVIDERS`) |
| `providers[].label` | string | Human label; SAML label is overridden by `IDP_LABEL` |
| `providers[].loginUrl` | string | Relative path including the encoded `redirect` parameter |

Order is stable (registry order), not allowlist order.

---

## `GET /auth/branding` JSON Contract

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

**Field definitions:**

| Field | Type | Source env var |
|---|---|---|
| `title` | string \| null | `LOGIN_PAGE_TITLE` |
| `subtitle` | string \| null | `LOGIN_PAGE_SUBTITLE` |
| `logoUrl` | string \| null | `LOGIN_PAGE_LOGO_URL` |
| `faviconUrl` | string \| null | `LOGIN_PAGE_FAVICON_URL` |
| `accentColor` | string \| null | `LOGIN_PAGE_ACCENT_COLOR` |
| `backgroundColor` | string \| null | `LOGIN_PAGE_BACKGROUND_COLOR` |
| `cssUrl` | string \| null | `LOGIN_PAGE_CSS_URL` |

Returns current `LOGIN_PAGE_*` env var values as a JSON object. Custom login pages (Tier 2) can `fetch("/auth/branding")` to auto-style themselves consistently without duplicating the env var set.

---

## Redirect Validation

The `?redirect=` parameter is validated against `SSO_ALLOWED_ORIGINS`. Rules:

- **Relative URLs** (starting with `/`) are always permitted.
- **Off-origin absolute URLs** are silently dropped — the post-login redirect falls back to `/`.
- **Protocol-relative and backslash bypasses** (e.g. `/\evil.com`) are rejected.
- Set `SSO_ALLOWED_ORIGINS` to a comma-separated list of allowed origins (e.g. `https://shop.example.com`) to permit absolute redirects.

This is a security-load-bearing constraint. Off-origin redirects without an explicit allowlist entry are dropped, not passed through with a warning.

---

## Shared Config the Origin Needs to Know About

These env vars and secrets affect behavior that is visible to the origin or to a custom login page. All others are internal to the two FastEdge apps.

| Config | Set on | Origin relevance |
|---|---|---|
| `SSO_VARIANT` | Both apps | Determines what the origin receives (nothing / JWT cookie / identity headers). Must match on both apps. |
| `SSO_AUDIENCE` | Both apps | Required and fail-closed on both sides. Use a distinct value per deployment to isolate sessions; use the same value across deployments to share sessions deliberately. |
| `AUTH_PREFIX` | Both apps | The path prefix reserved for auth routes (default: `/auth`). Custom login pages and origin routing rules must avoid capturing this prefix. |
| `SESSION_COOKIE` | Both apps | Cookie name (default: `sso_session`). The origin (cookie variant) must read this cookie name to verify the JWT. |
| `SESSION_SECRET` | Both apps (gate-only / header) | Shared HMAC secret. Internal to the filter in gate-only/header — the origin does not verify; no origin action needed. |
| `SESSION_PUBLIC_JWK` | cdn-filter (cookie variant) | The public JWK served at `/auth/.well-known/jwks.json`. The origin uses the JWKS endpoint, not this value directly. |
| `SSO_ALLOWED_ORIGINS` | auth-app | Controls which absolute redirect targets are permitted post-login. Set to your origin's domain to allow post-login redirects back to specific pages. |
| `LOGIN_PAGE_URL` | cdn-filter | Overrides the built-in login page. Set on the filter only; the origin is unaffected but must not gate the custom page URL. |
| `CANONICAL_HOST` | auth-app | The auth-app 301-redirects requests arriving on other hosts. IdP callback/ACS URLs must match this domain. |

**Provider credentials** (`GOOGLE_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, etc.) are internal to the auth-app only — see the provider table in the template README for the full list per provider. The origin is not involved in provider credential configuration.

**See also:** edge-sso template README, auth-app `.env.example`, cdn-filter `.env.example`, architecture overview, auth-modes reference, security posture reference.
