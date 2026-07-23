# Reference Material — How It Was Built & How to Update It

This documents the sources, method, and maintenance process for the `fastedge-docs` reference files.

---

## Reference Files

| File                   | Content                                                                             | Primary Source                                          | Status              |
| ---------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------- | ------------------- |
| `sdk-reference-js.md`  | JavaScript SDK API                                                                  | `FastEdge-sdk-js/types/*.d.ts`                           | ✅ Has real content |
| `sdk-reference-rust.md`| Rust SDK core API                                                                   | `docs.rs/fastedge`                                       | ✅ Has real content |
| `host-services-rust.md`| Rust host services (KV, secrets, dictionary)                                        | `docs.rs/fastedge` host modules                          | ⚠️ Stub — pending first sync |
| `platform-overview.md` | Architecture, PoPs, limits, app types                                               | Written from platform knowledge                         | ✅ Has real content |
| `best-practices.md`    | Patterns, Hono, KV usage, optimisation                                              | `FastEdge-sdk-js/docs/examples/` + `FastEdge-sdk-rust/examples/` | ⚠️ Review needed    |
| `error-codes.md`       | 530–533 debugging guidance                                                          | Written from platform knowledge                         | ⚠️ Review needed    |
| `js-runtime.md`        | StarlingMonkey runtime constraints, crypto.subtle matrix, SAML implementation guide | Derived from SAML app development (March 2026)          | ✅ Has real content |

---

## Sources Used (March 2026)

### 1. `FastEdge-sdk-js` repo

**Path:** `FastEdge-sdk-js/`

The authoritative source for all JavaScript SDK APIs. Read these files directly:

| File                                   | What it contains                                                                                            |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `types/fastedge-env.d.ts`              | `getEnv()` API                                                                                              |
| `types/fastedge-secret.d.ts`           | `getSecret()`, `getSecretEffectiveAt()` APIs                                                                |
| `types/fastedge-kv.d.ts`               | Full `KvStore` API with all methods and signatures                                                          |
| `types/fastedge-fs.d.ts`               | `readFileSync()` build-time API                                                                             |
| `types/globals.d.ts`                   | All Web APIs: `FetchEvent`, `ClientInfo`, `Request`, `Response`, `Headers`, `crypto`, streams, timers, etc. |
| `docs/examples/*.js`                   | Canonical working examples                                                                                  |
| `docs/src/content/docs/reference/`     | Astro docs reference pages                                                                                  |
| `docs/src/content/docs/examples/*.mdx` | Example walkthroughs                                                                                        |

**Critical:** The `types/*.d.ts` files are the ground truth for the JS SDK API. Always read these when updating — do not guess from memory.

### 2. `proxy-wasm-sdk-as` repo (integrated April 2026)

**Path:** `proxy-wasm-sdk-as/`

AssemblyScript proxy-wasm SDK for CDN filter applications. CDN-only (no HTTP app type).

| Path                                   | What it contains                                                                                            |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `docs/SDK_API.md`                      | Complete API reference — lifecycle, hooks, enums, stream_context, FastEdge host APIs                        |
| `docs/quickstart.md`                   | Getting started with AS CDN apps                                                                            |
| `assembly/fastedge/*.ts`               | FastEdge extensions: getEnv, getSecret, KvStore, getCurrentTime, setLogLevel                                |
| `examples/helloWorld/`                 | Minimal base skeleton (source for cdn-base blueprint)                                                       |
| `examples/body/`, `geoBlock/`, etc.   | Feature examples (source for blueprints + patterns)                                                         |
| `fastedge-plugin-source/manifest.json` | Contract: 16 source entries → plugin reference files                                                        |
| `fastedge-plugin-source/.generation-config.md` | Docs generation instructions with platform-specific accuracy rules                                  |

**Critical platform knowledge**: Hook state isolation (context per-hook, not per-request — nginx vs core-proxy split), unsupported proxy-wasm features omitted (metrics, gRPC, shared data, tick timers), header removal sets to empty on nginx.

### 3. `FastEdge-sdk-rust` repo (migrated from FastEdge-examples)

**Path:** `FastEdge-sdk-rust/`

Rust SDK with comprehensive examples organized by app type. Useful for verifying patterns and finding real-world usage:

| Path                            | What it contains                                    |
| ------------------------------- | --------------------------------------------------- |
| `examples/http/basic/*/`        | Rust HTTP handler examples (10 examples)            |
| `examples/http/wasi/*/`         | Rust HTTP WASI handler examples (9 examples)        |
| `examples/cdn/*/`               | Rust CDN wireframe/filter examples (15 examples)    |

### 3. `docs.rs/fastedge` (fetched via WebFetch)

**URL:** `https://docs.rs/fastedge/latest/fastedge/`

Rust SDK API documentation. Covers:

- `#[fastedge::http]` macro (from `fastedge-derive`)
- `fastedge::http` module (re-exports from `http` crate)
- `fastedge::key_value` — `Store::open()`, `get()`
- `fastedge::secret` — `secret::get()`
- `fastedge::send_request` — outbound HTTP
- Feature flags: `proxywasm`, `json`

**Note:** `crates.io` requires JavaScript rendering — use `docs.rs` instead which serves static HTML.

### 4. `docs.rs/fastedge-derive` (fetched via WebFetch)

**URL:** `https://docs.rs/fastedge-derive/latest/fastedge_derive/`

Documents the `#[fastedge::http]` procedural macro specifically.

---

## How to Update the Reference Files

### When the JS SDK changes

1. Check what changed in `FastEdge-sdk-js`:

   ```bash
   git -C FastEdge-sdk-js log --oneline -10
   git -C FastEdge-sdk-js diff HEAD~1 types/
   ```

2. Read the updated `types/*.d.ts` files — they are the source of truth

3. Update `sdk-reference-js.md` to match — pay particular attention to:
   - `KvStore` API (historically had drift between docs and actual API)
   - New modules or functions in `types/index.d.ts`

4. Fix any affected patterns in `best-practices.md`

### When the Rust SDK changes

1. Fetch updated API: `WebFetch https://docs.rs/fastedge/latest/fastedge/`

2. Check the version on `crates.io` to know if there's been a release:

   ```bash
   curl -s "https://crates.io/api/v1/crates/fastedge" | jq '.crate.newest_version'
   ```

3. Update `sdk-reference-rust.md` and `host-services-rust.md`

### When platform limits or features change

Update `platform-overview.md` — resource limits table, app types, networking capabilities.

### After updating reference files

Bump the plugin version in `plugins/gcore-fastedge/.claude-plugin/plugin.json`:

```json
{ "version": "1.0.1" }
```

And the marketplace version in `.claude-plugin/marketplace.json` to match.

---

## Known Issues / Gaps (updated April 2026)

- **`platform-overview.md` resource limits** — plan limits (50ms/128MB basic, 200ms/256MB pro) are from memory, not confirmed from official docs. Verify against `gcore.com/docs/fastedge` before publishing.
- **Rust `key_value` API** — scan, sorted set, and bloom filter operations may exist in Rust but were not confirmed from docs.rs (the page was sparse). Check `docs.rs/fastedge` for the full `key_value::Store` API.
- **`fastedge-docs` SKILL.md** auto-invocation — the `disable-model-invocation: false` setting means this skill makes an additional LLM call. These reference files are loaded as context for that call.
- **FastEdge-sdk-rust CDN_APPS.md** — `.generation-config.md` updated (April 2026) with hook state isolation, expanded request properties (4→16), header removal caveat. Needs `generate-docs CDN_APPS.md` re-run.
- **proxy-wasm-sdk-as** — fully integrated as 4th source repo (April 2026). Pipeline test (AS-07) pending. See `context/repos/proxy-wasm-sdk-as.md` for full status.

---

## GitHub Actions Sync Pipeline (v2)

Reference files are updated automatically via a GitHub Actions pipeline. A human reviews and merges the generated PRs.

### Authentication — GitHub App

The pipeline authenticates via a **GitHub App** (`fastedge-plugin-sync`), not a Personal Access Token. This gives the pipeline its own bot identity (`fastedge-plugin-sync[bot]`) so no human developer is blocked from reviewing or approving PRs.

**How it works:**

1. The workflow generates a short-lived installation token using `actions/create-github-app-token@v1`
2. The token is exported as `GH_TOKEN` via `GITHUB_ENV`
3. All `gh` CLI commands and `git push` operations inherit it automatically
4. Tokens expire after 1 hour (sufficient for typical pipeline runs)

**Required secrets:**

| Secret | Value |
|--------|-------|
| `FASTEDGE_APP_ID` | Numeric App ID from GitHub App settings |
| `FASTEDGE_APP_PRIVATE_KEY` | Full PEM private key contents (including `-----BEGIN/END RSA PRIVATE KEY-----` lines) |

**App permissions (minimum):**

| Permission | Access | Why |
|---|---|---|
| Contents | Read & Write | Push PR branches and baseline tags |
| Pull requests | Read & Write | Create, edit, and label PRs |
| Metadata | Read | Required by default |

**The App cannot merge to `main`** as long as branch protection rules require PR approval — it can only create branches and open PRs. It is not on any bypass list.

**App installation scope:** Installed on the plugin repo (where the workflow runs). Source repos (fastedge-test, FastEdge-sdk-js) are public and don't require App installation for read access.

**Setup (if recreating):**

1. Create GitHub App under org or personal account (Settings > Developer settings > GitHub Apps)
2. Set permissions above, uncheck webhook "Active", ignore OAuth/post-install sections
3. If created under personal account, select "Any account" for installation scope, then install on the org (requires org admin approval)
4. Generate a private key (.pem) from the App's General page
5. Add `FASTEDGE_APP_ID` and `FASTEDGE_APP_PRIVATE_KEY` as repository secrets
6. The workflow step `actions/create-github-app-token@v1` handles token generation

**Why not a PAT?** A PAT is tied to a specific developer — that developer cannot approve PRs created by their own token. A GitHub App has its own bot identity, so any team member can review. Apps also use short-lived tokens (better security) and cost nothing (unlike machine user accounts which consume a seat).

### Key Documents

| Document                                    | Purpose                                                                                |
| ------------------------------------------- | -------------------------------------------------------------------------------------- |
| `sources.json` (repo root)                  | Slim pipeline config: which repos, how to fetch, which agents (v2 format)              |
| `manifest.json` (in source repo contract)   | Content mapping: what files the source provides, where they map to in the plugin       |
| `.github/workflows/sync-reference-docs.yml` | The pipeline workflow — triggers, per-repo loop, dry_run guard, step summary           |
| `context/sources-json-schema.md`            | Authoritative v2 schema + validation rules + manifest schema + traceability format     |

### Two-Stage Generation

**Stage 1 (source repo, local)**: A generation agent reads source code + `.generation-config.md` and produces standardized contract files in `fastedge-plugin-source/`. This is faithful extraction.

**Stage 2 (plugin pipeline, CI)**: The pipeline agent reads contract files + agent-intent-skills and produces curated reference docs. This is audience-aware curation.

### Pipeline Architecture (v2)

```
workflow_dispatch / repository_dispatch (fastedge-ref-update)
  │
  ├── validate-sources.sh sources.json       ← v2 rules (7 checks)
  │
  └── process-repos.sh
        for each repo in sources.json:
          process_repo()                     ← isolated; failure does not block others
            fetch-repo.sh --contract-path    ← sparse checkout contract dir only
            read manifest.json               ← discover target_mapping
            validate-contract.sh             ← validate contract (6 rules)
            │
            for each target_mapping entry:
              invoke-agent.sh --role generator ← claude -p with synthesis intent
              invoke-agent.sh --role reviewer  ← OpenAI gpt-4o, VERDICT + FINDINGS
            │
            [dry_run gate — skips writes/PR/tag when dry_run=true]
            │
            if all steps succeed:
              invoke-agent.sh --role splice   ← section-splice into reference file
              manage-pr.sh                    ← create/update PR; add/remove labels
              git tag ref-update/<repo-id>    ← update baseline (branchless)
            else:
              record_failure(), continue      ← per-repo isolation
```

### Two-Level Config

| Config | Location | Controls | Example |
|--------|----------|----------|---------|
| `sources.json` | Plugin repo root | HOW to fetch (URL, ref, trigger, agents, intent_dir) | `"contract_path": "fastedge-plugin-source/"` |
| `manifest.json` | Source repo `fastedge-plugin-source/` | WHAT to generate (provides, target_mapping, validation) | `"api-reference.md" → "plugins/.../testing-api.md"` |

### Triggers

| Trigger                                       | Input                                              | Behaviour                                                          |
| --------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------ |
| `workflow_dispatch`                           | `source_repo_id` (optional), `dry_run` (bool)      | Process all `schedule`/`both` repos, or only the named one         |
| `repository_dispatch` (`fastedge-ref-update`) | `client_payload.source_repo_id`, `.ref`, `.commit` | Process only the identified repo; validated against `sources.json` |

### Scripts

| Script                               | Purpose                                                                            |
| ------------------------------------ | ---------------------------------------------------------------------------------- |
| `scripts/sync/validate-sources.sh`   | Validates `sources.json` v2 (7 rules including version check and v1 field rejection) |
| `scripts/sync/validate-contract.sh`  | Validates a contract directory's `manifest.json` (6 rules, advisory/strict modes)  |
| `scripts/sync/fetch-repo.sh`         | Sparse checkout `contract_path` only; emit `CHANGED=true/false`; baseline tags     |
| `scripts/sync/invoke-agent.sh`       | Generator (Claude), reviewer (OpenAI gpt-4o), and section-splice roles             |
| `scripts/sync/manage-pr.sh`          | Create-or-update PR via `gh` CLI; label management (`needs-review`, `missing-intent-skill`) |
| `scripts/sync/process-repos.sh`      | Main loop; reads manifest after fetch; per-repo isolation                          |

### Templates

| File | Purpose |
|------|---------|
| `scripts/sync/templates/generation-config-template.md` | Starting point for source repos to create `.generation-config.md` |

### Synthesis Intent Files

The pipeline resolves intent files by stripping everything up to and including `reference/` from the target reference file path and appending the remaining suffix to `intent_dir` (from `sources.json`). For example, a reference file at `plugins/.../reference/http/kv-store-ts.md` with `intent_dir: "agent-intent-skills/fastedge-sdk-rust/"` resolves to `agent-intent-skills/fastedge-sdk-rust/http/kv-store-ts.md`. This preserves subdirectory structure, so intent directories must mirror the folder hierarchy under `reference/`. When found, the content is injected into the generator prompt as a `## Synthesis Instructions` block. When no intent file is found, the generator proceeds without synthesis instructions (relying on its own reasoning) and the pipeline emits a yellow `[WARNING]` to stderr. If any mapping entry in a run lacks an intent file, the `missing-intent-skill` label is added to the PR.

**Hierarchical base pattern**: Intent skills follow a two-level inheritance model:

1. **Root-level base files** (`_docs-pattern-base.md`, `_scaffold-blueprint-base.md`) — contain universal rules that apply to all generated reference docs: cross-referencing rules (never output file links — use descriptive topic terms instead), accuracy constraints, output format, and general exclusions. Root-level intent skills (e.g., `quickstart.md`, `sdk-reference-js.md`, `build-cli.md`) reference these directly.

2. **Subdirectory base files** (`http/_docs-pattern-http.md`, `cdn/_docs-pattern-cdn.md`, `http/_scaffold-blueprint-http.md`, `cdn/_scaffold-blueprint-cdn.md`) — inherit from the root base and add appType-specific structure (required sections for examples, scaffold blueprint format). Per-example intent files in `http/` or `cdn/` reference these local bases.

Per-example intent files are short (~15-20 lines) and reference their local base via a blockquote link. Base skeleton intent files (e.g., `http/base-ts.md`) reference the local scaffold base for cross-referencing rules but define their own structure.

**Cross-referencing rule** (enforced via root base files): Generated reference docs must never contain file links or filenames as cross-references (e.g., `[SDK_API](SDK_API.md)` or `./dotenv.md`). Reference docs live in different skill directories so relative links will not resolve. Instead, use descriptive topic terms that agents can search for (e.g., "the SDK API reference", "the dotenv configuration guide").

When adding a new example, copy an existing per-example file from the same subdirectory and change only the target, frontmatter, and extraction hints.

### Testing

Plain bash test suite — no external dependencies. Uses path-shimable mocks in `scripts/sync/tests/mocks/` for `gh` and `git`. Run all tests with:

```bash
bash scripts/sync/tests/run-all-tests.sh
```

| Test file                    | Coverage                                                                             |
| ---------------------------- | ------------------------------------------------------------------------------------ |
| `test-validate-sources.sh`   | v2 schema rules (version, contract_path, intent_dir, v1 rejection)                  |
| `test-validate-contract.sh`  | Contract validation (manifest parse, required files, generated headers, strict modes) |
| `test-fetch-repo.sh`         | Arg validation, contract-path anchoring, `CHANGED` detection, baseline tag parsing   |
| `test-verdict-parse.sh`      | `VERDICT`/`FINDINGS` parse logic                                                     |
| `test-section-splice.sh`     | Section splice — mid-file, EOF, not found, multiple sections, multi-repo frontmatter |
| `test-process-repos.sh`      | Loop isolation — trigger filter, `FILTER_REPO_ID`, dry_run gate, fetch failure       |
| `test-manage-pr.sh`          | PR creation/edit, `--base` propagation, URL emission, `missing-intent-skill` label   |

**Total: 7 suites, 67 tests.**

### Notes

- `sources.json` is now v2 format — `updates[]` and `sparse_paths` removed, replaced by `contract_path` + `intent_dir` + manifest-driven mapping.
- `FastEdge-examples` is deprecated — Rust examples migrated to `FastEdge-sdk-rust/examples/`. `best-practices.md` source should reference `FastEdge-sdk-rust/examples/` going forward.
- `gh api` is used for Rule 2 URL reachability checks (supports SAML-protected private repos via GitHub App token).
- Baseline state is stored as annotated git tags (`refs/tags/ref-update/<repo-id>`), not committed files.
- `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `FASTEDGE_APP_ID`, and `FASTEDGE_APP_PRIVATE_KEY` must be configured as repository secrets.

---

## Pipeline Data Structures

### Baseline Git Tags — Per-Repo Processing Record

Persists the last-successfully-processed state per source repo as a force-updated annotated git tag in the plugin repo. No file commit required.

**Tag naming**: `refs/tags/ref-update/<repo-id>`

**Tag message format** (single line, pipe-delimited):
```
<ref> | <commit-sha> | <processed_at-ISO8601>
```

**Example**:
```
tag: refs/tags/ref-update/fastedge-test
msg: v2.1.0 | abc1234def5678abc1234def5678abc1234def56 | 2026-03-09T14:30:00Z
```

**State transitions**:
- First run (no tag exists): treat as new content, run full pipeline; create annotated tag on success
- Subsequent runs: fetch tag message → parse commit SHA → compare to current source HEAD → skip if identical
- After successful PR open: force-push tag with updated commit SHA, ref, and processed_at

**Tag push**:
```bash
git tag -f -a "ref-update/$REPO_ID" \
  -m "$REF | $COMMIT | $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push origin --force "refs/tags/ref-update/$REPO_ID"
```

**Tag read**:
```bash
TAG_MSG=$(git ls-remote origin "refs/tags/ref-update/$REPO_ID" \
  | awk '{print $1}' \
  | xargs -I{} git cat-file tag {} 2>/dev/null \
  | grep -A1 "^$" | tail -1)
LAST_COMMIT=$(echo "$TAG_MSG" | cut -d'|' -f2 | tr -d ' ')
```

**Inspect all baselines**:
```bash
git ls-remote origin 'refs/tags/ref-update/*'
```

### Pull Request Shape — One Per Changed Source Repo

**Branch naming**: `auto-ref-update/<repo-id>` (stable name, same branch reused on re-runs so existing PR gets updated)

**PR labels**:

| Label | Color | When Applied | When Removed |
|-------|-------|--------------|--------------|
| `auto-ref-update` | `0075ca` (blue) | Always | Never |
| `needs-review` | `d93f0b` (red-orange) | Reviewer verdict is REJECT | Subsequent run with ACCEPT verdict |
| `missing-intent-skill` | `e4e669` (yellow-green) | Any mapping entry had no intent file | Subsequent run where all entries have intent files |

**PR structure**:
```
title:  "auto: update reference docs from <repo-id> (<ref>)"
labels: ["auto-ref-update"]
        + ["needs-review"]          // reviewer verdict is REJECT
        + ["missing-intent-skill"]  // any mapping entry lacked an intent file
body:
  ## Source
  - Repo: <github_url>
  - Ref: <ref>
  - Commit: <commit>

  ## Changes
  <list of reference files updated, with section if applicable>

  ## Review Agent Findings
  <reviewer_agent> verdict: <ACCEPT | REJECT>

  <verbatim review output>

  ---
  _Generated by sync-reference-docs workflow. Do not edit this PR body manually._
```

**Lifecycle**:
- Opened on first run where changes detected for that repo
- Body replaced (not appended) on subsequent runs that update the same open PR
- Review findings always posted as fresh body update (not a separate comment)
- Humans merge; automation never merges

### Workflow Run Summary

Written to GitHub Actions step summary (`$GITHUB_STEP_SUMMARY`), not persisted to a file.

**Format** (Markdown table):
```
| Source Repo       | Outcome   | Ref     | PR                      |
|-------------------|-----------|---------|-------------------------|
| fastedge-sdk-js   | ✅ PR #42 | v2.1.0  | https://github.com/...  |
| fastedge-sdk-rust | ⏭ skipped | v0.4.1 | no changes              |
| fastedge-test     | ❌ failed | main    | fetch error             |
```

Failed repos are listed with the specific failing step.
