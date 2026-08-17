# Synthesis Instructions: edge-totp-integration.md

> For shared cross-referencing rules, extraction rules, and exclusions see
> [_docs-pattern-base.md](../_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/templates/edge-totp-integration.md`

## Audience
An agent helping a developer who has **already deployed** the `edge-totp` template (otp-app +
otp-filter, from the Gcore portal) in front of a site that already has its own password login,
and now needs to wire the TOTP second factor into that origin's login flow. The developer's
origin is an arbitrary codebase this agent has never seen; this doc is the contract.

## Output goal
A precise reference for the three origin-side code changes, with the Profile A vs. B trade-off
stated clearly enough that the agent can help the developer pick correctly for their security
posture — this is an MFA gate, a wrong choice here is a real vulnerability, not a style issue.

## Required sections (in this order)

1. **The three origin-side changes** — split login into password-then-OTP (handoff ticket +
   `pre_mfa` cookie/marker + redirect to `{AUTH_PREFIX}/challenge`), finish login on return
   (Profile A vs B), and enrollment (`POST {AUTH_PREFIX}/enroll` / self-service `/activate`).
   Preserve the handoff ticket's exact shape (`HMAC(HANDOFF_KEY)` over `{sub, next, exp}`).

2. **Profile A vs Profile B — decision-relevant framing.** State plainly: Profile A requires zero
   origin crypto but the origin cannot know *which* user passed MFA from the edge alone; Profile B
   lets the origin verify a signed proof via JWKS and bind it to `sub`. Preserve the security
   warning about not trusting an unsigned forwarded-identity header verbatim — this is the
   difference between a real MFA gate and a bypassable one (cite the header-smuggling CVE class
   framing from source, don't soften it to a generic "be careful"). For Profile B, explicitly
   instruct the origin's verification call to also check the proof's `aud` claim against
   `MFA_AUDIENCE` (from `context/architecture/storage-and-secrets.md` — `MFA_AUDIENCE` is embedded
   as `aud` in the proof by the edge, same as it is for `mfa_session`, but neither
   `context/integration.md` nor a naive reading of the JWKS-verification step mentions the origin
   needs to check it). Say this is a required check, not optional — verifying the signature alone
   without checking `aud` accepts a proof that was never meant for this deployment.

3. **Shared configuration table** — `HANDOFF_KEY` and JWKS, exactly which side (origin vs. edge)
   holds which key/endpoint, preserved from the source table verbatim, plus a `MFA_AUDIENCE` row:
   embedded as `aud` on both `mfa_session` and the Profile-B proof by the edge; the edge filter
   enforces it on `mfa_session` (Profile A) and the origin **must** enforce it on the proof
   (Profile B) — this is a shared value, not edge-internal-only, unlike `MFA_SESSION_KEY`.

4. **Required deployment precondition** — the origin must be reachable **only** through the CDN
   (IP allowlist / origin auth / tunnel); state this as a hard requirement, not a suggestion —
   without it, both profiles are bypassable by hitting the origin directly.

5. **Recovery / self-service enrollment caveat** — self-service enrollment inherits the
   password's trust level; point to it as a decision point for sensitive accounts, don't just
   mention the endpoint exists.

## What to exclude
- otp-app/otp-filter deployment or configuration internals (portal deployment, `.env.example`
  contents) — out of scope for an origin-integration doc
- Replay/rate-limiting internals (`Cache`-based, edge-internal — not something the origin
  implements or needs to know about)

## Quality bar
Every env var name, route, and the HMAC/JWT shape must match `edge-totp/context/integration.md`,
`edge-totp/README.md`, and `edge-totp/context/architecture/storage-and-secrets.md` verbatim.
Security warnings must be preserved at their original strength — do not downgrade a
"must"/"required" into a "should"/"recommended". A Profile B writeup that verifies the proof's
signature but omits the `aud`/`MFA_AUDIENCE` check is incomplete — treat that as a required-
content gap, not an acceptable simplification, the same way an `edge-sso` cookie/header writeup
without a JWKS endpoint or exact header list is incomplete.
