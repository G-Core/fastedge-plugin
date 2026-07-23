# Next Priorities — fastedge-plugin

**Status as of 2026-05-20**: forward queue trimmed after the 2026-05-20 session closed out the Codex CI workflow (#3) and the Codex skills determinism work (#4 — alignment with Claude spec + Worked Examples sections + `live-test` port). Distribution architecture session on the same day added #4 (reference-docs artifact pipeline) — see `context/PLUGIN_DISTRIBUTION.md` and `context/REFERENCE_ARTIFACT_PIPELINE.md`. **#4 done (2026-05-20)**: Tasks 1–7 implemented; Task 8 (MCP server consumer) is a cross-team handoff. A future agent picks up remaining items; treat each as self-contained. Delete this file once all remaining items are confirmed done (or migrate residuals into a more permanent doc like `TDD_ROADMAP.md` or `MCP_INTEGRATION.md`).

---

## 1. Run sync pipeline post-merge for proxy-wasm-sdk-as + FastEdge-sdk-js

**Why**: the intent skills + manifest patches landed earlier are only useful once the pipeline regenerates the reference layer from them.

**Status**: externally blocked. Two source-repo branches must merge first:
- `proxy-wasm-sdk-as/feature/extended-examples` → `master` (17 new AS CDN examples)
- `FastEdge-sdk-js/live-test-plugin` → `main` (4 new docs + extended examples + manifest expansion)

**When unblocked**:
1. Trigger the sync workflow via `workflow_dispatch` (`.github/workflows/sync-reference-docs.yml`), or wait for a source-repo release dispatch.
2. Review generated reference-doc PRs in `fastedge-plugin`. Watch the two PR labels:
   - `needs-review` (red-orange) — reviewer agent rejected, investigate before merging.
   - `missing-intent-skill` (yellow-green) — should **not** appear; if it does, an intent skill regressed or a new manifest entry slipped in.
3. Merge approved PRs to `feature/cdn-app-live-testing` (or whichever branch the pipeline targets — confirm in workflow).
4. End-to-end smoke: scaffold a project via the new `react-with-hono-server-blueprint` and `static-assets-blueprint`. Confirm `npm install && npm run build` produces a working WASM in each case. The static-assets one needs the user to populate `./images/` themselves (PNG binaries deliberately not in manifest — see Build Notes in the generated blueprint).

**Files to read first**: `context/REFERENCE_MATERIAL.md`, `scripts/sync/process-repos.sh`, `agent-intent-skills/fastedge-sdk-js/http/react-with-hono-server-ts.md` (background on Option B expanded scope).

---

## 2. Close out REFERENCE_DOCS_AUDIT_HANDOFF.md

**Why**: the April 2026 audit reshuffled `reference/` along hand-crafted vs pipeline-generated lines. The handoff doc lists remaining cleanup that depends on the pipeline run in #1.

**Status**: blocked by #1.

**Steps**:
1. Verify orphan reference files removed from `plugins/gcore-fastedge/skills/fastedge-docs/reference/` (pre-audit hand-crafted ones now superseded by pipeline output).
2. Check `plugins/gcore-fastedge/skills/fastedge-docs/SKILL.md` Reference Files list matches what's on disk.
3. Confirm `sdk-reference-{js,rust,as}.md` show the extended/current API surface (SDK_API extension was an audit item).
4. Regenerate and commit `docs-index.json` if not done by the pipeline.
5. **Delete `context/REFERENCE_DOCS_AUDIT_HANDOFF.md`** once all checklist items in it are confirmed done.

**Files to read first**: `context/REFERENCE_DOCS_AUDIT_HANDOFF.md` (the full checklist), `context/AUTHORING_GUIDELINES.md`.

---

## 3. List FastEdge MCP server on third-party MCP directories

**Why**: The MCP server is architecturally client-agnostic — `ghcr.io/g-core/fastedge-mcp-server:latest` plus a `.mcp.json` config exposes the `fastedge-docs`, `build-wasm`, `upload-binary`, etc. tools to **any** MCP-capable client (Cursor, Cline, Continue, Zed, custom clients). But discoverability today is centered on Claude Code / Codex / FastEdge VSCode extension. Cursor / Cline / etc. users have no easy way to find it.

**Status**: ready to start. Cross-team coordination — primarily a `FastEdge-mcp-server` concern, listed here for visibility because it affects the plugin's "reference material reach" story.

**Candidate directories**:
- modelcontextprotocol.io's official server catalog
- Smithery (smithery.ai)
- Cursor's MCP directory
- Cline's marketplace
- Continue.dev plugin directory
- mcp-get registry

**Steps**:
1. Confirm with FastEdge-mcp-server team that public listing is desired and approve the listing content.
2. Draft a canonical one-paragraph listing description (tools summary + Docker install command from `STANDALONE-SETUP.md`).
3. Submit per each directory's submission process.
4. Track which directories accept the listing.
5. Link accepted URLs from `FastEdge-mcp-server/README.md` install section.

**Files to read first**: `FastEdge-mcp-server/README.md`, `FastEdge-mcp-server/STANDALONE-SETUP.md`, `fastedge-plugin/context/MCP_INTEGRATION.md` (the Phase 2 dropped rationale explains why the `fastedge-docs` tool is the consumer-facing surface, not raw MCP resources).

---

## 4. ~~Reference-docs artifact pipeline (vendor to Codex + GitHub Release tarball + MCP consumer)~~ ✅ DONE (2026-05-20)

All 8 tasks implemented. See `context/REFERENCE_ARTIFACT_PIPELINE.md` for details.

**Status**: ~~planned (2026-05-20). Architecture agreed; ready to implement. 8 discrete tasks, mostly self-contained.~~

**Files to read first**: `context/REFERENCE_ARTIFACT_PIPELINE.md` (full task list with file paths and validation steps), `context/PLUGIN_DISTRIBUTION.md` (the rationale — repo shape, marketplace model, release cadence), `context/MCP_INTEGRATION.md` (downstream consumer contract section).

**Order matters**: implement tasks 1 → 8 in the order listed in `REFERENCE_ARTIFACT_PIPELINE.md`. Tasks 1–5 land in this repo; Task 6 updates Codex skill paths; Task 7 updates user-facing docs; Task 8 is a cross-team handoff to the MCP server team. Each task has its own validation step — do not move forward until the prior one is green.

**Smallest viable first slice**: Tasks 1 + 2 + 3 (parameterize generator + mirror script + emit two docs-index files) is the minimum that unblocks Task 6 (Codex skill path fix). Tasks 4 + 5 + 8 (tarball + dispatch payload + MCP consumer) can land afterward without breaking anything in the meantime.

---

## Beyond this queue

Smaller / less time-critical items not in the priority queue but worth scanning before picking up unrelated work:

- `context/PLUGIN_SKILL_FINDINGS.md` — finding #16 (inference shared-prefix collapse) is open polish. Stage-1 polish observations #18, #19 also open.
- `context/MCP_INTEGRATION.md` Phase 3 — scaffold delegation to MCP server is open architecturally. Not yet designed; needs a spec pass before any implementation.
- `context/TDD_ROADMAP.md` — deploy `--skip-tests` override flag is listed as planned. Small ergonomics fix.

These are smaller than 1–4 above. Take them up if you have leftover time after 1–4, or if a related task pulls you toward them naturally.
