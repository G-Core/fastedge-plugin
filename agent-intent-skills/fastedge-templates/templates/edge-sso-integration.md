# Synthesis Instructions: edge-sso-integration.md

> For shared cross-referencing rules, extraction rules, and exclusions see
> [_docs-pattern-base.md](../_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/templates/edge-sso-integration.md`

## Audience
An agent helping a developer who has **already deployed** the `edge-sso` template (auth-app +
cdn-filter, from the Gcore portal) and now needs to wire it into their own origin codebase —
login buttons, a custom login page, or verifying the identity the edge hands back. The developer's
origin is an arbitrary codebase this agent has never seen; this doc is the contract, not a
tutorial for a specific stack.

## Output goal
A precise, code-adjacent reference the agent can use to write integration code confidently
without re-deriving the contract from source. Every route, JSON shape, and env var name must be
exact — a customer's origin code will call these literally.

## Required sections (in this order)

1. **What `SSO_VARIANT` means for the origin** — the three modes (gate-only / cookie / header)
   and, for each, what the origin actually receives and what it's responsible for checking
   itself. This section must include, not just gesture at:
   - The signing algorithm per variant (HS256 for gate-only/header, ES256 for cookie) — from
     `context/architecture/auth-modes.md` / `security.md`.
   - **For `cookie`**: the exact JWKS endpoint (`GET /auth/.well-known/jwks.json`, mounted only
     for the cookie variant), and that the origin verifies with a standard JWKS client (e.g.
     `createRemoteJWKSet`) — never invents its own verification approach. From
     `context/architecture/overview.md`.
   - **For `header`**: the complete, exact list of injected headers — `x-sso-user`, `x-sso-email`,
     `x-sso-name`, `x-sso-picture`, `x-sso-given-name`, `x-sso-family-name` — pulled verbatim from
     `cdn-filter/src/lib.rs` (these names exist nowhere in markdown source; the code comments are
     the only ground truth, extract them like doc comments). State the anti-spoofing contract:
     the filter clears any client-supplied `x-sso-*` header before injecting verified values, and
     the origin **must** treat an empty `x-sso-*` header as absent (the platform blanks a cleared
     header to empty rather than removing it) — from `context/architecture/security.md`.

2. **Routes table** — every route the auth-app exposes under `AUTH_PREFIX`, method, and purpose,
   verbatim from source. Note which routes are meant to be called by a browser vs. by a
   customer-built login UI (`/auth/providers`, `/auth/branding`) vs. never called directly
   (IdP callbacks).

3. **Login page customization tiers** — the three tiers (env-var branding / fully custom page via
   `LOGIN_PAGE_URL` / embedded sign-in buttons), with the static-link and dynamic-widget code
   snippets preserved verbatim (they're copy-paste integration code).

4. **`GET /auth/providers` and `GET /auth/branding` JSON contracts** — exact field names and an
   example response for each, preserved verbatim from source.

5. **Redirect validation** — `?redirect=` behavior and `SSO_ALLOWED_ORIGINS`, stated as a
   security-load-bearing constraint, not a footnote.

6. **Shared config the origin needs to know about** — which of `SSO_VARIANT`, `SESSION_SECRET`,
   `SSO_AUDIENCE`, `AUTH_PREFIX` etc. the origin needs to be aware of (vs. purely internal to the
   two FastEdge apps), cross-referencing the provider table from the catalog entry only by name.

## What to exclude
- How to deploy or configure the auth-app/cdn-filter themselves (that's the template's own
  README/`.env.example`, deployed via the Gcore portal — out of scope for an origin-integration
  doc)
- SAML-specific crypto internals (see the template's own `context/architecture/saml-flow.md` if
  ever surfaced separately — not needed for origin integration)

## Quality bar
Every route path, JSON field name, env var name, and `x-sso-*` header name must match source
verbatim — `edge-sso/context/design/integration.md`, `edge-sso/README.md`,
`edge-sso/context/architecture/{auth-modes,overview,security}.md`, and
`edge-sso/cdn-filter/src/lib.rs` for the header names specifically. Do not paraphrase route
paths, field names, or header names. A `cookie` or `header` variant integration described
without a JWKS endpoint or without the exact header list, respectively, is incomplete — treat
that as a required-content gap, not an acceptable simplification.
