#!/usr/bin/env bash
set -euo pipefail

# fetch-repo.sh — Sparse-clone a source repo's contract directory and detect changes
#
# Usage:
#   fetch-repo.sh --repo-url <url> --contract-path <path> --repo-id <id> \
#                 --ref <ref> --checkout-dir <dir>
#
# Arguments:
#   --repo-url       Full HTTPS URL to the GitHub repo (no trailing slash)
#   --contract-path  Path to the contract directory (e.g. "fastedge-plugin-source/")
#   --repo-id        Unique kebab-case repo identifier (matches sources.json id)
#   --ref            "latest-release", "main", or a tag like "vX.Y.Z"
#   --checkout-dir   Directory to clone into (created if absent, re-created if exists)
#
# Outputs (written to stdout, one per line, KEY=VALUE format):
#   CHANGED=true|false   whether HEAD SHA differs from baseline
#   RESOLVED_REF=<tag>   actual tag used (same as --ref unless latest-release)
#   COMMIT=<sha>         full HEAD commit SHA of the cloned source repo
#
# Baseline tags are read/written in the *plugin* repo (current working dir).
#
# Exit codes:
#   0  success
#   1  any error (bad argument, clone failure, API error, etc.)
#
# Sourcing: when sourced as a library (BASH_SOURCE != $0), only functions are
# defined — no execution occurs. Used by test-fetch-repo.sh for unit tests.

# ── Functions ─────────────────────────────────────────────────────────────────

# resolve_latest_release <repo-url>
# Resolves "latest-release" to the actual tag name via the GitHub API.
resolve_latest_release() {
  local repo_url="$1"
  local owner_repo
  owner_repo=$(echo "$repo_url" | sed 's|https://github.com/||')

  local tag_name
  tag_name=$(gh api "repos/${owner_repo}/releases/latest" --jq '.tag_name' 2>/dev/null) || {
    echo "ERROR: gh api request failed for repos/${owner_repo}/releases/latest" >&2
    exit 1
  }

  if [[ -z "$tag_name" || "$tag_name" == "null" ]]; then
    echo "ERROR: Could not resolve latest release for $repo_url — no tag_name in response" >&2
    exit 1
  fi

  echo "$tag_name"
}

# read_baseline_commit <repo-id>
# Reads the last-processed commit SHA from annotated tag refs/tags/ref-update/<repo-id>
# on the plugin repo origin. Message format: "<ref> | <commit-sha> | <timestamp>"
# Returns empty string when no baseline exists (first run).
read_baseline_commit() {
  local repo_id="$1"
  local tag_refspec="refs/tags/ref-update/${repo_id}"

  local remote_sha
  remote_sha=$(git ls-remote origin "$tag_refspec" 2>/dev/null | awk '{print $1}')

  if [[ -z "$remote_sha" ]]; then
    echo ""
    return 0
  fi

  if ! git fetch --quiet origin "$tag_refspec" 2>/dev/null; then
    echo "WARN: Baseline tag found on remote but fetch failed ($tag_refspec) — treating as new" >&2
    echo ""
    return 0
  fi

  local tag_msg
  tag_msg=$(git cat-file tag FETCH_HEAD 2>/dev/null \
    | awk '/^$/{found=1; next} found{print; exit}')

  if [[ -z "$tag_msg" ]]; then
    echo "WARN: Baseline tag exists but message is empty ($tag_refspec) — treating as new" >&2
    echo ""
    return 0
  fi

  echo "$tag_msg" | cut -d'|' -f2 | tr -d ' '
}

# write_baseline_tag <repo-id> <ref> <commit>
# Writes an annotated tag recording the last-processed state for <repo-id>.
# Tag message format: "<ref> | <commit> | <ISO8601-timestamp>"
# Force-pushes the tag to origin so the next run can read it back.
write_baseline_tag() {
  local repo_id="$1"
  local ref="$2"
  local commit="$3"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local tag_name="ref-update/${repo_id}"

  git tag -f -a "$tag_name" -m "${ref} | ${commit} | ${now}" >&2
  git push --force origin "refs/tags/${tag_name}" >&2
}

# assert_allowed_paths_only <repo-id> <anchored-path>...
# After git checkout, enumerate every tracked file with git ls-files and
# assert that each one falls under the allowed sparse-checkout paths
# (contract directory + source doc paths from the manifest).
# Supports three pattern types:
#   - Directory prefix:  /src/        → matches src/foo.txt, src/bar/baz.txt
#   - Exact file:        /README.md   → matches README.md only
#   - Glob pattern:      /examples/cdn_*  → matches examples/cdn_foo, examples/cdn_bar
assert_allowed_paths_only() {
  local repo_id="$1"
  shift
  local anchored_paths=("$@")

  local -a unexpected=()
  local file
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    [[ -f "$file" ]] || continue
    local matched=false
    local pat
    for pat in "${anchored_paths[@]}"; do
      local p="${pat#/}"
      if [[ "$p" == */ ]]; then
        # Directory prefix: /src/ matches src/anything
        [[ "$file" == "$p"* || "$file" == "${p%/}" ]] && matched=true && break
      elif [[ "$p" == *'*'* || "$p" == *'?'* || "$p" == *'['* ]]; then
        # Glob pattern: /examples/cdn_* matches examples/cdn_foo
        # Single * and ? must not cross path separators (matches gitignore behaviour).
        # Enforce by requiring the same number of / in file and pattern.
        local pat_depth file_depth
        pat_depth="${p//[!\/]/}"    # keep only slashes
        file_depth="${file//[!\/]/}"
        if [[ "${#pat_depth}" -eq "${#file_depth}" ]]; then
          # shellcheck disable=SC2254
          case "$file" in $p) matched=true ;; esac
          [[ "$matched" == true ]] && break
        fi
      else
        # Exact file match
        [[ "$file" == "$p" ]] && matched=true && break
      fi
    done
    [[ "$matched" != true ]] && unexpected+=("$file")
  done < <(git ls-files)

  if [[ "${#unexpected[@]}" -gt 0 ]]; then
    echo "ERROR: Post-checkout assertion failed for ${repo_id}" >&2
    echo "ERROR: Files below are outside the allowed sparse-checkout paths — aborting:" >&2
    printf '  %s\n' "${unexpected[@]}" >&2
    exit 1
  fi
}

# _fetch_repo_main [args...]
# Main execution: arg parsing → ref resolution → baseline read → sparse clone
# → change detection → emit KEY=VALUE results to stdout.
_fetch_repo_main() {
  local REPO_URL="" CONTRACT_PATH="" REPO_ID="" REF="" CHECKOUT_DIR=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-url)       REPO_URL="$2";       shift 2 ;;
      --contract-path)  CONTRACT_PATH="$2";  shift 2 ;;
      --repo-id)        REPO_ID="$2";        shift 2 ;;
      --ref)            REF="$2";            shift 2 ;;
      --checkout-dir)   CHECKOUT_DIR="$2";   shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  local missing=()
  [[ -z "$REPO_URL" ]]       && missing+=(--repo-url)
  [[ -z "$CONTRACT_PATH" ]]  && missing+=(--contract-path)
  [[ -z "$REPO_ID" ]]        && missing+=(--repo-id)
  [[ -z "$REF" ]]            && missing+=(--ref)
  [[ -z "$CHECKOUT_DIR" ]]   && missing+=(--checkout-dir)

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required arguments: ${missing[*]}" >&2
    exit 1
  fi

  # ── Resolve ref ─────────────────────────────────────────────────────────────

  local RESOLVED_REF="$REF"
  if [[ "$REF" == "latest-release" ]]; then
    RESOLVED_REF=$(resolve_latest_release "$REPO_URL")
    echo "INFO: Resolved latest-release → $RESOLVED_REF for $REPO_ID" >&2
  fi

  # ── Read baseline commit SHA ───────────────────────────────────────────────

  local LAST_COMMIT
  LAST_COMMIT=$(read_baseline_commit "$REPO_ID")

  # ── Sparse clone ───────────────────────────────────────────────────────────

  if [[ -e "$CHECKOUT_DIR" ]]; then
    echo "INFO: Removing existing checkout dir for fresh clone: $CHECKOUT_DIR" >&2
    rm -rf "$CHECKOUT_DIR"
  fi
  mkdir -p "$CHECKOUT_DIR"

  echo "INFO: Cloning $REPO_URL at $RESOLVED_REF into $CHECKOUT_DIR" >&2

  gh repo clone "$REPO_URL" "$CHECKOUT_DIR" -- \
    --filter=blob:none \
    --no-checkout \
    --depth 1 \
    --branch "$RESOLVED_REF" >&2

  # ── Sparse checkout: contract_path first, then source files from manifest ──

  cd "$CHECKOUT_DIR"

  # Root-anchor the contract path for sparse checkout
  local anchored_path
  [[ "$CONTRACT_PATH" == /* ]] && anchored_path="$CONTRACT_PATH" || anchored_path="/${CONTRACT_PATH}"

  git sparse-checkout init --no-cone >&2

  git sparse-checkout set "$anchored_path" >&2 || {
    echo "ERROR: git sparse-checkout set failed for ${REPO_ID} — aborting (no full-clone fallback)" >&2
    echo "ERROR: Path attempted: ${anchored_path}" >&2
    exit 1
  }

  git checkout >&2

  # ── Two-step fetch: read manifest, expand sparse checkout with source files ──

  local manifest_path="${CONTRACT_PATH}manifest.json"
  local -a all_anchored_paths=("$anchored_path")

  if [[ -f "$manifest_path" ]] && jq empty "$manifest_path" 2>/dev/null; then
    local source_files
    source_files=$(jq -r '.sources // {} | to_entries[] | .value.files // [] | .[]' "$manifest_path" 2>/dev/null)

    if [[ -n "$source_files" ]]; then
      while IFS= read -r sf; do
        [[ -z "$sf" ]] && continue
        # Reject absolute paths, path traversal, and .git access
        if [[ "$sf" == /* ]] || [[ "$sf" =~ (^|/)\.\.(/|$) ]] || [[ "$sf" =~ (^|/)\.git(/|$) ]]; then
          echo "ERROR: Refusing unsafe source path from manifest: ${sf}" >&2
          exit 1
        fi
        local anchored_sf
        [[ "$sf" == /* ]] && anchored_sf="$sf" || anchored_sf="/${sf}"
        all_anchored_paths+=("$anchored_sf")
      done <<< "$source_files"

      echo "INFO: Expanding sparse checkout with ${#all_anchored_paths[@]} paths for ${REPO_ID}" >&2

      git sparse-checkout set "${all_anchored_paths[@]}" >&2 || {
        echo "ERROR: git sparse-checkout expansion failed for ${REPO_ID}" >&2
        exit 1
      }

      git checkout >&2
    fi
  else
    echo "WARN: manifest.json not found or invalid in ${CONTRACT_PATH} — skipping source file expansion" >&2
  fi

  # Post-checkout assertion: only allowed paths present
  assert_allowed_paths_only "$REPO_ID" "${all_anchored_paths[@]}"

  # ── Capture HEAD commit SHA ─────────────────────────────────────────────────

  local COMMIT
  COMMIT=$(git rev-parse HEAD)

  # ── Detect changes ──────────────────────────────────────────────────────────

  local CHANGED
  if [[ -z "$LAST_COMMIT" ]]; then
    CHANGED=true
    echo "INFO: No baseline found for $REPO_ID — treating as changed (first run)" >&2
  elif [[ "$COMMIT" == "$LAST_COMMIT" ]]; then
    CHANGED=false
    echo "INFO: No changes for $REPO_ID (commit unchanged: $COMMIT)" >&2
  else
    CHANGED=true
    echo "INFO: Changes detected for $REPO_ID ($LAST_COMMIT → $COMMIT)" >&2
  fi

  # ── Emit results ────────────────────────────────────────────────────────────

  echo "CHANGED=$CHANGED"
  echo "RESOLVED_REF=$RESOLVED_REF"
  echo "COMMIT=$COMMIT"
}

# ── Entry point ───────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _fetch_repo_main "$@"
fi
