# Reference-Docs Artifact Pipeline — Implementation Plan

**Status:** Plan (not yet implemented). Read this end-to-end before touching the release pipeline.
**Date:** 2026-05-20
**Companion docs:** `PLUGIN_DISTRIBUTION.md` (the why), `MCP_INTEGRATION.md` (downstream consumer), `REFERENCE_MATERIAL.md` (pipeline source-of-truth model).

---

## Goal

Make reference docs available to **all three consumers** (Claude plugin, Codex plugin, FastEdge-mcp-server) without sibling-folder coupling, and without rebuilding the MCP server on every merge.

The release pipeline already exists and does most of the work. This document specifies the **delta** needed.

---

## Current state (as of 2026-05-20)

### What works today

- `scripts/sync/process-repos.sh` writes reference markdown to `plugins/gcore-fastedge/skills/.../reference/` only. Opens a PR per source-repo dispatch. **Codex folder is untouched.**
- `scripts/sync/generate-docs-index.mjs` scans only the Claude plugin's reference roots and writes to `plugins/gcore-fastedge/docs-index.json`. **No Codex docs-index exists.**
- `.github/workflows/release-plugin.yml` runs weekly. Detects changes in `plugins/gcore-fastedge/skills/*/reference/**/*.md`. Regenerates docs-index, bumps both `plugin.json` versions in lockstep via `scripts/bump-version.sh`, tags, creates GitHub Release with `--generate-notes`, dispatches `event_type=plugin-release` to `FastEdge-mcp-server`.
- `scripts/bump-version.sh` writes the same version to both `plugins/gcore-fastedge/.claude-plugin/plugin.json` and `plugins/gcore-fastedge-codex/.codex-plugin/plugin.json`.

### What's missing

1. **Codex plugin reference markdown is not mirrored from Claude.** Codex's `fastedge-docs` skill reads sibling paths today — broken once installed standalone.
2. **No Codex `docs-index.json`** — the generator only emits one file.
3. **GitHub Release has no attached tarball** — only release notes. The MCP server dispatch payload doesn't point at a downloadable artifact.
4. **MCP server has no `repository_dispatch` consumer wired up** — the plugin dispatches, but nothing listens on the MCP side yet.
5. **Codex SKILL.md references sibling paths** — needs path rewrite after mirroring lands.

---

## Order of operations

Implement in this order. Each task is independently testable.

1. Parameterize `generate-docs-index.mjs` so it can emit a docs-index for either plugin folder.
2. Add a mirroring step to `release-plugin.yml` that copies Claude reference markdown into the Codex plugin folder.
3. Generate `docs-index.json` for both plugins in `release-plugin.yml`.
4. Package the reference content into a tarball and attach it to the GitHub Release.
5. Extend the cross-repo dispatch payload with the tarball download URL.
6. Update Codex skills to read from their own folder.
7. Update README and `docs/quickstart.md` for dual-runtime install instructions.
8. Wire the MCP server consumer (lives in `FastEdge-mcp-server` repo — task description here for cross-team visibility).

---

## Tasks

### Task 1 — Parameterize `generate-docs-index.mjs`

**File:** `scripts/sync/generate-docs-index.mjs`

**Current behavior:** hard-coded `pluginRoot/plugins/gcore-fastedge/...` for both input scan and output path. Lines 11–16:

```js
const outputPath = path.join(pluginRoot, "plugins/gcore-fastedge/docs-index.json");
const referenceRoots = [
  path.join(pluginRoot, "plugins/gcore-fastedge/skills/fastedge-docs/reference"),
  path.join(pluginRoot, "plugins/gcore-fastedge/skills/test/reference"),
];
```

**Change to:** accept a `--plugin-dir <name>` argument (e.g., `gcore-fastedge` or `gcore-fastedge-codex`). Both `outputPath` and `referenceRoots` derive from that. Default to `gcore-fastedge` when arg not supplied (preserves current behavior).

**Path field handling inside topics:** the existing code emits `path: "plugins/gcore-fastedge/skills/fastedge-docs/reference/..."`. After parameterization, when generating for `gcore-fastedge-codex`, the `path:` field for every topic must point at the Codex plugin folder (so the Codex skill can resolve it). The `toPosixRelative` helper already computes paths relative to `pluginRoot` — that's correct as long as `referenceRoots` point at the right plugin's folders.

**Wrapper:** `scripts/sync/generate-docs-index.sh` currently calls the mjs once with no args. Update to call it twice:

```bash
node "$SCRIPT_DIR/generate-docs-index.mjs" --plugin-dir gcore-fastedge
node "$SCRIPT_DIR/generate-docs-index.mjs" --plugin-dir gcore-fastedge-codex
```

The second call requires Task 2 (mirroring) to have run first within the workflow. Order matters in `release-plugin.yml`.

**Validation:**
- Run `bash scripts/sync/generate-docs-index.sh` locally after manually copying Claude refs into Codex folder.
- Confirm two files exist: `plugins/gcore-fastedge/docs-index.json` and `plugins/gcore-fastedge-codex/docs-index.json`.
- Confirm topic `path:` fields in each file point at that plugin's own folder, not the sibling.
- Confirm topic count is identical between the two files (mirroring is faithful).
- Existing test in `scripts/sync/tests/test-docs-index-pipeline.sh` should still pass — it tests that `process-repos.sh` does NOT generate the index, which remains true.

---

### Task 2 — Mirror reference markdown into Codex plugin

**Where:** add a new step in `.github/workflows/release-plugin.yml`, **before** the "Regenerate docs-index.json" step.

**What it does:** copies `plugins/gcore-fastedge/skills/fastedge-docs/reference/` and `plugins/gcore-fastedge/skills/test/reference/` (and any future reference roots — keep the list maintained in one place) into the matching paths under `plugins/gcore-fastedge-codex/skills/.../reference/`. Use a small mirroring script under `scripts/sync/mirror-reference-to-codex.sh` so it's testable in isolation.

**Mirroring script behavior:**
- For each source reference root (`plugins/gcore-fastedge/skills/<skill>/reference/`), rsync (or `cp -r` + delete-removed) to the matching `plugins/gcore-fastedge-codex/skills/<skill>/reference/`.
- Use `rsync -a --delete` to ensure removed files in Claude folder are removed in Codex folder.
- Print a one-line summary per skill (`mirrored N files for <skill>`).
- Exit non-zero if any source root is missing (catches drift in skill folder names).

**Why mirror in the release workflow and not in `process-repos.sh`:**
- Per-PR mirroring would make every sync PR touch two folders. Doubles diff size and review surface.
- Release is the only point at which we ship Codex anything — mirroring at release time keeps the main branch's Codex folder consistent with the most recent release tag, which is what users get when they install.
- Mirroring is purely mechanical — no need for human review per mirror, and the release workflow already commits as a bot identity.

**Validation:**
- Trigger `release-plugin.yml` with `force: true` after the mirror script lands.
- Inspect the resulting commit: should add/update files under `plugins/gcore-fastedge-codex/skills/.../reference/` to exactly match the Claude folder.
- Diff Claude reference folder vs. Codex reference folder after the workflow runs: should be empty.

**Edge cases to handle:**
- New skill added with a reference folder (e.g., `skills/debug/reference/`): the mirror script's source-root list must be updated. Document this in a comment at the top of the script. **Keep it in sync with the `referenceRoots` array in `generate-docs-index.mjs`** — they describe the same set.

---

### Task 3 — Generate both docs-index files in release workflow

**File:** `.github/workflows/release-plugin.yml`, the "Regenerate docs-index.json" step (line ~100).

**Change:** Already covered by Task 1's update to `generate-docs-index.sh`. Confirm the step runs `bash scripts/sync/generate-docs-index.sh` (no arg change needed at the workflow level) and the wrapper handles invoking the mjs twice.

**Commit step update:** currently stages only the Claude docs-index and both plugin.json files (lines 120–122):

```yaml
git add --force plugins/gcore-fastedge/docs-index.json
git add plugins/gcore-fastedge/.claude-plugin/plugin.json
git add plugins/gcore-fastedge-codex/.codex-plugin/plugin.json
```

Add staging for Codex docs-index and the mirrored reference files:

```yaml
git add --force plugins/gcore-fastedge/docs-index.json
git add --force plugins/gcore-fastedge-codex/docs-index.json
git add plugins/gcore-fastedge-codex/skills/  # mirrored reference content
git add plugins/gcore-fastedge/.claude-plugin/plugin.json
git add plugins/gcore-fastedge-codex/.codex-plugin/plugin.json
```

The `git add plugins/gcore-fastedge-codex/skills/` is broad — it will pick up SKILL.md edits too, which is fine since those are intentional changes when they happen. If we want tighter staging, replace with explicit reference paths matched against the mirror script's roots.

**Validation:**
- After workflow run, the release commit should contain: updated reference markdown under both plugin folders, two `docs-index.json` updates, two `plugin.json` version bumps.

---

### Task 4 — Package + attach tarball to GitHub Release

**File:** `.github/workflows/release-plugin.yml`, between "Create GitHub Release" and the dispatch step (around line 137).

**What to package:** the reference-docs artifact must be standalone-consumable by any AI tool, including non-Claude/non-Codex MCP clients. Contents:

```
fastedge-reference-docs-vX.Y.Z/
├── docs-index.json               # the Claude index (single canonical index)
├── reference/
│   ├── fastedge-docs/            # contents of skills/fastedge-docs/reference/
│   └── test/                     # contents of skills/test/reference/
└── METADATA.json                 # version, generated_at, source commit, schema_version, file count
```

Use the Claude plugin's `docs-index.json` as the canonical index in the artifact. **Important:** the `path:` fields inside that index will say `plugins/gcore-fastedge/skills/.../reference/...md`. The MCP server consumer must understand to rewrite those paths to its own layout (or we strip the `plugins/gcore-fastedge/skills/` prefix when packaging — choose during implementation; tarball-internal paths are simpler).

**Recommended approach:** generate a third docs-index variant during packaging where `path:` fields are relative to the artifact root (e.g., `reference/fastedge-docs/sdk-reference-js.md`). This makes the artifact self-contained and avoids forcing the consumer to do path math. Put this in `scripts/sync/package-reference-artifact.sh`.

**Packaging script outline (`scripts/sync/package-reference-artifact.sh`):**

```bash
# Inputs: VERSION (env var, e.g., "1.2.3")
# Output: dist/fastedge-reference-docs-vX.Y.Z.tar.gz

STAGE="dist/stage/fastedge-reference-docs-v${VERSION}"
mkdir -p "$STAGE/reference"
cp -r plugins/gcore-fastedge/skills/fastedge-docs/reference "$STAGE/reference/fastedge-docs"
cp -r plugins/gcore-fastedge/skills/test/reference "$STAGE/reference/test"

# Rewrite docs-index paths to artifact-relative
node scripts/sync/rewrite-docs-index-paths.mjs \
  --input plugins/gcore-fastedge/docs-index.json \
  --output "$STAGE/docs-index.json" \
  --prefix "reference"

# Write METADATA.json
cat > "$STAGE/METADATA.json" <<EOF
{
  "version": "${VERSION}",
  "schema_version": "1.0.0",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source_repo": "G-Core/fastedge-plugin",
  "source_commit": "$(git rev-parse HEAD)",
  "tag": "v${VERSION}"
}
EOF

tar -czf "dist/fastedge-reference-docs-v${VERSION}.tar.gz" -C "dist/stage" "fastedge-reference-docs-v${VERSION}"
sha256sum "dist/fastedge-reference-docs-v${VERSION}.tar.gz" > "dist/fastedge-reference-docs-v${VERSION}.tar.gz.sha256"
```

The `rewrite-docs-index-paths.mjs` script is a small node script that loads the Claude docs-index, replaces the `plugins/gcore-fastedge/skills/fastedge-docs/reference/` and `plugins/gcore-fastedge/skills/test/reference/` prefixes in every `path` field with `reference/fastedge-docs/` and `reference/test/` respectively, and writes the result.

**Attach to release:**

```yaml
- name: Package reference-docs artifact
  if: steps.detect.outputs.changed == 'true' || inputs.force == true
  env:
    VERSION: ${{ steps.bump.outputs.version }}
  run: bash scripts/sync/package-reference-artifact.sh

- name: Upload artifact to GitHub Release
  if: steps.detect.outputs.changed == 'true' || inputs.force == true
  env:
    GH_TOKEN: ${{ steps.app-token.outputs.token }}
    VERSION: ${{ steps.bump.outputs.version }}
  run: |
    gh release upload "v${VERSION}" \
      "dist/fastedge-reference-docs-v${VERSION}.tar.gz" \
      "dist/fastedge-reference-docs-v${VERSION}.tar.gz.sha256"
```

**Validation:**
- After a forced release run, `gh release view v<version>` should list two attached files.
- Download the tarball, extract, confirm structure matches the layout above.
- Confirm `docs-index.json` inside the artifact has paths starting with `reference/` (not `plugins/gcore-fastedge/...`).

---

### Task 5 — Extend cross-repo dispatch payload

**File:** `.github/workflows/release-plugin.yml`, "Dispatch to FastEdge-mcp-server" step (around line 147).

**Current payload:**

```json
{
  "version": "1.2.3",
  "tag": "v1.2.3",
  "commit": "abc1234..."
}
```

**Extend to:**

```json
{
  "version": "1.2.3",
  "tag": "v1.2.3",
  "commit": "abc1234...",
  "artifact_url": "https://github.com/G-Core/fastedge-plugin/releases/download/v1.2.3/fastedge-reference-docs-v1.2.3.tar.gz",
  "artifact_sha256_url": "https://github.com/G-Core/fastedge-plugin/releases/download/v1.2.3/fastedge-reference-docs-v1.2.3.tar.gz.sha256"
}
```

The MCP server consumer can construct these URLs from the tag alone, but passing them explicitly is robust to future renaming. Use a known URL pattern documented at the top of the workflow.

**Validation:** Inspect a workflow run after this change. The dispatch payload appears in the workflow logs. Cross-check the URLs by visiting them in a browser.

---

### Task 6 — Update Codex skills to read own folder

**Files to update:**
- `plugins/gcore-fastedge-codex/skills/fastedge-docs/SKILL.md` — change `plugins/gcore-fastedge/docs-index.json` to `plugins/gcore-fastedge-codex/docs-index.json`. Change reference paths to point at Codex's own `skills/fastedge-docs/reference/`.
- Audit other Codex SKILL.md files for any other sibling references (`grep -rn "gcore-fastedge/" plugins/gcore-fastedge-codex/`). The current grep returns hits in `deploy/`, `manage/`, `debug/`, `fastedge-core/`, `test/`, `scaffold/`, `live-test/`, and `README.md` — review each.
- `docs/codex-quickstart.md` — currently tells users docs come from `plugins/gcore-fastedge/...`. Update to reflect Codex's own folder once mirroring lands.

**Important:** do this task **after** Tasks 2 and 3 land and the Codex folder actually contains the mirrored files + docs-index. Otherwise you break the existing (broken-at-install-time-only) authoring flow.

**Validation:**
- `bash scripts/validate-codex-plugin.sh` should pass with no path errors.
- Manual review: install the Codex plugin against a fresh path (or simulate by copying only `plugins/gcore-fastedge-codex/` to a temp dir) and confirm the `fastedge-docs` skill resolves its index and reference files without needing the sibling.

---

### Task 7 — README + quickstart updates

**Files:**
- `README.md` — add a Codex install section. Currently only documents Claude install. Keep the Claude section as primary.
- `docs/quickstart.md` — fork into "Claude Code" and "Codex" install paths. Both should converge on the same skill set.
- `docs/codex-quickstart.md` — already exists; update path references per Task 6.

**No new docs needed** — just bring existing ones in line with the dual-runtime model described in `PLUGIN_DISTRIBUTION.md`.

---

### Task 8 — FastEdge-mcp-server consumer ✅ DONE (2026-05-20)

**Where:** `FastEdge-mcp-server` repo.

**Implemented:** `scripts/sync-from-artifact.sh` + updated `.github/workflows/sync-and-release.yml`.

On `repository_dispatch: plugin-release` the workflow now:
1. Reads `artifact_url` + `artifact_sha256_url` from the dispatch payload.
2. Calls `sync-from-artifact.sh` which downloads, verifies sha256, extracts the tarball, and syncs `reference-docs/` (same id-as-filename convention as the manual sync script). Writes `reference-docs/VERSION` with the pinned version string.
3. Commits + tags → triggers `create-release.yaml` → Docker image rebuild.

The `workflow_dispatch` path (sparse checkout + `sync-reference-docs.sh`) is unchanged for manual/dev use.

**Contract (unchanged):**
- Tarball location: `https://github.com/G-Core/fastedge-plugin/releases/download/<tag>/fastedge-reference-docs-<tag>.tar.gz` (and `.sha256` sibling).
- Dispatch event name: `plugin-release`.
- Dispatch payload schema: version, tag, commit, artifact_url, artifact_sha256_url.

---

## Validation: end-to-end

After all 8 tasks land, do one full end-to-end validation:

1. Make a deliberate reference-doc change (small typo fix in `plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference-js.md`).
2. Trigger `release-plugin.yml` with `workflow_dispatch` and `force: true`.
3. Confirm:
   - Commit on `main` contains: typo fix in Claude folder, identical typo fix mirrored to Codex folder, both `docs-index.json` updated, both `plugin.json` versions bumped.
   - GitHub Release `vX.Y.Z` exists with two attached files (tarball + sha256).
   - Tarball extracts to the documented structure; `docs-index.json` inside has artifact-relative paths.
   - `repository_dispatch` to `FastEdge-mcp-server` fired with extended payload (visible in workflow logs).
4. On the MCP server side (after Task 8 lands): a PR appears within minutes bumping the vendor pin.
5. Merging that PR triggers MCP Docker image rebuild and `ghcr.io/g-core/fastedge-mcp-server:latest` updates within the existing build window.

If all five hold, the artifact pipeline is functioning correctly.

---

## Out of scope (do NOT do as part of this work)

- **Do not** publish reference docs to npm. GitHub Releases is the agreed artifact host. Revisit only if a strong cross-ecosystem use case appears.
- **Do not** change the sync-pipeline PR flow. PRs still target the Claude plugin folder only. Codex mirroring happens at release time, not per-PR.
- **Do not** add a runtime fetch step to either plugin. Plugins must be offline-functional after install.
- **Do not** split the version numbers. Both plugins and the reference-docs artifact share one string per release.
- **Do not** reintroduce the dropped Phase 2 (reference docs as MCP resources). The `fastedge-docs` MCP tool is the access path for non-Claude/non-Codex MCP clients.

---

## Risk + rollback

**Risk: mirroring corrupts Codex folder.** Mitigation: mirror script uses `rsync -a --delete` so output is deterministic. If something goes wrong on a release run, the previous tag still works for users — they'll just be on the older version until the next successful release.

**Risk: tarball missing or malformed.** Mitigation: the MCP server consumer verifies checksum before extracting. On verification failure, the bump PR is not opened and the existing pinned version stays in place. The MCP image is not affected.

**Risk: docs-index path rewriting introduces a bug.** Mitigation: keep `scripts/sync/rewrite-docs-index-paths.mjs` small and well-tested. Add a unit test that loads a sample index, rewrites it, and asserts the path transformations are correct.

**Risk: cross-repo dispatch fails silently.** Mitigation: log the dispatch HTTP response in the workflow. If status is not 204, fail the step. (The MCP server side currently no-ops because no listener exists — Task 8 fixes that.)

---

## File map (what each task touches)

| Task | New files | Modified files |
|---|---|---|
| 1 | — | `scripts/sync/generate-docs-index.mjs`, `scripts/sync/generate-docs-index.sh` |
| 2 | `scripts/sync/mirror-reference-to-codex.sh` | `.github/workflows/release-plugin.yml` |
| 3 | — | `.github/workflows/release-plugin.yml` |
| 4 | `scripts/sync/package-reference-artifact.sh`, `scripts/sync/rewrite-docs-index-paths.mjs` | `.github/workflows/release-plugin.yml` |
| 5 | — | `.github/workflows/release-plugin.yml` |
| 6 | — | `plugins/gcore-fastedge-codex/skills/**/SKILL.md`, `docs/codex-quickstart.md` |
| 7 | — | `README.md`, `docs/quickstart.md`, `docs/codex-quickstart.md` |
| 8 | `.github/workflows/sync-reference-docs.yml` (in MCP server repo) | (MCP server side — out of this repo) |
