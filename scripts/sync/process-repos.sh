#!/usr/bin/env bash
set -uo pipefail

# process-repos.sh — Main pipeline loop for sync-reference-docs.yml.
#
# Reads sources.json (v2), fetches each eligible source repo's contract directory,
# reads manifest.json for target_mapping, runs generator and reviewer agents,
# writes updated reference files, opens/updates PRs, and records baseline tags.
#
# Environment variables (all required when called from GitHub Actions):
#   DRY_RUN          "true" to skip file writes, PRs, and baseline updates
#   FILTER_REPO_ID   if set, process only this repo ID (ignores trigger field)
#   FORCE_RUN        "true" to process a repo even when no new commits exist
#                    since the last baseline tag (bypasses the up-to-date check)
#   SOURCES_FILE     path to sources.json (default: sources.json); overridable
#                    for testing without modifying the real config file
#   GITHUB_STEP_SUMMARY  path to Actions step summary file (set by runner)
#   ANTHROPIC_API_KEY    passed through to invoke-agent.sh (generator)
#   OPENAI_API_KEY       passed through to invoke-agent.sh (reviewer)
#
# Usage:
#   bash scripts/sync/process-repos.sh
#
# Sourcing: when sourced as a library (BASH_SOURCE != $0), only functions are
# defined — no execution occurs. Used by test-process-repos.sh for unit tests.
#
# Exit codes:
#   0  all processed repos succeeded (or were legitimately skipped)
#   1  one or more repos failed; see output for details

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source fetch-repo.sh as a library to get write_baseline_tag() and friends.
# shellcheck source=./fetch-repo.sh
source "${SCRIPT_DIR}/fetch-repo.sh"
# Source validate-contract.sh as a library to get validate_contract().
# shellcheck source=./validate-contract.sh
source "${SCRIPT_DIR}/validate-contract.sh"
set +e

# ── Environment defaults ──────────────────────────────────────────────────────

DRY_RUN="${DRY_RUN:-false}"
FORCE_RUN="${FORCE_RUN:-false}"
FILTER_REPO_ID="${FILTER_REPO_ID:-}"
SOURCES_FILE="${SOURCES_FILE:-sources.json}"
STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# T015: repository_dispatch payload fields (empty outside dispatch context)
DISPATCH_REF="${DISPATCH_REF:-}"
DISPATCH_TRIGGER="${DISPATCH_TRIGGER:-}"

# Staging and checkout dirs live in RUNNER_TEMP when in Actions; /tmp locally
_TMPBASE="${RUNNER_TEMP:-/tmp}"
STAGING_BASE="${_TMPBASE}/sync-staging"
CHECKOUT_BASE="${_TMPBASE}/sync-checkout"

# ── Helpers ───────────────────────────────────────────────────────────────────

# verdict_icon ACCEPT|REJECT → emoji
verdict_icon() {
  [[ "$1" == "ACCEPT" ]] && echo "✅" || echo "⚠️"
}

# ── Per-repo processing functions ────────────────────────────────────────────

# fetch_repo <index> → sets RESOLVED_REF, COMMIT, CHANGED
fetch_repo() {
  local idx="$1"
  local repo_url contract_path repo_id ref checkout_dir

  repo_url=$(jq -r ".repos[$idx].github_url" "$SOURCES_FILE")
  contract_path=$(jq -r ".repos[$idx].contract_path" "$SOURCES_FILE")
  repo_id=$(jq -r ".repos[$idx].id" "$SOURCES_FILE")
  # T015: use DISPATCH_REF when set (repository_dispatch override)
  ref="${DISPATCH_REF:-$(jq -r ".repos[$idx].ref" "$SOURCES_FILE")}"
  checkout_dir="${CHECKOUT_BASE}/${repo_id}"

  local fetch_output
  fetch_output=$(bash "${SCRIPT_DIR}/fetch-repo.sh" \
    --repo-url       "$repo_url" \
    --contract-path  "$contract_path" \
    --repo-id        "$repo_id" \
    --ref            "$ref" \
    --checkout-dir   "$checkout_dir") || return 1

  # Parse KEY=VALUE pairs from fetch-repo.sh stdout
  RESOLVED_REF="" COMMIT="" CHANGED=""
  while IFS='=' read -r key value; do
    case "$key" in
      CHANGED)      CHANGED="$value" ;;
      RESOLVED_REF) RESOLVED_REF="$value" ;;
      COMMIT)       COMMIT="$value" ;;
    esac
  done <<< "$fetch_output"
}

# read_manifest <checkout-dir> <contract-path>
# Reads manifest.json from the fetched contract directory.
# Sets MANIFEST_FILE on success, returns 1 on failure.
read_manifest() {
  local checkout_dir="$1" contract_path="$2"
  MANIFEST_FILE="${checkout_dir}/${contract_path}manifest.json"

  if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo "ERROR: manifest.json not found at ${MANIFEST_FILE}" >&2
    return 1
  fi

  if ! jq empty "$MANIFEST_FILE" 2>/dev/null; then
    echo "ERROR: manifest.json is not valid JSON at ${MANIFEST_FILE}" >&2
    return 1
  fi
}

# run_agents <repo-index> <staging-dir> <checkout-dir>
# Reads target_mapping from manifest.json, then for each mapping entry:
# resolves source files from the sources field, invokes generator then reviewer
# in parallel (up to MAX_PARALLEL concurrent entries).
# Writes gen-N.md, rev-N.txt, result-N.txt, combined-findings.txt to staging-dir.
# Sets CHANGED_FILES and OVERALL_VERDICT on success; returns 1 on failure.
run_agents() {
  local idx="$1" staging_dir="$2" checkout_dir="$3"
  local repo_id contract_path intent_dir

  repo_id=$(jq -r ".repos[$idx].id" "$SOURCES_FILE")
  contract_path=$(jq -r ".repos[$idx].contract_path" "$SOURCES_FILE")
  intent_dir=$(jq -r ".repos[$idx].intent_dir" "$SOURCES_FILE")

  local manifest_file="${checkout_dir}/${contract_path}manifest.json"

  CHANGED_FILES=""
  OVERALL_VERDICT="ACCEPT"
  MISSING_INTENT=false
  local findings_file="${staging_dir}/combined-findings.txt"
  > "$findings_file"

  local mapping_count
  mapping_count=$(jq '.target_mapping | length' "$manifest_file")

  # Resolve sources.json directory once — used by every subshell for intent lookup
  local sources_dir
  sources_dir="$(cd "$(dirname "$SOURCES_FILE")" && pwd)"

  local MAX_PARALLEL="${MAX_PARALLEL:-16}"
  if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: MAX_PARALLEL must be a positive integer; got '${MAX_PARALLEL}'" >&2
    return 1
  fi
  echo "INFO: Processing ${mapping_count} target_mapping entries for ${repo_id} (parallel, cap=${MAX_PARALLEL})" >&2

  # Read all entries into arrays before launching so each subshell gets a
  # pre-assigned unique index. Dynamic index assignment after fork would race.
  local -a entry_keys=() entry_refs=() entry_sections=()
  while IFS=$'\t' read -r source_key reference_file section; do
    entry_keys+=("$source_key")
    entry_refs+=("$reference_file")
    entry_sections+=("$section")
  done < <(jq -r '.target_mapping | to_entries[] | [.key, .value.reference_file, (.value.section // "null")] | @tsv' "$manifest_file")

  local running=0
  local -a launched_pids=()

  local j
  for ((j = 0; j < mapping_count; j++)); do
    local source_key="${entry_keys[$j]}"
    local reference_file="${entry_refs[$j]}"
    local section="${entry_sections[$j]}"
    local entry_num=$((j + 1))

    # Throttle: block until a slot is free before launching the next subshell.
    # wait -n (bash 4.3+) reaps any job; older bash falls back to the oldest PID.
    while [[ $running -ge $MAX_PARALLEL ]]; do
      if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
        wait -n 2>/dev/null || true
      else
        # Fallback for older bash: wait for the oldest launched PID.
        wait "${launched_pids[0]}" 2>/dev/null || true
        launched_pids=("${launched_pids[@]:1}")
      fi
      running=$((running - 1))
    done

    # Each subshell writes only to its own uniquely-indexed files.
    # No shared mutable state between subshells.
    (
      local gen_output="${staging_dir}/gen-${entry_num}.md"
      local rev_output="${staging_dir}/rev-${entry_num}.txt"
      local result_file="${staging_dir}/result-${entry_num}.txt"

      [[ "$section" == "null" ]] && section=""

      echo "INFO: [${entry_num}/${mapping_count}] Starting '${source_key}' → ${reference_file}" >&2

      # Resolve source files — fail fast if missing, before any API call
      local source_files_list
      source_files_list=$(jq -r --arg k "$source_key" \
        '.sources[$k].files // [] | .[]' "$manifest_file" 2>/dev/null)

      if [[ -z "$source_files_list" ]]; then
        echo "ERROR: No source files resolved for mapping key '${source_key}' — check manifest.json .sources[\"${source_key}\"].files" >&2
        echo "FAILED=1" >> "$result_file"
        exit 1
      fi

      # Resolve intent file
      local ref_suffix="${reference_file##*reference/}"
      local candidate="${intent_dir}${ref_suffix}"
      local intent_file=""
      if [[ -f "${sources_dir}/${candidate}" ]]; then
        intent_file="$candidate"
      else
        echo -e "\033[33m[WARNING] No agent-intent-skill found for '${source_key}' → ${reference_file} (looked for: ${candidate})\033[0m" >&2
        echo "MISSING_INTENT=true" >> "$result_file"
      fi

      local section_args=() intent_args=() source_files_args=()
      [[ -n "$section" ]]           && section_args=(--section "$section")
      [[ -n "$intent_file" ]]       && intent_args=(--intent-file "$intent_file")
      [[ -n "$source_files_list" ]] && source_files_args=(--source-files "$source_files_list")

      bash "${SCRIPT_DIR}/invoke-agent.sh" \
        --role generator \
        "${section_args[@]}" \
        "${intent_args[@]}" \
        "${source_files_args[@]}" \
        --reference-file "$reference_file" \
        --source-dir     "$checkout_dir" \
        --repo-id        "$repo_id" \
        --ref            "$RESOLVED_REF" \
        --commit         "$COMMIT" \
        --output-file    "$gen_output" < /dev/null || {
          echo "ERROR: Generator failed for '${source_key}'" >&2
          echo "FAILED=1" >> "$result_file"
          exit 1
        }

      bash "${SCRIPT_DIR}/invoke-agent.sh" \
        --role reviewer \
        --input-file     "$gen_output" \
        --source-dir     "$checkout_dir" \
        "${source_files_args[@]}" \
        --output-file    "$rev_output" < /dev/null || {
          echo "ERROR: Reviewer failed for '${source_key}'" >&2
          echo "FAILED=1" >> "$result_file"
          exit 1
        }

      local verdict
      verdict=$(head -1 "$rev_output" | sed 's/^VERDICT=//')
      {
        echo "VERDICT=${verdict}"
        echo "CHANGED=${reference_file}"
      } >> "$result_file"

      echo "INFO: [${entry_num}/${mapping_count}] Done '${source_key}' → ${reference_file} (${verdict})" >&2
    ) &

    launched_pids+=($!)
    running=$((running + 1))
  done

  # Drain all remaining background jobs before reading result files
  local pid
  for pid in "${launched_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Collect results in original entry order — all subshells have exited, no races
  local overall_failed=0
  for ((j = 0; j < mapping_count; j++)); do
    local entry_num=$((j + 1))
    local result_file="${staging_dir}/result-${entry_num}.txt"
    local rev_output="${staging_dir}/rev-${entry_num}.txt"
    local reference_file="${entry_refs[$j]}"
    local section="${entry_sections[$j]}"
    [[ "$section" == "null" ]] && section=""

    if [[ ! -f "$result_file" ]] || grep -q "^FAILED=1" "$result_file"; then
      overall_failed=1
      continue
    fi

    grep -q "^MISSING_INTENT=true" "$result_file" && MISSING_INTENT=true

    local entry_verdict
    entry_verdict=$(grep "^VERDICT=" "$result_file" | head -1 | sed 's/^VERDICT=//')
    [[ "$entry_verdict" == "REJECT" ]] && OVERALL_VERDICT="REJECT"

    local changed
    changed=$(grep "^CHANGED=" "$result_file" | head -1 | sed 's/^CHANGED=//')
    CHANGED_FILES="${CHANGED_FILES:+${CHANGED_FILES} }${changed}"

    if [[ -f "$rev_output" ]]; then
      local entry_findings
      entry_findings=$(tail -n +3 "$rev_output")
      {
        echo "**${reference_file}${section:+ / ${section}}**: ${entry_verdict}"
        echo ""
        echo "$entry_findings"
        echo ""
      } >> "$findings_file"
    fi
  done

  [[ "$overall_failed" -eq 1 ]] && return 1
  return 0
}

# write_and_push <staging-dir> <manifest-file>
# Creates/resets the PR branch, splices or copies each staged file,
# commits, and force-pushes. Returns 1 on any failure; restores
# the default branch before returning. Returns 2 when git diff
# shows no net changes (content already current — not an error).
write_and_push() {
  local staging_dir="$1" manifest_file="$2"
  local pr_branch
  pr_branch="auto-ref-update/${REPO_ID}"

  git checkout -B "$pr_branch"

  local j=0 failed=0
  while IFS=$'\t' read -r _ reference_file section; do
    [[ "$section" == "null" ]] && section=""
    j=$((j + 1))
    local gen_output="${staging_dir}/gen-${j}.md"

    if [[ -n "$section" ]]; then
      bash "${SCRIPT_DIR}/invoke-agent.sh" \
        --role           splice \
        --reference-file "$reference_file" \
        --section        "$section" \
        --input-file     "$gen_output" \
        --repo-id        "$REPO_ID" \
        --ref            "$RESOLVED_REF" \
        --commit         "$COMMIT" < /dev/null || { failed=1; break; }
    else
      mkdir -p "$(dirname "$reference_file")"
      if ! cp "$gen_output" "$reference_file"; then
        echo "ERROR: Failed to copy ${gen_output} → ${reference_file}" >&2
        failed=1; break
      fi
    fi
  done < <(jq -r '.target_mapping | to_entries[] | [.key, .value.reference_file, (.value.section // "null")] | @tsv' "$manifest_file")

  if [[ "$failed" -eq 1 ]]; then
    git checkout "$DEFAULT_BRANCH"
    return 1
  fi

  # Stage reference files and check whether content actually changed.
  # docs-index.json is regenerated separately by the release workflow.
  # shellcheck disable=SC2086
  git add -- $CHANGED_FILES

  if git diff --cached --quiet; then
    echo "INFO: No net changes to commit for ${REPO_ID} (content already current)"
    git checkout "$DEFAULT_BRANCH"
    return 2  # signal: skipped — not an error
  fi

  git commit -m "auto: update reference docs from ${REPO_ID} (${RESOLVED_REF})"
  git push --force origin "$pr_branch"
  git checkout "$DEFAULT_BRANCH"
}

# open_or_update_pr <staging-dir>
# Calls manage-pr.sh and captures the PR URL to PR_URL.
open_or_update_pr() {
  local findings_file="${1}/combined-findings.txt"
  local combined_findings
  combined_findings=$(cat "$findings_file")

  PR_URL=$(bash "${SCRIPT_DIR}/manage-pr.sh" \
    --repo-id       "$REPO_ID" \
    --ref           "$RESOLVED_REF" \
    --commit        "$COMMIT" \
    --changed-files "$CHANGED_FILES" \
    --verdict       "$OVERALL_VERDICT" \
    --findings      "$combined_findings" \
    --missing-intent "$MISSING_INTENT" \
    --base          "$DEFAULT_BRANCH") || {
    echo "WARN: manage-pr.sh failed for ${REPO_ID} — PR may need manual attention" >&2
    PR_URL="(pr error)"
  }
}

# ── T014: Per-repo isolation helpers ─────────────────────────────────────────

_FAILURE_REASON=""

record_failure() {
  local repo_id="$1" exit_code="${2:-1}"
  local reason="${_FAILURE_REASON:-unexpected error (exit ${exit_code})}"
  _FAILURE_REASON=""
  echo "ERROR: Failed processing ${repo_id}: ${reason}" >&2
  SUMMARY_ROWS+="| ${repo_id} | ❌ failed | — | ${reason} |"$'\n'
  OVERALL_FAILED=1
}

# process_repo REPO_ID
# Runs the complete pipeline for one source repo in isolation.
process_repo() {
  REPO_ID="$1"

  local idx
  idx=$(jq -r --arg id "$REPO_ID" '.repos | to_entries[] | select(.value.id == $id) | .key' "$SOURCES_FILE")

  local TRIGGER
  TRIGGER=$(jq -r ".repos[$idx].trigger" "$SOURCES_FILE")

  # ── Filter: which repos are eligible for this trigger ────────────────────
  if [[ -n "$FILTER_REPO_ID" ]]; then
    [[ "$REPO_ID" != "$FILTER_REPO_ID" ]] && return 0
  else
    if [[ "$TRIGGER" != "schedule" && "$TRIGGER" != "both" ]]; then
      echo "INFO: Skipping ${REPO_ID} (trigger=${TRIGGER})"
      SUMMARY_ROWS+="| ${REPO_ID} | ⏭ skipped | — | trigger=${TRIGGER} |"$'\n'
      return 0
    fi
  fi

  echo "========================================"
  echo "Processing: ${REPO_ID}"

  local STAGING_DIR="${STAGING_BASE}/${REPO_ID}"
  local CHECKOUT_DIR="${CHECKOUT_BASE}/${REPO_ID}"
  local CONTRACT_PATH
  CONTRACT_PATH=$(jq -r ".repos[$idx].contract_path" "$SOURCES_FILE")
  mkdir -p "$STAGING_DIR"

  RESOLVED_REF="" COMMIT="" CHANGED=""
  CHANGED_FILES="" OVERALL_VERDICT="ACCEPT" PR_URL=""

  # ── Step 1: Fetch ─────────────────────────────────────────────────────────
  if ! fetch_repo "$idx"; then
    _FAILURE_REASON="fetch error"
    return 1
  fi

  if [[ "$CHANGED" != "true" ]]; then
    if [[ "$FORCE_RUN" == "true" ]]; then
      echo "INFO: No changes for ${REPO_ID} — proceeding anyway (force_run=true)" >&2
      CHANGED=true
    else
      echo "INFO: No changes for ${REPO_ID} — skipping"
      SUMMARY_ROWS+="| ${REPO_ID} | ⏭ skipped | ${RESOLVED_REF} | no changes |"$'\n'
      return 0
    fi
  fi

  # ── Step 1.5: Read and validate manifest ─────────────────────────────────
  MANIFEST_FILE=""
  if ! read_manifest "$CHECKOUT_DIR" "$CONTRACT_PATH"; then
    _FAILURE_REASON="manifest error"
    return 1
  fi

  # Validate contract (pass checkout dir as repo_root for file existence checks)
  local contract_dir="${CHECKOUT_DIR}/${CONTRACT_PATH}"
  if ! validate_contract "$contract_dir" "$CHECKOUT_DIR"; then
    _FAILURE_REASON="contract validation error"
    return 1
  fi

  # ── Step 2: Generate + review ─────────────────────────────────────────────
  if ! run_agents "$idx" "$STAGING_DIR" "$CHECKOUT_DIR"; then
    _FAILURE_REASON="agent error"
    return 1
  fi

  # ── dry_run gate ──────────────────────────────────────────────────────────
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "INFO: dry_run=true — skipping writes, PR, and baseline for ${REPO_ID}"
    SUMMARY_ROWS+="| ${REPO_ID} | 🔍 dry-run $(verdict_icon "$OVERALL_VERDICT") | ${RESOLVED_REF} | writes skipped |"$'\n'
    return 0
  fi

  # ── Step 3: Write + commit + push ─────────────────────────────────────────
  local write_rc=0
  write_and_push "$STAGING_DIR" "$MANIFEST_FILE" || write_rc=$?

  if [[ "$write_rc" -eq 1 ]]; then
    _FAILURE_REASON="write error"
    return 1
  fi

  if [[ "$write_rc" -eq 2 ]]; then
    SUMMARY_ROWS+="| ${REPO_ID} | ⏭ skipped | ${RESOLVED_REF} | no net changes |"$'\n'
    return 0
  fi

  # ── Step 4: Open / update PR ──────────────────────────────────────────────
  open_or_update_pr "$STAGING_DIR"

  # ── Step 5: Update baseline tag ───────────────────────────────────────────
  write_baseline_tag "$REPO_ID" "$RESOLVED_REF" "$COMMIT" || {
    echo "WARN: Failed to update baseline tag for ${REPO_ID}" >&2
  }

  SUMMARY_ROWS+="| ${REPO_ID} | $(verdict_icon "$OVERALL_VERDICT") PR | ${RESOLVED_REF} | ${PR_URL:-opened} |"$'\n'
  return 0
}

# ── Main ─────────────────────────────────────────────────────────────────────

_process_repos_main() {
  local PLUGIN_ROOT DEFAULT_BRANCH

  PLUGIN_ROOT="$(pwd)"
  DEFAULT_BRANCH="${TARGET_BRANCH:-$(git symbolic-ref --short HEAD)}"
  mkdir -p "$STAGING_BASE" "$CHECKOUT_BASE"

  git config user.email "fastedge-plugin-sync[bot]@users.noreply.github.com"
  git config user.name  "fastedge-plugin-sync[bot]"

  OVERALL_FAILED=0
  SUMMARY_ROWS=""

  # ── T015: Validate repository_dispatch payload ────────────────────────────
  if [[ "${DISPATCH_TRIGGER}" == "repository_dispatch" ]]; then
    if [[ -z "$FILTER_REPO_ID" ]]; then
      echo "ERROR: repository_dispatch missing source_repo_id in client_payload" >&2
      exit 1
    fi
    local _found
    _found=$(jq -r --arg id "$FILTER_REPO_ID" '.repos[] | select(.id == $id) | .id' "$SOURCES_FILE")
    if [[ -z "$_found" ]]; then
      echo "ERROR: repository_dispatch source_repo_id '${FILTER_REPO_ID}' not found in ${SOURCES_FILE}" >&2
      exit 1
    fi
  fi

  local REPO_COUNT
  REPO_COUNT=$(jq '.repos | length' "$SOURCES_FILE")

  local i
  for ((i = 0; i < REPO_COUNT; i++)); do
    REPO_ID=$(jq -r ".repos[$i].id" "$SOURCES_FILE")
    if ! process_repo "$REPO_ID"; then
      record_failure "$REPO_ID" "$?"
    fi
  done

  # ── Write step summary ────────────────────────────────────────────────────
  {
    echo "## Sync Reference Docs — Run Summary"
    echo ""
    echo "| Source Repo | Outcome | Ref | PR |"
    echo "|-------------|---------|-----|----|"
    printf '%s' "$SUMMARY_ROWS"
  } >> "$STEP_SUMMARY"

  if [[ "$OVERALL_FAILED" -eq 1 ]]; then
    echo "ERROR: One or more repos failed processing" >&2
    return 1
  fi
}

# ── Entry point ───────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _process_repos_main "$@"
fi
