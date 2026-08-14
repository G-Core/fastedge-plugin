# Synthesis Instructions: edge-totp-integration.md

> For shared cross-referencing rules, extraction rules, and exclusions see
> [_docs-pattern-base.md](./_docs-pattern-base.md)

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
   framing from source, don't soften it to a generic "be careful").

3. **Shared configuration table** — `HANDOFF_KEY` and JWKS, exactly which side (origin vs. edge)
   holds which key/endpoint, preserved from the source table verbatim.

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
Every env var name, route, and the HMAC/JWT shape must match `edge-totp/context/integration.md`
and `edge-totp/README.md` verbatim. Security warnings must be preserved at their original
strength — do not downgrade a "must"/"required" into a "should"/"recommended".
