<!--
  auto-updated: true
  sources:
    - id: fastedge-templates
      ref: main
      commit: 87b7dc143db5e74cf0e7eb52f67484f6abc51c43
      updated: 2026-08-17
-->

# edge-totp — Origin Integration

Reference for wiring the `edge-totp` TOTP second factor into an origin's existing password login. Covers the three origin-side code changes, Profile A vs. B selection, shared configuration, and deployment preconditions. Does not cover otp-app/otp-filter deployment or edge-internal configuration.

---

## The Three Origin-Side Changes

The origin's existing auth module requires three targeted changes. Nothing outside the auth layer changes.

### 1. Split login: password-then-OTP

After the password check succeeds, instead of immediately minting the full origin session:

1. Sign a **handoff ticket** = `HMAC(HANDOFF_KEY)` over `{ sub: userId, next, exp: now + TICKET_TTL }`.
2. Set a short-lived **`pre_mfa`** cookie or server-side marker so the origin remembers the password step passed, bound to `sub`.
3. `303`-redirect to `{AUTH_PREFIX}/challenge?t=<ticket>` (totp-app, same CDN host via the path rule).

`TICKET_TTL` is set by the origin when it signs the ticket. The edge independently requires `exp` and caps absolute age. The default is `90` seconds. The ticket is single-use.

### 2. Finish login on return to `next` — choose a profile

On the redirect return to `next`, the origin must re-identify its `pre_mfa` user and mint its own session. The mechanism depends on the chosen profile:

**Profile A (default — zero origin crypto):**
The Rust filter (`otp-filter`) enforces the edge `mfa_session` cookie (8h absolute, non-sliding) on all protected paths. Any request that reaches the origin has already passed MFA enforcement at the edge. The origin re-identifies its `pre_mfa` user and mints its own session. No proof verification, no cryptographic operations required. `HANDOFF_KEY` is the only secret the origin holds.

**Profile B (opt-in — signed proof, longer sessions):**
After TOTP verification, the edge delivers a one-time **ES256** proof as a short-lived cookie (`mfa_proof`, default TTL `90`s). The origin:
1. Reads the proof from the `mfa_proof` cookie (never from a URL).
2. Fetches the edge's public key via `createRemoteJWKSet` from `{AUTH_PREFIX}/.well-known/jwks.json` (public key only — cannot forge).
3. Verifies the ES256 signature.
4. **Checks the proof's `aud` claim matches `MFA_AUDIENCE`.** This is a required check, not optional. Verifying the signature alone without checking `aud` accepts a proof that was never meant for this deployment — a proof from a different edge deployment would pass signature verification but carry the wrong audience.
5. Checks that `sub` in the proof matches the `pre_mfa` user.
6. Mints its own revocable session with whatever lifetime the origin wants — safely longer than the 8h edge session.

The proof is never in a URL. It is delivered exclusively as a short-lived cookie. The proof is single-use.

### 3. Enroll users

No custom origin endpoint is required for enrollment.

**Admin provisioning:** `POST {AUTH_PREFIX}/enroll` (gated by `ENROLL_API_KEY`) writes the seed to KV via `GCORE_API_TOKEN`. Call with `force: true` to re-provision a lost authenticator behind your own identity check.

**Self-service enrollment:** On first login, unenrolled users are directed to `{AUTH_PREFIX}/activate` (enabled by default; set `ALLOW_SELF_ENROLLMENT=false` to disable — `/activate` returns `403` and `/challenge` refuses unenrolled users). Self-service enrollment requires admin provisioning to be disabled for sensitive accounts — see the recovery caveat below.

---

## Profile A vs. Profile B — Decision-Relevant Framing

This is a security architecture decision, not a preference. A wrong choice here is a real vulnerability, not a style issue.

| Criterion | Profile A | Profile B |
| --- | --- | --- |
| Origin crypto required | None | ES256 verification via JWKS |
| Sessions the origin can issue | Must match or be shorter than 8h edge session | Any lifetime (origin owns session fully) |
| Origin knows *which* user passed MFA | No — only that *a* valid `mfa_session` exists | Yes — `sub` is in the signed proof |
| Robustness if origin is partially reachable | Lower — edge enforcement must be the only gate | Higher — origin independently verifies the signed proof |
| Required origin secrets | `HANDOFF_KEY` | `HANDOFF_KEY` + JWKS fetch |

**Critical security constraint on Profile A — do not add a forwarded-identity header:**

In Profile A the Rust filter verifies only that *a* valid `mfa_session` exists — it deliberately does not bind that session to the origin's password identity and does not forward the user id to the origin. This is correct: the origin already authenticated the password and re-identifies its `pre_mfa` user when minting its own session.

Do **not** add an unsigned `x-mfa-user`-style header for the origin to trust. Forwarded-identity headers are a recurring source of auth-bypass CVEs (e.g. oauth2-proxy header smuggling). If the origin needs to know *which* user passed MFA from the edge assertion, use **Profile B**: the ES256 proof carries `sub`, the origin verifies it via JWKS and checks it matches `pre_mfa`. This is the same signed-assertion pattern Cloudflare Access uses (`Cf-Access-Jwt-Assertion`), and the reason the proof is signed rather than a bare header.

**Profile B `aud` check is mandatory:**

When verifying the ES256 proof in Profile B, the origin must check the `aud` claim against `MFA_AUDIENCE`. The edge embeds `MFA_AUDIENCE` as `aud` in both `mfa_session` and the proof. The edge filter enforces `aud` on `mfa_session` (Profile A). In Profile B, the origin is responsible for enforcing it on the proof. A deployment that verifies the signature but skips the `aud` check accepts any proof signed by the same keypair — including proofs from other deployments sharing a key. Set `MFA_AUDIENCE` to the CDN hostname (e.g. `https://app.example.com`) on both the edge app and your origin verification logic.

---

## Shared Configuration

| Key | Origin uses it to… | Edge uses it to… |
| --- | --- | --- |
| `HANDOFF_KEY` (HS256) | Sign the handoff ticket | Verify it on `/challenge` and `/verify` |
| **JWKS** (Profile B only) | Verify the one-time ES256 proof via `createRemoteJWKSet` (public key only — cannot forge) | Sign the proof (`MFA_PROOF_SIGNING_KEY`) and serve `{AUTH_PREFIX}/.well-known/jwks.json` |
| `MFA_AUDIENCE` | **Must** enforce as `aud` claim when verifying the Profile-B proof | Embeds as `aud` in `mfa_session` (enforced by the Rust filter) and the Profile-B proof |

**Profile A shares only `HANDOFF_KEY`.** The origin holds no verification key for the session. The Rust filter enforces `mfa_session` (signed with `MFA_SESSION_KEY`, which is edge-internal — the origin never holds this). Profile B adds the JWKS public-key fetch. No symmetric secret crosses to the origin on the proof path.

Both apps live on the **same CDN host** (path rule `{AUTH_PREFIX}/*` → totp-app). Same-host is **required**: the proof and session are consumed at the edge into a host-only cookie with no `Domain` attribute, so there is no cross-host URL-token path.

---

## Required Deployment Precondition

**The origin must be reachable only through the CDN.** This is a hard requirement for both profiles, not a recommendation.

Any edge gate — Profile A or B — is meaningless if the origin's IP is directly reachable. An attacker who can reach the origin directly skips the CDN entirely; the `mfa_session` cookie and `otp-filter` never run.

Restrict the origin to Gcore CDN ingress using at minimum one of: IP allowlist, origin authentication, or a private tunnel.

Profile B provides a stronger guarantee here — the origin independently verifies the signed proof rather than relying solely on the request having passed through the edge gate. It is the preferred profile when the origin cannot be fully locked down. However, it does not eliminate this requirement — it reduces the blast radius of a partial bypass.

---

## Recovery and Self-Service Enrollment Caveat

**Self-service enrollment (`{AUTH_PREFIX}/activate`) inherits the trust level of the password login.** If an attacker compromises a user's password, they can also complete self-enrollment, defeating the second factor entirely.

For sensitive accounts or deployments where password compromise is a significant threat model, set `ALLOW_SELF_ENROLLMENT=false` and require admin provisioning via `POST {AUTH_PREFIX}/enroll` (gated by `ENROLL_API_KEY`). This means a compromised password alone is insufficient to enroll a new authenticator — an operator must perform explicit re-provisioning behind a separate identity check.

Recovery for a lost authenticator: call `POST {AUTH_PREFIX}/enroll` with `force: true`. This overwrites the existing seed. Gate this call behind your own identity verification — the endpoint itself is gated only by `ENROLL_API_KEY`, which is a shared API key, not per-user auth.

---

## See Also

- edge-totp storage and secrets reference (storage model, KV binding, full env var and secret list)
- edge-totp threat model (full trust boundaries, residual risks, R4 KV token scope, R5 self-enrollment)
- edge-totp architecture flow (why the seed is fetched at verify time, Cache vs. KV)
- FastEdge dotenv sync (manage skill — syncing `.env` files to deployed apps)
- Profile B keypair generation: `node otp-app/scripts/gen-ec-keypair.mjs` (add `--dotenv` for `.env`-ready output)
