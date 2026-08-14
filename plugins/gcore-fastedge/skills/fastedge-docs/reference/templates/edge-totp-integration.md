<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: daa9b068b7122b39c0962133f780adc25bb439c1
      updated: 2026-08-14
-->

# edge-totp — Origin Integration

## Overview

`edge-totp` adds a TOTP (RFC 6238) two-factor step in front of a website's existing login, deployed at the edge on Gcore FastEdge. The site keeps its own password login. The edge hosts the 6-digit challenge, verifies the code (with replay and brute-force protection), and hands back a signed assertion the origin trusts.

## Components

| Component | Language | Role |
| --- | --- | --- |
| `otp-app/` | TypeScript + Hono (WASM) | HTTP app: challenge, verify, enroll, self-service activate, logout, JWKS, health. Signs `mfa_session` cookie (HS256) and optional ES256 proof. |
| `otp-filter/` | Rust (proxy-wasm) | CDN enforcement filter: verifies `mfa_session` on protected paths, default-deny and fail-closed. |

## Enforcement Profiles

Two enforcement profiles are available:

- **Profile A (default)** — The Rust filter enforces at the edge; zero origin code required. Any request reaching the origin has passed MFA. The origin re-identifies its `pre_mfa` user and mints its own session. Only `HANDOFF_KEY` is shared with the origin.
- **Profile B (opt-in)** — The edge hands back a one-time ES256 proof. The origin verifies it via totp-app's JWKS endpoint (`createRemoteJWKSet` — public key only, cannot forge), checks `sub` matches `pre_mfa`, and mints its own revocable session with any lifetime (safely longer than the 8h edge session).

## Origin Integration — Three Required Changes

Adding the TOTP second factor requires three changes in the origin's auth layer only. The rest of the site is untouched.

### 1. Split login into password-then-OTP

After password check succeeds, instead of immediately minting the full origin session:

- Sign a **handoff ticket** = `HMAC(HANDOFF_KEY)` over `{ sub: userId, next, exp: now+TICKET_TTL }`
- Set a short-lived `pre_mfa` cookie/marker bound to `sub` so the origin remembers the password step passed
- `303`-redirect to `{AUTH_PREFIX}/challenge?t=<ticket>` (totp-app, same host via CDN path rule)

### 2. Finish login on return to `next`

- **Profile A:** The Rust filter enforces the edge `mfa_session` (8h) on protected paths. The origin re-identifies its `pre_mfa` user and mints its own session. No proof verification, no crypto.
- **Profile B:** The edge delivers a one-time ES256 proof as a short-lived cookie (never in a URL). The origin verifies it via totp-app's JWKS endpoint, checks `sub` matches `pre_mfa`, and mints its own revocable session.

### 3. Enroll users

No origin endpoint is needed. Call `POST {AUTH_PREFIX}/enroll` (gated by `ENROLL_API_KEY`), which writes the seed to KV via totp-app's `GCORE_API_TOKEN`. Verify reads it from KV at challenge time.

Users can also self-enroll on first login via `{AUTH_PREFIX}/activate` (enabled by default; set `ALLOW_SELF_ENROLLMENT=false` to require admin provisioning instead).

**Recovery:** Re-provision a lost authenticator by calling `/enroll` with `force: true` behind your own identity check. Self-service enrollment inherits the password's trust level.

## Shared Configuration (Origin ↔ Edge)

| Key | Origin uses it to… | Edge uses it to… |
| --- | --- | --- |
| `HANDOFF_KEY` (HS256) | Sign the handoff ticket | Verify it on `/challenge` + `/verify` |
| **JWKS** (Profile B only) | Verify the one-time ES256 proof via `createRemoteJWKSet` (public key only) | Sign the proof (`MFA_PROOF_SIGNING_KEY`) + serve `{AUTH_PREFIX}/.well-known/jwks.json` |

Profile A shares only `HANDOFF_KEY`. Profile B adds the JWKS public-key fetch. No symmetric secret crosses to the origin on the proof path.

Both apps live on the same CDN host (path rule `{AUTH_PREFIX}/*` → totp-app), so the `mfa_session` cookie is first-party and host-only. Same-host is required — the proof and session are consumed at the edge into a host-only cookie, so there is no cross-host URL-token path.

## Trust Boundary

The edge proves "a second factor succeeded", not "this specific request is user X."

- **Identity stays the origin's job.** In Profile A, the Rust filter only verifies that a valid `mfa_session` exists — it does not bind that session to the origin's password identity and does not forward user id to the origin. Do not add an unsigned `x-mfa-user`-style header for the origin to trust — forwarded-identity headers are a recurring source of auth-bypass CVEs. If the edge must assert which user passed MFA, use Profile B: the ES256 proof carries `sub`, and the origin verifies it via JWKS.
- **Lock the origin to edge-only traffic (required).** Any edge gate is only meaningful if the origin cannot be reached except through the CDN. Customers must restrict the origin to Gcore CDN ingress (IP allowlist / origin auth / tunnel). Profile B is more robust when the origin cannot be fully locked down because the origin independently verifies the signed proof rather than trusting the request path.

## Security Requirements

- **Lock the origin to edge-only traffic.** An edge gate is meaningless if the origin is directly reachable — an attacker just skips the CDN.
- **Set `MFA_AUDIENCE`** on both apps when the filter is deployed. The filter fail-closes (refuses every session) if it is unset.
- **`GCORE_API_TOKEN` has write access to every seed in the store.** Reads via the KV REST API never return a seed in the clear — only the app's own `fastedge::kv` binding can, at verify time. But the token can overwrite any user's seed. Use a single-tenant, per-customer isolated KV store and scope `GCORE_API_TOKEN` to that one store.
- **The edge `mfa_session` is short-lived (8h, non-sliding) and not cross-PoP revocable.** Understand the accepted residual risks before relying on it.
- **CDN logs include user identity.** The filter logs the session subject (`sub`) and request path on each authorized request. If `sub` contains PII, review CDN log retention policy.

## Build

From the repo root:

```bash
pnpm install
pnpm build        # build both wasm binaries into ./wasm
pnpm test         # run TS unit tests + Rust filter tests
```

Per-component scripts: `pnpm build:app` / `pnpm test:app` (otp-app), `pnpm build:filter` / `pnpm test:filter` (otp-filter).

## Configuration

Copy `otp-app/.env.example` and `otp-filter/.env.example` to `.env` and fill in real values (`.env` is git-ignored). For Profile B, generate the ES256 keypair with `node otp-app/scripts/gen-ec-keypair.mjs`.

Full env/secret reference is in `storage-and-secrets` (architecture context).

## Deploy

Upload the compiled binaries to the Gcore portal under **FastEdge → Templates**:

- `wasm/totp-app.wasm` — as an **HTTP App** template
- `wasm/totp-filter.wasm` — as a **Proxy-WASM** template

Set the environment variables and secrets from your `.env` files on each template.

**CDN wiring:**
- Attach `otp-app` as a CDN origin on the `{AUTH_PREFIX}/*` path rule of the customer's CDN resource.
- Attach `otp-filter` as the CDN proxy app in front of the protected paths (bypassing `{AUTH_PREFIX}` + `/health`).

## See Also

- storage-and-secrets (architecture context) — full env/secret variable reference for both apps
- threat-model (security context) — full trust model, protections, and residual risks
- integration context — customer-side CDN wiring detail
