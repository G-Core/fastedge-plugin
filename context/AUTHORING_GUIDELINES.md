# Plugin Authoring Guidelines

Rules for anyone — human or AI — writing or modifying reference docs, intent skills, blueprints, or pattern docs in this plugin. These complement the per-skill `CLAUDE.md` and `SKILL.md` files; they cover *how* to work with the doc surface, not *what* the docs should say.

---

## 1. Pipeline-generated docs are the source of truth

Files marked `<!-- auto-updated: true -->` and any `docs/<file>` produced by a source repo's `generate-docs.sh` from `.d.ts` / source code are pipeline-managed: they update automatically when source changes. Hand-crafted docs (`reference/platform/`, hand-authored entries in source-repo `docs/`) do not.

**Rule:** hand-crafted docs MUST NOT duplicate any content covered by a pipeline-generated doc. Pipeline coverage is the source of truth. If a hand-crafted doc needs to reference auto-generated material, link to it by descriptive topic term and let the docs skill retrieve the live pipeline output.

**Why:** hand-written copies drift the moment the SDK changes; auto-generated docs track reality.

**How to apply:** before adding content to a hand-crafted doc, scan for overlap with pipeline-generated docs in the same directory tree — look for `auto-updated: true` frontmatter, or trace the file back through `manifest.json` `target_mapping` to a generator config. If overlap exists, drop the duplicated content and either (a) extend the pipeline generation spec to cover the gap, or (b) cross-reference the pipeline doc by topic term. When in doubt, prefer extending the pipeline over expanding the hand-crafted surface.

---

## 2. Verify cross-references actually demonstrate the topic

**Rule:** open each cross-reference (`See Also`, `Related examples`, `Next steps`) and confirm it actually demonstrates the topic of the current doc. Do not list items by name, by neighbouring location, or because they happen to exist.

**Why:** listing examples that don't demonstrate the topic misleads readers. Concrete failure mode: an early draft of `FastEdge-sdk-js/docs/HONO_PATTERNS.md` listed `examples/outbound-modify-response/` and `examples/crypto-hmac-jwt/` in See Also — both are valid example apps but neither uses Hono. The references implied otherwise.

**How to apply:** when drafting a See Also list, spot-check by opening at least the entry point (`src/index.{js,ts}` / `src/lib.rs` / equivalent) of each referenced example and confirming the relevant API or pattern is used. If a related pattern lives in a different example that does NOT demonstrate the current topic, link to the **other doc** by descriptive topic term, not the unrelated example folder.

---

## 3. Ask, don't guess at APIs

When writing code patterns, examples, or docs that include API calls, do not assert *how* an API behaves, what options it accepts, or what its return type is unless verified against authoritative source.

**Rule:** before writing an API call into a doc/example/pattern, identify the source. Sources that count:
- The SDK's `.d.ts` declarations (`FastEdge-sdk-js/types/`)
- The framework's published types (e.g. `node_modules/.../*.d.ts` for third-party libraries the plugin recommends)
- An existing example in the same repo that uses the exact pattern
- Explicit user confirmation

Sources that don't count: training data, plausibility, "this is how it usually works in similar runtimes."

**Why:** confident-sounding wrong assertions ship as part of pattern docs and stay there until someone debugs them. Documented incidents:
- An early draft of `PROXY_PATTERNS.md` asserted that `Response.clone()` and `fetch(..., { redirect: "manual" })` work on the FastEdge runtime; neither was verified, both ended up removed.
- `KvStore.open()` was incorrectly documented as nullable; the actual `.d.ts` returns a non-nullable `KvStoreInstance` that throws on missing stores.

**How to apply:** before writing an API call, ask: "do I have a source for this signature/option/behaviour on *this* runtime?" If not, surface the uncertainty rather than papering over it: *"I don't have a source for X — should I check the framework types, or do you know if this works on the FastEdge runtime?"* If a behaviour cannot currently be verified, capture it in the relevant source repo's "doc verification backlog" (e.g. `FastEdge-sdk-js/context/CONTEXT_INDEX.md` "Known Issues / Future Work") rather than documenting it on a guess.

---

## 4. "Hook" terminology in CDN context

**Rule:** in this plugin's documentation, "hook" specifically means a proxy-wasm lifecycle phase (`onRequestHeaders`, `onRequestBody`, `onResponseHeaders`, `onResponseBody`) at which a CDN app is attached to a CDN resource — **not** a generic API webhook or git-style hook.

**Why:** "hook" is overloaded in software. In this project it consistently refers to the proxy-wasm lifecycle context. Misinterpreting it leads to wrong assumptions about what attaching a CDN app actually does, and bleeds into incorrect docs.

**How to apply:** when the user (or another doc) says "attach a hook to a resource" or "disable a hook on this path", interpret it as configuring which proxy-wasm phases of which CDN app run on traffic flowing through the resource (or matching a rule's path). When authoring docs, use "hook" only in this sense; if you need to refer to webhooks or other lifecycle concepts, name them explicitly.

---

## 5. CDN ruleset `fastedge` config is replace, not merge

When a CDN resource's `options.fastedge` block is overridden by a CDN rule (path-scoped) for traffic matching the rule's pattern, the rule's `fastedge` block **fully replaces** the resource's — there is no per-hook inheritance.

**Rule:** never document, suggest, or imply that a rule's `fastedge` config is additive over the resource's. Every doc, blueprint, or pattern touching CDN ruleset configuration must explicitly restate this rule when relevant.

**Why:** this is the most common source of misconfiguration in CDN ruleset edits. If a rule sets only `on_request_headers` and the resource has both `on_request_headers` and `on_response_headers` configured, then for matching paths only the rule's request-header hook fires; response-header processing is silently dropped. To kill all hooks on a path (public-route pattern), set the rule's `options.fastedge.enabled = false`.

The canonical reference doc is `plugins/gcore-fastedge/skills/fastedge-docs/reference/platform/cdn-integration.md` — worked examples and the full schema live there.

**How to apply:** when advising on path-specific overrides, restate the rule explicitly: *"the rule's fastedge block defines the **complete** hook set for matching paths; copy any resource-level hooks you want to keep into the rule."* This applies to drafting docs, blueprints, intent skills, and any direct user advice on CDN configuration.

---

## When to add a new rule here

Add a guideline to this file when:
- It's a non-obvious authoring rule that other developers / AI tools could violate without realising
- It applies across multiple files / skills / blueprints, not just one location
- The cost of getting it wrong is hard to detect after the fact (silent drift, misleading examples, wrong runtime claims)

If the rule applies only to a single skill or doc, prefer documenting it inline in that skill's `SKILL.md` or the doc itself. This file is for rules that need to survive context-switching between files.
