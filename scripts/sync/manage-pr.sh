#!/usr/bin/env bash
set -euo pipefail

# manage-pr.sh — Create or update the reference docs PR for a source repo.
#
# Uses a stable branch name auto-ref-update/<repo-id> so re-runs update the
# same PR rather than opening a new one.
#
# Usage:
#   manage-pr.sh \
#     --repo-id     <id>           sources.json repo identifier
#     --ref         <ref>          resolved ref (e.g. v2.1.0)
#     --commit      <sha>          full HEAD commit SHA from fetch-repo.sh
#     --changed-files <list>       space-separated list of reference files updated
#     --verdict     ACCEPT|REJECT  reviewer verdict from invoke-agent.sh
#     --findings    <text>         verbatim reviewer findings (may be multi-line)
#
# Exit codes:
#   0  success (PR created or updated)
#   1  any error (bad args, gh CLI failure, missing label, etc.)

# ── Argument parsing ──────────────────────────────────────────────────────────

REPO_ID=""
REF=""
COMMIT=""
CHANGED_FILES=""
VERDICT=""
FINDINGS=""
BASE_BRANCH=""
MISSING_INTENT="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-id)       REPO_ID="$2";       shift 2 ;;
    --ref)           REF="$2";           shift 2 ;;
    --commit)        COMMIT="$2";        shift 2 ;;
    --changed-files) CHANGED_FILES="$2"; shift 2 ;;
    --verdict)       VERDICT="$2";       shift 2 ;;
    --findings)      FINDINGS="$2";      shift 2 ;;
    --missing-intent) MISSING_INTENT="$2"; shift 2 ;;
    --base)          BASE_BRANCH="$2";   shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────

missing=()
[[ -z "$REPO_ID" ]]       && missing+=(--repo-id)
[[ -z "$REF" ]]           && missing+=(--ref)
[[ -z "$COMMIT" ]]        && missing+=(--commit)
[[ -z "$CHANGED_FILES" ]] && missing+=(--changed-files)
[[ -z "$VERDICT" ]]       && missing+=(--verdict)
[[ -z "$FINDINGS" ]]      && missing+=(--findings)

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Missing required arguments: ${missing[*]}" >&2
  exit 1
fi

if [[ "$VERDICT" != "ACCEPT" && "$VERDICT" != "REJECT" ]]; then
  echo "ERROR: --verdict must be ACCEPT or REJECT, got: $VERDICT" >&2
  exit 1
fi

# ── Label pre-check / create ──────────────────────────────────────────────────
# Ensure required labels exist so gh pr create/edit never fails on label-not-found.
# (This logic is also required by T017, but is safe to run here for T009 correctness.)

ensure_label() {
  local label_name="$1"
  local label_color="$2"

  if ! gh label list --json name -q '.[].name' 2>/dev/null | grep -qF "$label_name"; then
    echo "INFO: Creating label '$label_name'" >&2
    gh label create "$label_name" --color "$label_color" --description "" 2>/dev/null || {
      echo "WARN: Could not create label '$label_name' — continuing anyway" >&2
    }
  fi
}

ensure_label "auto-ref-update"      "0075ca"
ensure_label "needs-review"          "d93f0b"
ensure_label "missing-intent-skill"  "e4e669"

# ── Build PR body ─────────────────────────────────────────────────────────────

# Format the changed-files list as markdown bullets
changed_files_md=""
for f in $CHANGED_FILES; do
  changed_files_md+="- \`${f}\`"$'\n'
done

# Determine source GitHub URL from sources.json (best effort — fallback to repo-id)
SOURCE_URL=""
if [[ -f "sources.json" ]]; then
  SOURCE_URL=$(jq -r --arg id "$REPO_ID" \
    '.repos[] | select(.id == $id) | .github_url' sources.json 2>/dev/null || true)
fi
SOURCE_URL="${SOURCE_URL:-https://github.com/(see sources.json: ${REPO_ID})}"

# ── Format findings as a table ──────────────────────────────────────────────

_flush_findings_entry() {
  # Called by build_findings_table to emit one table row + optional details.
  # Reads/writes: current_file, current_verdict, current_comments,
  #               _ft_table_rows, _ft_details  (all in caller scope)
  [[ -z "$current_file" ]] && return
  local icon
  [[ "$current_verdict" == "ACCEPT" ]] && icon="✅" || icon="❌"

  # Trim leading/trailing blank lines from comments
  current_comments="$(printf '%s\n' "$current_comments" | sed '/./,$!d' | tac | sed '/./,$!d' | tac)"

  if [[ -z "$current_comments" || "$current_comments" == "None." ]]; then
    _ft_table_rows+="| \`${current_file}\` | ${icon} | — |"$'\n'
    return
  fi

  if [[ "$current_verdict" == "REJECT" ]]; then
    # Count non-empty lines as issue count
    local issue_count
    issue_count=$(printf '%s\n' "$current_comments" | grep -c '.' || true)
    local summary
    if [[ "$issue_count" -eq 1 ]]; then
      summary="1 issue — see details"
    else
      summary="${issue_count} issues — see details"
    fi

    _ft_table_rows+="| \`${current_file}\` | ${icon} | ${summary} |"$'\n'
    _ft_details+=$'\n'"<details>"$'\n'"<summary>${icon} <code>${current_file}</code></summary>"$'\n\n'
    _ft_details+="${current_comments}"$'\n\n'
    _ft_details+="</details>"$'\n'
  else
    # ACCEPT with comments (rare) — single-line in table
    local NL=$'\n'
    local oneline="${current_comments//${NL}/ }"
    oneline="${oneline//|/\\|}"
    _ft_table_rows+="| \`${current_file}\` | ${icon} | ${oneline} |"$'\n'
  fi
}

build_findings_table() {
  local findings="$1" overall_verdict="$2"
  local verdict_icon
  [[ "$overall_verdict" == "ACCEPT" ]] && verdict_icon="✅" || verdict_icon="❌"

  _ft_table_rows=""
  _ft_details=""
  local current_file="" current_verdict="" current_comments=""
  local NL=$'\n'

  while IFS= read -r line; do
    if [[ "$line" =~ ^\*\*(.+)\*\*:\ (ACCEPT|REJECT)$ ]]; then
      _flush_findings_entry
      current_file="${BASH_REMATCH[1]}"
      current_verdict="${BASH_REMATCH[2]}"
      current_comments=""
    elif [[ -n "$current_file" ]]; then
      # Preserve line breaks — append with newline (skip leading blank lines)
      if [[ -n "$line" || -n "$current_comments" ]]; then
        current_comments="${current_comments:+${current_comments}${NL}}${line}"
      fi
    fi
  done <<< "$findings"
  _flush_findings_entry

  printf '%s **%s** verdict from reviewer agent:\n\n' "$verdict_icon" "$overall_verdict"

  if [[ -z "$_ft_table_rows" ]]; then
    # No per-file headers parsed — show raw findings as-is
    printf '<details>\n<summary>Reviewer Findings</summary>\n\n'
    printf '%s\n' "$findings"
    printf '\n</details>\n'
    return
  fi

  printf '| File | Status | Comments |\n'
  printf '|------|--------|----------|\n'
  printf '%s' "$_ft_table_rows"
  if [[ -n "$_ft_details" ]]; then
    printf '\n### Reviewer Details\n'
    printf '%s' "$_ft_details"
  fi
}

FINDINGS_TABLE="$(build_findings_table "$FINDINGS" "$VERDICT")"

PR_BODY="## Source
- Repo: ${SOURCE_URL}
- Ref: ${REF}
- Commit: \`${COMMIT}\`

## Changes
${changed_files_md}
## Review Agent Findings
${FINDINGS_TABLE}

---
_Generated by sync-reference-docs workflow. Do not edit this PR body manually._"

# ── Branch and PR management ──────────────────────────────────────────────────

BRANCH="auto-ref-update/${REPO_ID}"
PR_TITLE="auto: update reference docs from ${REPO_ID} (${REF})"

# Check for existing open PR on this branch
EXISTING_PR_NUMBER=$(gh pr list \
  --head "$BRANCH" \
  --state open \
  --json number \
  -q '.[0].number' 2>/dev/null || echo "")

if [[ -z "$EXISTING_PR_NUMBER" ]]; then
  echo "INFO: Creating new PR for branch ${BRANCH}" >&2

  gh pr create \
    --head "$BRANCH" \
    --base "${BASE_BRANCH:-main}" \
    --title "$PR_TITLE" \
    --label "auto-ref-update" \
    --body "$PR_BODY" >&2

  # Re-fetch PR number after creation
  EXISTING_PR_NUMBER=$(gh pr list \
    --head "$BRANCH" \
    --state open \
    --json number \
    -q '.[0].number' 2>/dev/null || echo "")
else
  echo "INFO: Updating existing PR #${EXISTING_PR_NUMBER} for branch ${BRANCH}" >&2

  gh pr edit "$EXISTING_PR_NUMBER" \
    --title "$PR_TITLE" \
    --body "$PR_BODY"
fi

# ── Verdict-based label management ────────────────────────────────────────────

if [[ -n "$EXISTING_PR_NUMBER" ]]; then
  if [[ "$VERDICT" == "REJECT" ]]; then
    echo "INFO: Verdict is REJECT — adding needs-review label to PR #${EXISTING_PR_NUMBER}" >&2
    gh pr edit "$EXISTING_PR_NUMBER" --add-label "needs-review" 2>/dev/null || {
      echo "WARN: Could not add needs-review label" >&2
    }
  else
    # ACCEPT: remove needs-review if present
    existing_labels=$(gh pr view "$EXISTING_PR_NUMBER" --json labels \
      -q '.labels[].name' 2>/dev/null || echo "")
    if echo "$existing_labels" | grep -qF "needs-review"; then
      echo "INFO: Verdict is ACCEPT — removing needs-review label from PR #${EXISTING_PR_NUMBER}" >&2
      gh pr edit "$EXISTING_PR_NUMBER" --remove-label "needs-review" 2>/dev/null || {
        echo "WARN: Could not remove needs-review label" >&2
      }
    fi
  fi

  # missing-intent-skill label management
  if [[ "$MISSING_INTENT" == "true" ]]; then
    echo "INFO: Missing intent skills detected — adding missing-intent-skill label to PR #${EXISTING_PR_NUMBER}" >&2
    gh pr edit "$EXISTING_PR_NUMBER" --add-label "missing-intent-skill" 2>/dev/null || {
      echo "WARN: Could not add missing-intent-skill label" >&2
    }
  else
    existing_labels=$(gh pr view "$EXISTING_PR_NUMBER" --json labels \
      -q '.labels[].name' 2>/dev/null || echo "")
    if echo "$existing_labels" | grep -qF "missing-intent-skill"; then
      echo "INFO: All intent skills present — removing missing-intent-skill label from PR #${EXISTING_PR_NUMBER}" >&2
      gh pr edit "$EXISTING_PR_NUMBER" --remove-label "missing-intent-skill" 2>/dev/null || {
        echo "WARN: Could not remove missing-intent-skill label" >&2
      }
    fi
  fi
fi

echo "INFO: PR management complete for ${REPO_ID} (${VERDICT})" >&2

# Always emit the PR URL to stdout so callers (process-repos.sh) can capture it.
if [[ -n "$EXISTING_PR_NUMBER" ]]; then
  gh pr view "$EXISTING_PR_NUMBER" --json url -q .url
fi
