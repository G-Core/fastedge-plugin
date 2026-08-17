<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: 87b7dc143db5e74cf0e7eb52f67484f6abc51c43
      updated: 2026-08-17
-->

# edge-sso — Origin Integration Reference

Reference for integrating your origin codebase with a deployed `edge-sso` template (auth-app + cdn-filter). Covers what the edge hands to your origin per variant, the routes your code may call, and the contracts it must satisfy.

---

## 1. What `SSO_VARIANT` Means for the Origin

`SSO_VARIANT` is set identically on both the auth-app and the cdn-filter. It controls how (or whether) the edge passes identity to your origin. Set in the Gcore portal — no code change or rebuild required.

### `gate-only`

- **Signing algorithm**: HS256 (`SESSION_SECRET` shared between auth-app and cdn-filter).
- **What the origin receives**: nothing identity-related. The filter allows or denies; your origin sees only allowed requests.
- **Origin responsibility**: none. The edge handles all access control. The session cookie is stripped before the request reaches the origin.
- **Use when**: the origin only needs to know "is this user authenticated?" — static sites, file downloads, internal tools.

### `cookie`

- **Signing algorithm**: ES256. The auth-app signs with `SESSION_SIGNING_KEY` (PKCS#8 EC private key); the public half is available via JWKS.
- **What the origin receives**: the `sso_session` cookie (name configurable via `SESSION_COOKIE`) is forwarded intact. The origin is responsible for verifying it.
- **JWKS endpoint**: `GET /auth/.well-known/jwks.json` — mounted only when `SSO_VARIANT=cookie` and `SESSION_PUBLIC_JWK` is configured. The endpoint returns only public JWK members (private key material is stripped before publication).
- **How to verify**: use a standard JWKS client (e.g. `createRemoteJWKSet` from `jose`) pointed at `GET /auth/.well-known/jwks.json`. Do not implement raw ES256 verification — use a standards-compliant JWKS library.
- **JWT payload fields**: `sub`, `iat`, `exp`, `aud`, `iss` (optional), `email`, `name`, `picture`, `given_name`, `family_name`.
- **Cookie attributes**: `HttpOnly; Secure; SameSite=Lax`. Under single-domain routing, no `Domain=` is set — same-origin.
- **Use when**: the origin already verifies stateless JWTs, or needs to read user identity from a verifiable token.

### `header`

- **Signing algorithm**: HS256 (`SESSION_SECRET`).
- **What the origin receives**: identity injected as request headers. The filter clears any client-supplied `x-sso-*` header and injects only values derived from the verified session token. The session cookie is stripped before the request reaches the origin.
- **Injected headers** (exact names):
  - `x-sso-user` — subject (`sub` claim)
  - `x-sso-email` — email claim
  - `x-sso-name` — name claim
  - `x-sso-picture` — picture claim
  - `x-sso-given-name` — given_name claim
  - `x-sso-family-name` — family_name claim
- **Anti-spoofing contract**: the filter clears any client-supplied `x-sso-*` header before injecting verified values. The FastEdge CDN platform blanks a cleared header to an empty string rather than removing it from the request. The origin **must** treat an empty `x-sso-*` header value as absent — do not trust an empty string as a valid identity claim.
- **Origin responsibility**: trust these headers unconditionally for authenticated requests; treat empty values as absent. No token verification required.
- **Use when**: the origin has server-side sessions or won't verify tokens; the origin trusts the edge layer.

---

## 2. Routes Table

All routes are served under `AUTH_PREFIX` (default: `/auth`). The table uses `/auth` as the prefix.

| Route | Method | Caller | Purpose |
|---|---|---|---|
| `/auth/` (and `/auth`) | GET | Browser | Hosted login page — server-rendered, branded, provider buttons. Honours `?redirect=`. |
| `/auth/providers` | GET | Browser or custom login UI | Provider data (JSON) — enabled provider set with login URLs. Honours `?redirect=`. |
| `/auth/branding` | GET | Custom login UI | Branding config (JSON) — current `LOGIN_PAGE_*` values for consistent styling. |
| `/auth/login/google` | GET | Browser | Start Google OIDC flow. Honours `?redirect=`. |
| `/auth/login/github` | GET | Browser | Start GitHub OAuth flow. Honours `?redirect=`. |
| `/auth/login/microsoft` | GET | Browser | Start Microsoft OIDC flow. Honours `?redirect=`. |
| `/auth/login/facebook` | GET | Browser | Start Facebook OAuth flow. Honours `?redirect=`. |
| `/auth/login` | GET | Browser | Start SAML SSO flow. Honours `?redirect=`. |
| `/auth/logout` | GET | Browser | Sign out — clears `sso_session` (`Max-Age=0`), redirects to validated `?redirect=` (defaults to `/`). Not gated by the cdn-filter. |
| `/auth/callback/<provider>` | GET | IdP only | OAuth/OIDC callback. Not called directly by customer code. |
| `/auth/callback` | POST | IdP only | SAML ACS callback. Not called directly by customer code. |
| `/auth/.well-known/jwks.json` | GET | Origin (cookie variant) | JWKS endpoint for ES256 public key. Mounted only when `SSO_VARIANT=cookie`. |

The cdn-filter bypasses all paths under `AUTH_PREFIX` — requests to `/auth/**` are never gated, preventing redirect loops.

`?redirect=<url>` is the post-login destination. After successful federation the auth-app sets the `sso_session` cookie and 302s to that URL. Relative URLs (starting with `/`) are always permitted; absolute URLs are validated against `SSO_ALLOWED_ORIGINS`.

---

## 3. Login Page Customization Tiers

### Tier 1 — Env var branding (recommended default)

The built-in hosted login page reads these env vars per-request. No code changes or custom CSS required for basic branding.

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

`LOGIN_PAGE_CSS_URL` is the deep-customization escape hatch — a `<link rel="stylesheet">` injected after built-in styles. The CSS variables `--lp-accent` and `--lp-bg` are intentional override points.

### Tier 2 — Fully custom login page (`LOGIN_PAGE_URL`)

Set `LOGIN_PAGE_URL` on the cdn-filter to redirect unauthenticated users to a page you own instead of the built-in one. That page calls `GET /auth/providers` for login URLs and, optionally, `GET /auth/branding` for consistent branding tokens.

```
LOGIN_PAGE_URL=https://shop.example.com/my-login
```

Your custom page handles the full UI; clicking a provider's button navigates to its `loginUrl` (relative, same-origin) which kicks off the standard federation flow. The default value of `LOGIN_PAGE_URL` is `/auth/` — set it only to opt out.

### Tier 3 — Embed sign-in buttons on an existing page

**Static links (simplest):** hard-code the provider routes.
```html
<a href="/auth/login/google?redirect=/account">Sign in with Google</a>
<a href="/auth/login/github?redirect=/account">Sign in with GitHub</a>
<a href="/auth/login?redirect=/account">Single Sign-On</a>
```

**Dynamic widget:** fetch `/auth/providers` and render whatever is enabled.
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

## 4. JSON Contracts

### `GET /auth/providers`

Query parameter: `?redirect=<url>` (optional) — encoded into each `loginUrl`.

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

Field semantics:
- `id` — stable identifier; matches values used in `SSO_PROVIDERS`.
- `label` — human-readable label; SAML label is overridden by `IDP_LABEL`.
- `loginUrl` — relative path including the encoded `redirect`. Safe to use as an `href` directly.
- Order is stable (registry order), not allowlist order.

The enabled provider set is resolved at runtime from `SSO_PROVIDERS` ∩ providers-whose-credentials-are-present. The hosted page and `/auth/providers` derive from the same resolution (`selectProviders`) — they never disagree.

### `GET /auth/branding`

No query parameters.

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

Returns the current `LOGIN_PAGE_*` env var values as a JSON object. Custom login pages (Tier 2) can `fetch("/auth/branding")` to auto-style themselves consistently without duplicating the env var set.

---

## 5. Redirect Validation

The `?redirect=` parameter is security-load-bearing. Validation rules:

- **Relative URLs** (starting with `/`) are always permitted.
- **Absolute URLs** are validated against `SSO_ALLOWED_ORIGINS` (comma-separated list of allowed origins, e.g. `https://shop.example.com`).
- **Off-origin absolute URLs** not in `SSO_ALLOWED_ORIGINS` are silently dropped — the post-login redirect falls back to `/`.
- **Protocol-relative and backslash bypass attempts** (e.g. `//evil.com`, `/\evil.com`) are rejected.

Set `SSO_ALLOWED_ORIGINS` whenever your post-login flow requires an absolute URL redirect. Omitting it restricts all redirects to same-origin relative paths.

This validation applies at every point a `redirect` parameter is consumed: OAuth/OIDC login initiation, SAML relay state, and logout.

---

## 6. Shared Config the Origin Needs to Know About

These settings are configured on the FastEdge apps in the Gcore portal but have direct implications for origin-side integration code:

| Config | Where set | Origin impact |
|---|---|---|
| `SSO_VARIANT` | Both apps | Determines what identity the origin receives (nothing / JWT cookie / request headers). Must drive the origin's verification approach. |
| `SESSION_SECRET` | Both apps (secret) | HS256 signing key for gate-only/header variants. Not used by the origin directly, but must be consistent between the two apps. |
| `SESSION_SIGNING_KEY` + `SESSION_PUBLIC_JWK` | Auth-app (secret + env) | EC keypair for cookie variant. The origin fetches the public key from `GET /auth/.well-known/jwks.json` — it does not need direct access to these values. |
| `SSO_AUDIENCE` | Both apps | The `aud` claim value in every issued token. Cookie-variant origins verifying the JWT themselves must validate `aud` against the expected value. |
| `AUTH_PREFIX` | Both apps | Default `/auth`. All route paths in this document are relative to this prefix. If changed, all route paths shift accordingly. |
| `SESSION_COOKIE` | Both apps | Default `sso_session`. The cookie name the cookie variant sets and the origin reads. |
| `SSO_ALLOWED_ORIGINS` | Auth-app | Controls which absolute redirect URLs are permitted. Configure to match your origin's domain if post-login redirects use absolute URLs. |
| `LOGIN_PAGE_URL` | CDN filter | Set to redirect unauthenticated users to a custom login page (Tier 2). Defaults to `AUTH_PREFIX/`. |

Provider OAuth credentials (`GOOGLE_CLIENT_ID`, `GITHUB_CLIENT_ID`, `MICROSOFT_CLIENT_ID`, `FACEBOOK_CLIENT_ID`, and SAML `IDP_*`/`SP_*` vars) are internal to the auth-app and do not affect origin integration code. See the template README and `.env.example` files for the full configuration reference.

---

## See Also

- edge-sso template README — deployment and full `.env.example` reference for both apps
- edge-sso auth-modes architecture — SSO_VARIANT axis rationale and runtime vs. build-time split
- edge-sso security architecture — token contract, signing strategy, and known limitations
- fastedge-docs platform-overview — FastEdge HTTP app and CDN app runtime model
