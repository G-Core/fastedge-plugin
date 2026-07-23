# Pipeline Design Decisions

Documents the *why* behind key technical choices in the sync pipeline. Read this when modifying pipeline scripts or extending the pipeline to new repos.

> **Historical reference**: This file was distilled from `specs/001-auto-ref-update/` (a speckit project used during initial pipeline development). The original spec, research, data model, contracts, tasks, and checklists were removed after migration. To view the original files, check git history at or before commit `725c3e0` (last commit that touched `specs/001-auto-ref-update/`).

---

## 1. Claude Code CLI — Non-Interactive CI Invocation

**Decision**: Use `claude -p "<prompt>"` with `ANTHROPIC_API_KEY` environment variable.

**Rationale**: The `-p` / `--print` flag puts Claude Code into headless mode — it executes the prompt, returns output, and exits without any interactive session. This is the documented path for CI use.

**Pattern**:
```bash
npm install -g @anthropic-ai/claude-code
export ANTHROPIC_API_KEY="${{ secrets.ANTHROPIC_API_KEY }}"
result=$(claude -p "$(cat prompt.md)" --output-format json | jq -r '.result')
```

**Alternatives rejected**:
- Direct Anthropic REST API via curl — works but lacks file-reading context that Claude Code provides natively
- Actions-specific Anthropic SDK — no official GitHub Action exists; CLI is the canonical path

---

## 2. Review Agent — OpenAI gpt-4o

**Decision**: Use OpenAI `gpt-4o` via `https://api.openai.com/v1/chat/completions` with `OPENAI_API_KEY`.

**Rationale**: The cross-agent review principle is preserved: Claude generates, OpenAI reviews. Previously Kimi K2.5 was used via Gcore's inference API; switched to OpenAI gpt-4o after Kimi access was discontinued. The curl pattern is identical (URL, model name, and auth header change; everything else stays the same).

**Pattern**:
```bash
review_output=$(curl -s https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "$(jq -n --arg prompt "$REVIEW_PROMPT" \
    '{"model":"gpt-4o","messages":[{"role":"user","content":$prompt}],"temperature":0}')" \
  | jq -r '.choices[0].message.content')
```

**Agent dispatch**: `sources.json` `reviewer_agent` field governs which agent is selected per repo. `invoke-agent.sh` dispatches to the correct API. Adding a new reviewer requires implementing its invocation branch in that script.

**Alternatives rejected**:
- Kimi K2.5 via Gcore API (previous choice — access discontinued)
- GitHub Copilot API (not publicly available for programmatic invocation)
- Gemini API (viable as future reviewer option, same abstraction)

---

## 3. PR Create-or-Update Pattern

**Decision**: Use `gh pr list --head <branch>` to check existence, then `gh pr create` or `gh pr edit` conditionally.

**Rationale**: `gh pr create` fails with an error if a PR already exists on the branch. The check-then-act pattern is the standard workaround documented in gh CLI best practices.

**Pattern**:
```bash
PR_NUM=$(gh pr list --head "$BRANCH_NAME" --json number -q '.[0].number')
if [ -z "$PR_NUM" ]; then
  gh pr create --title "$TITLE" --body "$BODY" --label "auto-ref-update"
else
  gh pr edit "$PR_NUM" --body "$BODY"
  gh pr comment "$PR_NUM" --body "$REVIEW_COMMENT"
fi
```

**Labels required**: `auto-ref-update` and `needs-review` must be pre-created in the repo.

---

## 4. Sparse Checkout — Path Anchoring Strategy

**Decision**: Use `git sparse-checkout init --no-cone` with root-anchored paths (prefixed with `/`).

**Rationale**: In no-cone mode, patterns without a leading `/` match at any depth. Each path from `sources.json` is prefixed with `/` before passing to `git sparse-checkout set` so that `src/` matches only the top-level `src/`, not `nested/src/`.

Non-cone mode is chosen over cone mode because `sources.json` sparse paths include individual files (e.g., `README.md`) which cone mode cannot express.

**Pattern**:
```bash
gh repo clone "$REPO_URL" "$CHECKOUT_DIR" -- \
  --filter=blob:none --no-checkout --depth 1 --branch "$RESOLVED_REF"

cd "$CHECKOUT_DIR"
git sparse-checkout init --no-cone
git sparse-checkout set "${ANCHORED_PATHS[@]}"   # each path prefixed with /
git checkout
```

**Why `gh repo clone`** (not raw `git clone`):
1. **Token safety** — `gh` uses its own credential store; the token never appears in the git remote URL, reflog, process list, or CI logs
2. **Consistency** — `gh` CLI is already a declared primary dependency (pre-installed on `ubuntu-latest`)

**Alternatives rejected**:
- `git clone` with `x-access-token` URL — token leakage risk in git internals and CI logs
- `actions/checkout` with `sparse-checkout` option — only works for the workflow's own repo, not external repos
- Full clone — rejected per Constitution Principle XI
- Cone mode — cannot express file-level paths

---

## 5. Baseline Tracking — Annotated Git Tags

**Decision**: Use one annotated git tag per source repo, force-updated in the plugin repo after each successful run. Tag naming: `refs/tags/ref-update/<repo-id>`.

**Rationale**: Baseline tracking needs to persist across workflow runs without requiring a commit to any branch. A committed file (e.g., `ref-baselines.json`) would need to go somewhere — `main` is protected, and the PR branch would pollute the PR diff with unrelated baseline commits. Git tags are branchless and atomic: `git push origin --force refs/tags/ref-update/<repo-id>` records the new baseline without touching any branch. Tag pushes are also safe under concurrent runs (last writer wins, which is acceptable — both runs processed the same commit).

**Tag message format** (single line, pipe-delimited):
```
<ref> | <commit-sha> | <processed_at-ISO8601>
```

**Alternatives rejected**:
- `ref-baselines.json` committed to a branch — no clean branch; pollutes PR diffs; race condition risk
- GitHub Actions cache — evictable, not reliable for permanent state
- Repository variables — not designed for frequently-updated per-repo structured data
- One tag per processed commit (append-only) — tags accumulate indefinitely; requires querying/sorting

---

## 6. Workflow Triggers — Manual + Repository Dispatch

**Decision**: Support `workflow_dispatch` (manual CLI or GitHub UI) and `repository_dispatch` with `event_type: "fastedge-ref-update"`.

**Rationale**: The spec requires both manual CLI invocation and webhook triggers from source repos. `workflow_dispatch` provides the manual path. `repository_dispatch` is the GitHub-native mechanism for cross-repo webhooks — source repos send the event on release, filtered by `event_type` to avoid unintended triggers.

When triggered by `repository_dispatch`, the workflow processes only the repo identified in `client_payload.source_repo_id`. When triggered by `workflow_dispatch`, it processes all repos in `sources.json` (or a single named one).

---

## 7. Fail-Visible Strategy (Principle XII)

**Decision**: Use a staging directory pattern — all file writes go to a temp directory first. Only after ALL steps for a repo succeed are files moved to `plugins/`. If any step fails, `exit 1` is called before any write to `plugins/`.

**Rationale**: This implements "no partial updates" from Principle XII.

**Principle XII vs US3 reconciliation**: The `exit 1` is scoped to the per-repo processing function. The top-level workflow loop catches the non-zero exit, records the failure in the run summary (`$GITHUB_STEP_SUMMARY`), and continues to the next repo. This satisfies both:
- **Principle XII** (no partial writes to `plugins/`) — governs file atomicity within a single repo's processing
- **US3 / FR-005** (individual repo failure must not block others) — governs pipeline resilience across repos

The two principles operate at different scopes.

**Alternatives rejected**:
- Write files then revert on failure — more complex, risks edge cases where revert also fails
- Separate git worktree — more isolation but adds complexity for a single-script flow

---

## 8. Docs-Index Staging — Reference Files First

**Decision**: In `write_and_push()`, stage reference markdown files and check for changes *before* regenerating `docs-index.json`. Only regenerate and stage the index when reference content actually changed.

**Rationale**: `docs-index.json` contains a `generated_at` timestamp that changes on every run. If the index is staged alongside the reference files *before* the no-changes check (`git diff --cached --quiet`), the timestamp diff defeats the early-exit — producing a commit even when no reference content changed. By checking reference file diffs first, the early-exit works correctly and `generated_at` only updates when content actually changed.

**Pattern** (in `write_and_push()`):
```bash
# 1. Stage reference files only
git add -- $CHANGED_FILES

# 2. Check for actual content changes
if git diff --cached --quiet; then
  return 2  # no net changes
fi

# 3. Only regenerate docs-index when content changed
bash generate-docs-index.sh
git add -- "$docs_index_file"
```

**Alternatives rejected**:
- Removing `generated_at` — loses audit/debugging value
- Making `generated_at` deterministic (e.g., from source commit) — adds coupling for marginal benefit
- Diffing the JSON payload ignoring metadata fields — more complex than reordering the staging

---

## Constitution Compliance Check

Verified during design phase. All 15 principles pass.

### Principles I–V (Core Plugin Principles)

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Skill-First Design | Pass | Pipeline is CI/CD infrastructure, not plugin skill logic |
| II. Delegate, Don't Duplicate | Pass | Reads source repos and writes reference files; no duplication |
| III. Scope Boundary | Pass | Write scope restricted to `plugins/` (Principle X) |
| IV. Clarify Before Acting | Pass | Not applicable — automated infrastructure, not user-interactive |
| V. Knowledge Base Integrity | Pass | Pipeline IS the mechanism to keep the knowledge base current; PR-gated human review prevents incorrect content |

### Principles VI–XV (Reference Material Automation)

| Principle | Status | Notes |
|-----------|--------|-------|
| VI. PR-Gated | Pass | All changes go through a PR. Workflow never merges. |
| VII. One PR Per Source Repo | Pass | Branch naming `auto-ref-update/<repo-id>` enforces one-PR-per-repo |
| VIII. Cross-Agent Review | Pass | `generator_agent !== reviewer_agent` enforced by sources.json validation |
| IX. sources.json is Law | Pass | Only repos and paths listed in `sources.json` are fetched |
| X. Write Scope — plugins/ Only | Pass | Validation rule enforces `reference_file` starts with `plugins/`; script double-checks at write time |
| XI. Sparse Checkout | Pass | `--sparse --filter=blob:none --depth 1`. No full clone fallback — failure instead |
| XII. Fail Visibly | Pass | Staging directory pattern: no `plugins/` writes until all steps succeed |
| XIII. Reference Docs Are for Agents | Pass | Generator prompt: precise API signatures, parameter types, concrete examples, no vague summaries |
| XIV. GitHub CLI for All GitHub API Calls | Pass | All scripts use `gh api` and `gh repo clone`. No `curl` calls to api.github.com |
| XV. Version Traceability | Pass | Generator writes traceability frontmatter. Reviewer validates it. Missing block = review blocker |
