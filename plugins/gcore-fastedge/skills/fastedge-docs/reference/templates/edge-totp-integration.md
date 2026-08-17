<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: daa9b068b7122b39c0962133f780adc25bb439c1
      updated: 2026-08-17
-->

# edge-totp — Origin Integration

Reference for wiring the TOTP second factor into an origin's login flow after the `edge-totp` template (otp-app + otp-filter) has been deployed from the Gcore portal.

**Scope:** origin-side code changes only. otp-app/otp-filter deployment, portal configuration, and `.env` contents are out of scope.

---

## The Three Origin-Side Changes

Adding the TOTP second factor is **three small changes** on the origin side, all in the auth layer — the rest of the site is untouched.

### 1. Split login into password-then-OTP

After the password check succeeds, instead of immediately minting the full origin session:

- Sign a **handoff ticket** = `HMAC(HANDOFF_KEY)` over `{ sub: userId, next, exp: now+TICKET_TTL }`
- Set a short-lived **`pre_mfa`** cookie/marker so the origin remembers the password step passed (bind it to `sub`)
- 303-redirect to `{AUTH_PREFIX}/challenge?t=<ticket>` (totp-app, same host via the CDN path rule)

### 2. Finish login on return to `next` — pick a profile

**Profile A (default, zero origin code):** The Rust filter enforces the edge `mfa_session` (8h) on protected paths, so any request reaching the origin has passed MFA. The origin just re-identifies its `pre_mfa` user and mints its own session — **no proof verification, no crypto.** `HANDOFF_KEY` is the only key it holds.

**Profile B (opt-in, longer sessions):** The edge hands back a one-time **ES256** proof; the origin verifies it via totp-app's **JWKS** endpoint (`createRemoteJWKSet` — public key only, can't forge), checks `sub` matches `pre_mfa`, and mints its **own revocable session** with whatever lifetime it wants (safely longer than the 8h edge session). The proof is **never in a URL** — it is delivered as a short-lived cookie.

### 3. Enroll users

No origin endpoint needed. Call `POST {AUTH_PREFIX}/enroll` (gated by `ENROLL_API_KEY`), which writes the seed to KV (via totp-app's `GCORE_API_TOKEN`); verify reads it from KV at challenge time.

Users can also self-enroll on first login via `{AUTH_PREFIX}/activate` (on by default; set `ALLOW_SELF_ENROLLMENT=false` to require admin provisioning instead).

**Recovery:** Re-provision a lost authenticator by calling `/enroll` with `force:true` behind your own identity check.

---

## Profile A vs Profile B — Decision-Relevant Framing

This choice affects real security posture, not style.

**Profile A** requires zero origin crypto. The Rust filter only verifies that *a* valid `mfa_session` exists — it does not bind that session to the origin's password identity, and it deliberately does **not** forward the user id to the origin. The origin cannot know *which* user passed MFA from the edge alone.

Do **not** add an unsigned `x-mfa-user`-style header for the origin to trust — forwarded-identity headers are a recurring source of auth-bypass CVEs (e.g. oauth2-proxy header smuggling). If you need the *edge* to assert **which** user passed MFA, use **Profile B**.

**Profile B** lets the origin verify a signed ES256 proof via JWKS and bind it to `sub`. The origin verifies via `createRemoteJWKSet` (public key only, can't forge), checks `sub` matches `pre_mfa`, and mints its own revocable session. This is the same signed-assertion pattern Cloudflare Access uses (`Cf-Access-Jwt-Assertion`), and the reason the proof is signed rather than a bare header.

**Profile B is preferable when the origin cannot be fully locked to CDN-only traffic**, because the origin independently verifies the signed proof rather than trusting that the request came through the gate.

---

## Shared Configuration

| Key | Origin uses it to… | Edge uses it to… |
| --- | --- | --- |
| `HANDOFF_KEY` (HS256) | sign the handoff ticket | verify it on `/challenge` + `/verify` |
| **JWKS** (Profile B only) | verify the one-time ES256 proof via `createRemoteJWKSet` (**public key only**) | sign the proof (`MFA_PROOF_SIGNING_KEY`) + serve `{AUTH_PREFIX}/.well-known/jwks.json` |

> **Profile A shares only `HANDOFF_KEY`** — the origin holds no verification key at all; the Rust filter enforces `mfa_session` (HS256 `MFA_SESSION_KEY`, edge-internal). Profile B adds the JWKS public-key fetch. No symmetric secret crosses to the origin on the proof path.

Both apps live on the **same CDN host** (path rule `{AUTH_PREFIX}/*` → totp-app), so the `mfa_session` cookie is first-party and host-only. Same-host is **required**: the proof and session are consumed at the edge into a host-only cookie, so there is no cross-host URL-token path.

---

## Required Deployment Precondition

**The origin must be reachable only through the CDN.** This is a hard requirement, not a suggestion.

Any edge gate — Profile A or B — is only meaningful if the origin **cannot be reached except through the CDN**. If the origin's IP is directly reachable, an attacker simply skips the edge and the `mfa_session`/filter never runs. The origin must be restricted to Gcore CDN ingress via IP allowlist, origin auth, or tunnel.

Profile B is more robust when the origin can't be fully locked down, because the origin independently verifies the signed proof rather than trusting that the request came through the gate. But neither profile substitutes for locking the origin.

---

## Recovery and Self-Service Enrollment Caveat

Self-service enrollment via `{AUTH_PREFIX}/activate` inherits the **password's trust level** — it is only as strong as the password check that preceded it. For sensitive accounts where the password alone is insufficient to authorize MFA enrollment, disable self-service (`ALLOW_SELF_ENROLLMENT=false`) and require admin provisioning via `POST {AUTH_PREFIX}/enroll` behind your own identity check.

See the threat-model reference for the full treatment of residual risk R5 before relying on self-service enrollment for sensitive accounts.

---

## See Also

- architecture/storage-and-secrets — full env/secret reference for both apps
- security/threat-model — full trust model, protections, and residual risks (including R5 on self-service enrollment)
- edge-totp README — build, test, and portal deployment steps
