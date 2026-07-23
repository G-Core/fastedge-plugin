# Reference Docs Audit — Cleanup Handoff

**Status as of 2026-04-27**: source-repo and plugin-level edits drafted across multiple repos and committed locally; **awaiting PR cycle on each source repo**, then a pipeline run to regenerate the plugin reference layer, then a final cleanup pass.

This file documents what was done, what's still pending, and the exact verification steps a future agent needs to complete the audit. Delete this file once all checklist items are confirmed done.

---

## Background

April 2026 audit reshaped `plugins/gcore-fastedge/skills/fastedge-docs/reference/` along two axes:

1. **Hand-crafted vs pipeline-generated** — top-level `reference/` is now exclusively pipeline-derived (auto-updated frontmatter); `reference/platform/` is the only hand-edited area
2. **Content overlap removal** — Hono / KV / testing / common-pattern content that was redundant with source-repo docs got pushed back into source-repo `docs/` and is consumed via the pipeline

Authoring rules that came out of the audit live in `AUTHORING_GUIDELINES.md`. Read those before resuming work.

---

## What landed locally (across multiple repos, awaiting PRs)

### `FastEdge-sdk-js`
- **New docs** (hand-authored, will flow to plugin via pipeline):
  - `docs/HONO_PATTERNS.md` — Hono framework patterns
  - `docs/AUTH_PATTERNS.md` — bearer-token + HMAC JWT auth
  - `docs/PROXY_PATTERNS.md` — proxy / response transform
  - `docs/RUNTIME_CONSTRAINTS.md` — slimmed StarlingMonkey constraints + SAML guidance (no longer duplicates SDK_API content)
- **Manifest entries added** in `fastedge-plugin-source/manifest.json`: `hono-pattern`, `auth-pattern`, `proxy-pattern`, `runtime-constraints`. Existing `quickstart` entry retargeted to `quickstart-js.md`
- **`context/CONTEXT_INDEX.md`** — new "Doc verification backlog" section listing `Response.clone()` and `fetch redirect: "manual"` as items needing build-and-test before re-introduction to PROXY_PATTERNS

### `FastEdge-sdk-rust`
- **Manifest entry added**: `quickstart` source pointing at `docs/quickstart.md`, target `quickstart-rust.md`

### `proxy-wasm-sdk-as`
- **Manifest entry added**: `quickstart` source pointing at `docs/quickstart.md`, target `quickstart-as.md`

### `fastedge-plugin` (this repo)
- **`agent-intent-skills/fastedge-sdk-js/`**:
  - Renamed `quickstart.md` → `quickstart-js.md` (target file line updated)
  - New `js-runtime.md` (synthesis instructions for slimmed runtime constraints doc)
  - New `http/examples-hono-js.md`, `http/examples-auth-js.md`, `http/examples-proxy-js.md`
- **`agent-intent-skills/fastedge-sdk-rust/quickstart-rust.md`** — new
- **`agent-intent-skills/proxy-wasm-sdk-as/quickstart-as.md`** — new
- **`plugins/gcore-fastedge/skills/fastedge-docs/reference/platform/`** — created subdirectory:
  - `overview.md` (was `platform-overview.md`, with binary-size limit removed)
  - `error-codes.md` (with binary-size language softened)
  - `cdn-integration.md` (NEW — CDN resource attachment, `options.fastedge` shape, ruleset replace-not-merge, public-route disable pattern)
  - `operations.md` (NEW — 30-min `debug` logging knob)
  - `best-practices.md` (REWRITTEN — agent-quality guidance: confirmation discipline, scaffold-first, TDD loop, preconditions, observation-vs-request, ask-don't-guess; fully replaces the old Hono/KV/testing content)
- **`plugins/gcore-fastedge/skills/fastedge-docs/SKILL.md`**:
  - Reference Files list restructured (platform / SDK / examples groups)
  - Hono code snippet fixed (`event.respondWith(app.fetch(event.request))`, no `app.fire()`)
  - KV store Q&A corrected (`KvStore.open`, sync `get` returning `ArrayBuffer | null`, read-only)
  - Web APIs Q&A expanded (streams, NOT-available list, pointer to js-runtime ref)
- **`context/AUTHORING_GUIDELINES.md`** — new file, 5 plugin-authoring rules
- **`context/CONTEXT_INDEX.md`** — entry added for AUTHORING_GUIDELINES

### `FastEdge-mcp-server`
- **`context/CHANGELOG.md`** — fixed `/cdn/cdn/resources/{resource_id}` → `/cdn/resources/{resource_id}` in the access policy entry

---

## Pending — pick up here

### Step 1 — Confirm all PRs merged

Before doing anything pipeline-related, confirm these PRs are merged in their respective repos. Use `gh pr list` against each:

- [ ] `FastEdge-sdk-js` — docs additions + manifest changes + context-index update
- [ ] `FastEdge-sdk-rust` — manifest changes only
- [ ] `proxy-wasm-sdk-as` — manifest changes only
- [ ] `fastedge-plugin` — intent skills, platform/ subdirectory, SKILL.md, AUTHORING_GUIDELINES, CONTEXT_INDEX
- [ ] `FastEdge-mcp-server` — changelog path fix

If any are unmerged, stop here. The pipeline run requires all source-repo manifests in their final state.

### Step 2 — Run the auto-ref-update pipeline

Trigger the workflow:

```bash
gh workflow run sync-reference-docs.yml -R G-Core/fastedge-plugin
```

Or via repository_dispatch with event type `fastedge-ref-update`. See `.github/workflows/sync-reference-docs.yml` for the trigger surface.

### Step 3 — Verify pipeline outputs

After the workflow completes, the pipeline opens a PR per source repo with the regenerated reference files. Check each PR for:

- [ ] **No `needs-review` label** — means reviewer agent returned ACCEPT for all generated files
- [ ] **No `missing-intent-skill` label** — means every manifest entry has a matching intent file

Then verify the regenerated content includes the expected new files:

- [ ] `plugins/gcore-fastedge/skills/fastedge-docs/reference/quickstart-js.md` (replaces old `quickstart.md`)
- [ ] `plugins/gcore-fastedge/skills/fastedge-docs/reference/quickstart-rust.md` (new)
- [ ] `plugins/gcore-fastedge/skills/fastedge-docs/reference/quickstart-as.md` (new)
- [ ] `plugins/gcore-fastedge/skills/fastedge-docs/reference/js-runtime.md` (regenerated with `auto-updated: true` frontmatter, content from `RUNTIME_CONSTRAINTS.md`)
- [ ] `plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-hono-js.md` (new)
- [ ] `plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-auth-js.md` (new)
- [ ] `plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-proxy-js.md` (new)

### Step 4 — Cleanup the orphaned `quickstart.md`

The old top-level `quickstart.md` is no longer pointed at by any manifest entry — `FastEdge-sdk-js` manifest now retargets `quickstart` to `quickstart-js.md`. After the pipeline run, the file will linger as an orphan. Delete:

```bash
git rm plugins/gcore-fastedge/skills/fastedge-docs/reference/quickstart.md
```

Walk the rest of `reference/` and `reference/cdn/` and `reference/http/` looking for any files **without** `auto-updated: true` frontmatter that aren't in `platform/`. Each one is a candidate orphan — verify by tracing back to a manifest target_mapping. If nothing points at it, remove.

### Step 5 — Update `SKILL.md` reference list with the new files

Once the new pipeline outputs land, edit `plugins/gcore-fastedge/skills/fastedge-docs/SKILL.md` to list them explicitly. Currently the SKILL.md mentions the `cdn/` and `http/` subdirs in summary form — extend the SDK references and language-scoped sections to call out:

- `quickstart-js.md` / `quickstart-rust.md` / `quickstart-as.md` (replace the singular `quickstart.md` mention if still there)
- `http/examples-hono-js.md`, `http/examples-auth-js.md`, `http/examples-proxy-js.md` by name

Keep the platform / SDK / examples grouping that's already in place.

### Step 6 — Task #18 — Regenerate `SDK_API.md` with the new sections

`RUNTIME_CONSTRAINTS.md` was slimmed to remove API-surface duplication (available APIs, `crypto.subtle` matrix). That content was supposed to land in `SDK_API.md` instead.

**The generation config already has the authoritative content pre-staged** — it lives in `FastEdge-sdk-js/fastedge-plugin-source/.generation-config.md` under the `## docs/SDK_API.md` section, in a "Hand-curated content for SDK_API.md" subsection. Don't re-derive the lists; the lists are there.

Steps after the `FastEdge-sdk-js` PR merges:

1. From inside `FastEdge-sdk-js`, run:
   ```bash
   ./fastedge-plugin-source/generate-docs.sh SDK_API.md
   ```
2. PR the regenerated `docs/SDK_API.md`. Spot-check that the generator's output includes both:
   - A `## Unavailable APIs` section with `node:crypto`, `node:fs`, etc.
   - A `crypto.subtle` algorithm support matrix table inside the Web Crypto coverage
3. After merge, the next coordinator pipeline run regenerates `plugins/.../sdk-reference-js.md`. Verify the synthesis preserved both sections — if not, extend `agent-intent-skills/fastedge-sdk-js/sdk-reference-js.md` to require them, then re-run the pipeline.

If anyone *also* slimmed the generation config and you need to re-derive the lists from scratch, the canonical source is the pre-slim `js-runtime.md` content (recoverable from git history of `plugins/gcore-fastedge/skills/fastedge-docs/reference/js-runtime.md` before the April 2026 reshape) — but the pre-staged config in `.generation-config.md` should be authoritative.

---

## Context pointers

- **Why this audit happened** — reshaping `fastedge-docs/reference/` to remove overlap with source-repo content; see git log for `fastedge-plugin` April 2026 commits
- **The 5 plugin-authoring rules that came out of this audit** — `context/AUTHORING_GUIDELINES.md` (read this before doing any further reference-doc work)
- **Why the changelog fix in `FastEdge-mcp-server`** — earlier the MCP server's policy allowlist had a doubled `/cdn/cdn/...` path that didn't match the real upstream API. The CDN endpoint group was unreachable until the fix landed in a recent image. The changelog entry was rewritten to reflect the corrected path.
- **Doc verification backlog** (from `FastEdge-sdk-js/context/CONTEXT_INDEX.md`) — `Response.clone()` and `fetch(..., {redirect: "manual"})` are unverified on this runtime. If a developer asks "what's next" in `FastEdge-sdk-js`, surface those: build a small example, prove or disprove support, then either re-add to `PROXY_PATTERNS.md` or document the negative finding there.

---

## When this file can be deleted

Delete after **all** of the following are confirmed:

- [ ] All PRs in Step 1 merged
- [ ] Pipeline run produced expected outputs (Step 3 checklist)
- [ ] Orphan `quickstart.md` (and any other orphans found in Step 4) deleted
- [ ] `SKILL.md` reference list updated with new files (Step 5)
- [ ] Task #18 done — `SDK_API.md` regenerated with unavailable APIs + crypto matrix sections (Step 6)

If any of these is still pending, leave the file in place — it is the trail.
