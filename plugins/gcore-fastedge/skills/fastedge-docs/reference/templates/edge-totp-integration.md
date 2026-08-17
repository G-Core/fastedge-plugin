<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: 87b7dc143db5e74cf0e7eb52f67484f6abc51c43
      updated: 2026-08-17
-->

# edge-totp — Origin Integration Reference

## Overview

`edge-totp` adds a TOTP (RFC 6238) second-factor step in front of a site's existing password login, deployed at the edge. The origin retains ownership of identity (password authentication); totp-app adds the challenge/verify step and hands back a signed assertion. The origin makes exactly three changes to its auth layer — the rest of the site is untouched.

**Components:**
- `otp-app` — TypeScript + Hono (WASM HTTP app): handles challenge, verify, enroll, self-service activate, logout, JWKS, health. Signs `mfa_session` (HS256) and the optional Profile-B ES256 proof.
- `otp-filter` — Rust proxy-wasm CDN enforcement filter: verifies `mfa_session` on protected paths, default-deny, fail-closed.

**Two enforcement profiles:**
- **Profile A (default):** The Rust filter enforces the edge `mfa_session` (8h) on protected paths. Zero origin crypto required.
- **Profile B (opt-in):** The edge hands back a one-time ES256 proof; the origin verifies it via JWKS and mints its own revocable session.

---

## The Three Origin-Side Changes

### 1. Split login into password-then-OTP

After the password check succeeds, instead of immediately minting the full origin session:

1. Sign a **handoff ticket** = `HMAC(HANDOFF_KEY)` over `{ sub: userId, next, exp: now + TICKET_TTL }`.
2. Set a short-lived **`pre_mfa`** cookie or marker so the origin remembers the password step passed (bind it to `sub`).
3. Issue a `303` redirect to `{AUTH_PREFIX}/challenge?t=<ticket>` (totp-app, same CDN host via the path rule).

**Handoff ticket shape (exact):**
- Algorithm: HS256 HMAC using `HANDOFF_KEY`
- Claims: `sub` (userId), `next` (post-MFA return URL), `exp` (Unix timestamp = `now + TICKET_TTL`)
- `TICKET_TTL` default: `90` seconds (short, single-use; totp-app independently requires `exp` and caps absolute age)

The ticket is passed as query param `t` in the redirect URL. `next` must be a path on the same host.

### 2. Finish login on return — pick a profile

When the user returns to `next` after passing MFA, the origin re-identifies its `pre_mfa` user and mints its own session. The mechanism differs by profile:

**Profile A (default — zero origin code):**
- The Rust filter enforces the edge `mfa_session` (HS256, edge-internal) on all protected paths. Any request that reaches the origin has already passed MFA.
- The origin simply re-identifies the `pre_mfa` user and mints its own session.
- No proof verification, no crypto. The only key the origin holds is `HANDOFF_KEY`.

**Profile B (opt-in — longer, revocable sessions):**
- After verify succeeds, totp-app delivers a one-time **ES256 proof** as a short-lived cookie (`mfa_proof`, `PROOF_TTL` default: 90s, single-use).
- The origin retrieves the proof from the cookie, verifies it via totp-app's JWKS endpoint (`{AUTH_PREFIX}/.well-known/jwks.json`) using `createRemoteJWKSet` (public key only — cannot be forged).
- **Required verification steps on the origin:**
  1. Verify the proof's ES256 signature via the JWKS endpoint.
  2. Check that `sub` in the proof matches the `sub` stored in `pre_mfa` (i.e., the password-authenticated user).
  3. **Check the `aud` claim against `MFA_AUDIENCE`.** The edge embeds `MFA_AUDIENCE` as `aud` in the proof. Verifying the signature without checking `aud` accepts a proof that was never issued for this deployment — a proof from another edge-totp instance with a different audience would pass signature verification. This check is required, not optional.
  4. Check `iss` against `MFA_ISSUER` if set on both sides.
- After successful verification, the origin mints its own revocable session with whatever lifetime it chooses (safely longer than the 8h edge session).
- The proof is **never in a URL** — it is delivered only as a cookie. Do not redirect with the proof in query params.

### 3. Enroll users

No origin endpoint is required for enrollment. Two paths:

**Admin provisioning (explicit):**
```
POST {AUTH_PREFIX}/enroll
Authorization: Bearer <ENROLL_API_KEY>
Content-Type: application/json
{ "userId": "<sub>", "force": true|false }
```
- `force: true` overwrites an existing seed (re-provision a lost authenticator).
- Call this behind your own identity check before allowing the user to set up their authenticator.

**Self-service (default, on by default):**
- If `ALLOW_SELF_ENROLLMENT=true` (default), unenrolled users are redirected to `{AUTH_PREFIX}/activate` on their first login attempt via `/challenge`.
- Users complete enrollment by scanning the QR code and confirming a code within the `ENROLL_TTL` window (default: 600s).
- Set `ALLOW_SELF_ENROLLMENT=false` to require admin provisioning — `/activate` returns 403 and `/challenge` refuses unenrolled users.

**See also:** Recovery and self-service enrollment caveat (section below).

---

## Profile A vs Profile B — Decision-Relevant Framing

**Profile A — what it proves and what it does not:**

The Rust filter enforces that *a* valid `mfa_session` exists. It does **not** bind that session to the origin's password identity, and it deliberately does **not** forward the user id to the origin. That is correct here: the origin already authenticated the password and re-identifies its `pre_mfa` user when minting its session.

**Do not add an unsigned `x-mfa-user`-style header for the origin to trust.** Forwarded-identity headers are a recurring source of auth-bypass CVEs (e.g. oauth2-proxy header smuggling). If you need the edge to assert *which* user passed MFA, use Profile B — that is what the signed proof is for.

Profile A consequence: the origin cannot know from the edge alone which specific user passed MFA. It only knows that *a* valid second factor was presented. The origin re-establishes identity from its own `pre_mfa` state.

**Profile B — when to use it:**

Use Profile B when:
- You need the origin to independently verify *which* user passed MFA (not just that someone did).
- You need revocable origin sessions with lifetimes longer than the 8h edge session.
- The origin cannot be fully locked to CDN-only traffic (Profile B is more robust here because the origin independently verifies the signed proof rather than relying entirely on the edge gate).

Profile B uses the same signed-assertion pattern as Cloudflare Access (`Cf-Access-Jwt-Assertion`). The proof is signed with an ES256 private key held only at the edge; the origin verifies with the public JWKS endpoint. The private key never leaves the edge.

**Profile B verification — required checks (all four):**
1. Signature valid (via `createRemoteJWKSet` against `{AUTH_PREFIX}/.well-known/jwks.json`)
2. `sub` matches `pre_mfa` user
3. `aud` matches `MFA_AUDIENCE`
4. `iss` matches `MFA_ISSUER` (when set on both sides)
5. Proof is within `PROOF_TTL` and single-use (totp-app enforces single-use at the edge; the origin should not re-use the proof cookie)

---

## Shared Configuration

Both sides must agree on these values. Mismatches silently break the gate.

| Key / Value | Origin uses it to… | Edge uses it to… |
|---|---|---|
| `HANDOFF_KEY` (HS256) | Sign the handoff ticket (HMAC over `{sub, next, exp}`) | Verify the ticket on `/challenge` and `/verify` |
| JWKS endpoint (Profile B only) | Verify the one-time ES256 proof via `createRemoteJWKSet` (public key only, cannot forge). URL: `{AUTH_PREFIX}/.well-known/jwks.json` on the same CDN host. | Sign the proof with `MFA_PROOF_SIGNING_KEY` (ES256 private key, edge-internal); serve the public JWK at the JWKS endpoint via `MFA_PROOF_PUBLIC_JWK` |
| `MFA_AUDIENCE` | **Profile B:** must check proof's `aud` claim against this value (required — not optional). | Embeds as `aud` in both `mfa_session` and the Profile-B proof. The Rust filter enforces it on `mfa_session` (fail-closes if unset). |

**Profile A** shares only `HANDOFF_KEY`. The origin holds no verification key for the session — the Rust filter enforces `mfa_session` (HS256 `MFA_SESSION_KEY`, edge-internal, never shared with origin).

**Profile B** adds the JWKS public-key fetch. No symmetric secret crosses to the origin on the proof path. `MFA_AUDIENCE` is a shared value (not edge-internal): both sides must use the same value (recommended: the CDN hostname, e.g. `https://app.example.com`).

Both apps live on the **same CDN host** (path rule `{AUTH_PREFIX}/*` → totp-app), so the `mfa_session` and `mfa_proof` cookies are first-party and host-only. Same-host is required: the proof and session are consumed at the edge into host-only cookies, so there is no cross-host URL-token path.

---

## Required Deployment Precondition

**The origin must be reachable only through the CDN.** This is a hard requirement, not a suggestion.

Any edge gate — Profile A or B — is only meaningful if the origin cannot be reached except through the CDN. If the origin's IP is directly reachable, an attacker simply skips the edge entirely: the `mfa_session` cookie is never checked, the Rust filter never runs, and neither profile provides any protection.

Restrict the origin to Gcore CDN ingress using at minimum one of:
- IP allowlist (Gcore CDN egress IPs only)
- Origin authentication (shared secret / mTLS)
- Tunnel (private origin not exposed to public internet)

Profile B is more robust when the origin cannot be fully locked down (the origin independently verifies the signed proof), but locking the origin is still required for both profiles. Profile B without origin lockdown is defense-in-depth, not a substitute.

---

## Recovery and Self-Service Enrollment Caveat

Self-service enrollment (`{AUTH_PREFIX}/activate`) inherits the **password's trust level** — a user who has control of a password can self-enroll a new authenticator without any additional identity verification step. For most accounts this is acceptable. For sensitive or privileged accounts, this is a meaningful risk: an attacker with a compromised password can enroll their own authenticator before the legitimate user notices.

**Decision point for sensitive accounts:** Set `ALLOW_SELF_ENROLLMENT=false` and use admin provisioning (`POST {AUTH_PREFIX}/enroll` with `force: true`) behind your own out-of-band identity check (e.g. verified email, support ticket, existing session with elevated assurance). Recovery of a lost authenticator follows the same path: call `/enroll` with `force: true` after independently verifying the user's identity.

Do not rely on self-service enrollment for accounts where a compromised password alone would be sufficient to bypass the second factor through re-enrollment.

---

## Environment Variables Reference (Origin-Relevant Subset)

These are the variables whose values the origin must share or be aware of. Full variable list is in the storage and secrets reference.

| Variable | Default | Origin relevance |
|---|---|---|
| `AUTH_PREFIX` | `/auth/totp` | Mount path. The origin redirects to `{AUTH_PREFIX}/challenge` and calls `{AUTH_PREFIX}/enroll`. Must match the CDN path rule. |
| `TICKET_TTL` | `90` | Set by the origin when signing the handoff ticket. totp-app independently validates `exp` and caps absolute age. |
| `MFA_AUDIENCE` | — | **Profile B:** origin must check proof's `aud` against this value. **Profile A:** edge filter enforces; origin awareness not required. Required when filter is deployed (filter fail-closes without it). |
| `MFA_ISSUER` | — | Optional. Validated only when set on both sides. Origin must check proof's `iss` against this value if configured. |
| `ALLOW_SELF_ENROLLMENT` | `true` | Controls whether `/activate` is accessible. Origin-side decision (see Recovery section). |

---

## See Also

- storage-and-secrets reference (full env var and secret list, KV binding, ES256 keypair generation)
- edge-totp threat model (full trust model, residual risks, Profile A/B risk framing)
- edge-totp architecture flow (why the seed is fetched at verify time, PoP-safety rationale)
- FastEdge dotenv docs (syncing `.env` secrets to deployed apps)
