# Synthesis Instructions: js-runtime.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/js-runtime.md`

## Source note
The source `docs/RUNTIME_CONSTRAINTS.md` is hand-authored in the SDK repo (not produced by `generate-docs.sh`). It is already polished — preserve content faithfully. Do not invent new sections, libraries, or capabilities.

## Audience
AI agents helping developers reason about *non-API* runtime constraints — particularly when developers attempt to use Node.js libraries, crypto-heavy frameworks, or SAML/OAuth flows that may be incompatible with the WinterCG-style runtime.

## Output goal
A research and decision-support reference, **not** an API reference. Agents use this to refuse impossible requests early ("you cannot polyfill `node:crypto`") and to redirect users to viable alternatives. The actual SDK API surface (available Web APIs, supported `crypto.subtle` operations, SDK imports) lives in the SDK API reference — this doc must NOT duplicate that content.

## Required sections (in this order)

1. **Header note** — One paragraph linking to the SDK API reference for the canonical list of available APIs and the `crypto.subtle` operation matrix. Frame this doc as research/constraints, not API surface.

2. **Runtime identity** — StarlingMonkey, SpiderMonkey-based, WASI 0.2 Component Model, WinterCG-style. Explicit "not Node.js, no nodejs_compat" framing. Include the bullet list of unavailable Node built-ins (`node:crypto`, `node:fs`, etc.) and absent platform APIs (WebSocket, DOM) since these inform the polyfill discussion below — but do NOT include the available APIs list, that's SDK API territory.

3. **Why Node.js crypto polyfills fail** — preserve the four-point explanation. The sync/async impedance mismatch is the key insight an agent needs to convey to a user proposing a polyfill. Include the brief connector paragraph linking to the SDK API reference for the exact `crypto.subtle` matrix.

4. **SAML on FastEdge** — preserve all subsections:
   - Why standard SAML libraries don't work (the library/blocker table)
   - SAMLStorm CVE note
   - Viable SAML SP stack (the package/notes table)
   - XMLDSig verification steps (numbered list)
   - SAMLRequest encoding (with the `deflateRaw` snippet)

## Accuracy constraints
- **Preserve the SAML library blocker table verbatim.** Library names and root-cause attributions are research-derived and not safe to paraphrase.
- **Do not invent libraries or claim untested compatibility.** Only mention packages that appear in the source.
- **Do not insert numeric binary size limits.** The platform has no fixed limit; refer instead to general guidance.
- **Do not duplicate SDK API content.** If the doc starts looking like an API reference (listing supported algorithms, available APIs), trim — that's the SDK API reference's job.

## What to exclude
- Available Web APIs list (lives in SDK API reference)
- `crypto.subtle` algorithm matrix (lives in SDK API reference)
- Implementation details of the SDK itself (StarlingMonkey internals, JCO, ComponentizeJS)
- Recommendations for Node.js compatibility shims that are not in the source
- Marketing language

## Quality bar
The polyfill explanation and the SAML library blocker table are the highest-value sections — agents lean on them when triaging "why doesn't my library work?" questions. They must be reproduced with no algorithmic or library-name drift. The deflate-raw snippet must compile against the documented Web Compression Streams API. The header note linking to the SDK API reference must be present so agents know where to retrieve the canonical API surface.
