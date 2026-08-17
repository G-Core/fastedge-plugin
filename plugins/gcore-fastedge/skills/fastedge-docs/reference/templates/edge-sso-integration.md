<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: daa9b068b7122b39c0962133f780adc25bb439c1
      updated: 2026-08-17
-->

# edge-sso — Origin Integration

Reference for wiring an existing origin into a deployed `edge-sso` template (auth-app + cdn-filter). This document covers what the origin receives at runtime and how to integrate login surfaces — not how to deploy or configure the two FastEdge apps themselves.

---

## 1. What `SSO_VARIANT` Means for the Origin

`SSO_VARIANT` must be set to the **same value** on both the auth-app and cdn-filter. It determines what the origin receives on authenticated requests.

| `SSO_VARIANT` | What the origin receives | What the origin must check |
|---|---|---|
| `gate-only` | Nothing — request reaches origin only if session is valid | Nothing; access control is fully handled at the edge |
| `cookie` | `sso_session` cookie containing a signed JWT with user identity | The origin may verify the JWT signature using `SESSION_PUBLIC_JWK`; the token's `aud` claim matches `SSO_AUDIENCE` |
| `header` | Signed `x-sso-*` identity headers injected by the CDN filter | The origin may trust these headers as coming from the CDN layer; headers are not present on unauthenticated requests (which never reach origin) |

In all variants, unauthenticated requests never reach the origin — the cdn-filter redirects them to the auth-app. The origin only needs active verification logic in the `cookie` variant if it wants to extract user identity from the JWT.

---

## 2. Routes Table

All routes are served under `AUTH_PREFIX` (default: `/auth`). The CDN filter bypasses `AUTH_PREFIX/**`; all other paths are gated.

| Route | Method | Caller | Purpose |
|---|---|---|---|
| `/auth/` and `/auth` | GET | Browser | Hosted login page — server-rendered, branded, provider buttons. Honours `?redirect=`. |
| `/auth/providers` | GET | Browser or custom login UI | Provider data (JSON) — the enabled provider set with login URLs. Honours `?redirect=`. |
| `/auth/branding` | GET | Custom login page | Branding config (JSON) — current `LOGIN_PAGE_*` values. |
| `/auth/login/google` | GET | Browser | Start Google OIDC flow. Honours `?redirect=`. |
| `/auth/login/github` | GET | Browser | Start GitHub OAuth flow. Honours `?redirect=`. |
| `/auth/login/microsoft` | GET | Browser | Start Microsoft OIDC flow. Honours `?redirect=`. |
| `/auth/login/facebook` | GET | Browser | Start Facebook OAuth flow. Honours `?redirect=`. |
| `/auth/login` | GET | Browser | Start SAML SSO flow. Honours `?redirect=`. |
| `/auth/logout` | GET | Browser | Sign out — clears `sso_session` cookie (`Max-Age=0`), redirects to validated `?redirect=` (defaults to `/`). Not gated by the filter. |
| `/auth/callback/<provider>` | GET | IdP (OAuth) | IdP redirect target after OAuth/OIDC — not called directly. |
| `/auth/callback` | GET | IdP (SAML) | IdP redirect target after SAML assertion — not called directly. |

`?redirect=<url>` is the post-login destination. After successful federation the auth-app sets the `sso_session` cookie and 302s to that URL. See redirect validation constraints in section 5.

The enabled provider set is resolved at runtime from `SSO_PROVIDERS` ∩ providers-whose-credentials-are-present. The hosted page and `/auth/providers` are driven by the same resolution (`selectProviders`) so they never disagree.

---

## 3. Login Page Customization Tiers

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

`LOGIN_PAGE_CSS_URL` is the deep-customization escape hatch — a `<link rel="stylesheet">` injected after built-in styles. The CSS variables `--lp-accent` and `--lp-bg` are intentional override points.

### Tier 2 — Fully custom login page (`LOGIN_PAGE_URL`)

Set `LOGIN_PAGE_URL` on the **CDN filter** to redirect unauthenticated users to a page you own instead of the built-in one. That page calls `GET /auth/providers` for login URLs and, optionally, `GET /auth/branding` for consistent branding tokens.

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

Field definitions:
- `id` — stable identifier; also the value used in `SSO_PROVIDERS`.
- `label` — human label; SAML label is overridden by `IDP_LABEL`.
- `loginUrl` — relative path including the encoded `redirect`.
- Order is stable (registry order), not allowlist order.

### `GET /auth/branding`

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

The `?redirect=` parameter is validated against `SSO_ALLOWED_ORIGINS`.

- **Relative URLs** (starting with `/`) are always permitted.
- **Off-origin absolute URLs** are silently dropped — the post-login redirect falls back to `/`.
- Set `SSO_ALLOWED_ORIGINS` to a comma-separated list of allowed origins (e.g. `https://shop.example.com`) to permit absolute redirects.

This is a security-load-bearing constraint. Any integration that passes absolute redirect URLs must set `SSO_ALLOWED_ORIGINS` on both apps or those redirects will silently fall back to `/`.

---

## 6. Shared Config the Origin Needs to Know About

These env vars and secrets are set on the FastEdge apps but have direct implications for origin integration code:

| Name | Type | Relevance to origin |
|---|---|---|
| `SSO_VARIANT` | Env var | Determines what the origin receives (nothing / JWT cookie / identity headers) — origin integration code branches on this |
| `SESSION_SECRET` | Secret | Shared signing secret; used by both apps for OAuth/SAML flow cookies and session token signing (`gate-only` / `header` variants) |
| `SESSION_SIGNING_KEY` | Secret | EC private key; signs the JWT session token in the `cookie` variant |
| `SESSION_PUBLIC_JWK` | Env var | EC public key in JWK format; origin uses this to verify the `sso_session` JWT in the `cookie` variant |
| `SSO_AUDIENCE` | Env var | Must match on both apps; cdn-filter rejects tokens whose `aud` claim doesn't match — origin can use this value to validate the `aud` claim when verifying JWTs |
| `AUTH_PREFIX` | Env var | Path prefix reserved for auth routes (default: `/auth`); all route paths above are relative to this prefix — if changed, all hard-coded paths in origin integration code must be updated accordingly |

Provider-specific OAuth credentials (`GOOGLE_CLIENT_ID`, `GITHUB_CLIENT_ID`, etc.) and SAML IdP settings (`IDP_SSO_URL`, `IDP_ENTITY_ID`, etc.) are internal to the auth-app and not needed by the origin. See the provider table in the edge-sso catalog entry for the full list of per-provider env var names.

---

## See Also

- edge-sso catalog entry (provider table, deployment overview)
- edge-sso template README (full `.env.example` for both apps, deployment steps)
- platform-overview reference (FastEdge HTTP app and CDN app concepts)
