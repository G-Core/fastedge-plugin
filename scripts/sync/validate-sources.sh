#!/usr/bin/env bash
# validate-sources.sh — validate sources.json v2 against schema rules
# Usage: validate-sources.sh <path-to-sources.json>
set -euo pipefail

SOURCES_FILE="${1:-}"

if [[ -z "$SOURCES_FILE" ]]; then
  echo "ERROR: No sources.json path provided." >&2
  echo "Usage: $0 <path-to-sources.json>" >&2
  exit 1
fi

if [[ ! -f "$SOURCES_FILE" ]]; then
  echo "ERROR: File not found: $SOURCES_FILE" >&2
  exit 1
fi

ERRORS=0

# Resolve sources.json directory so intent_dir paths can be checked relative to it
SOURCES_DIR="$(cd "$(dirname "$SOURCES_FILE")" && pwd)"

fail() {
  echo "VALIDATION ERROR: $*" >&2
  ERRORS=$((ERRORS + 1))
}

# Rule 0: Version must be "2.0"
VERSION=$(jq -r '.version' "$SOURCES_FILE")
if [[ "$VERSION" != "2.0" ]]; then
  fail "Rule 0: sources.json version must be '2.0', got '${VERSION}'"
fi

# Rule 1: All repo `id` values must be unique
mapfile -t IDS < <(jq -r '.repos[].id' "$SOURCES_FILE")
UNIQUE_IDS=$(printf '%s\n' "${IDS[@]}" | sort -u | wc -l)
if [[ "${#IDS[@]}" -ne "$UNIQUE_IDS" ]]; then
  DUPES=$(printf '%s\n' "${IDS[@]}" | sort | uniq -d | tr '\n' ' ')
  fail "Rule 1: Duplicate repo id(s) found: $DUPES"
fi

# Rule 2: All github_url values must be reachable via GitHub API
while IFS= read -r URL; do
  if [[ "$URL" == */ ]]; then
    fail "Rule 2: github_url has trailing slash (remove it): $URL"
    continue
  fi
  REPO_PATH="${URL#https://github.com/}"
  if ! gh api "repos/$REPO_PATH" --silent 2>/dev/null; then
    fail "Rule 2: github_url not reachable (repo not found or no access): $URL"
  fi
done < <(jq -r '.repos[].github_url' "$SOURCES_FILE")

# Rule 3: generator_agent must not equal reviewer_agent within the same repo
while IFS=$'\t' read -r REPO_ID GEN REV; do
  if [[ "$GEN" == "$REV" ]]; then
    fail "Rule 3: generator_agent equals reviewer_agent ('$GEN') in repo '$REPO_ID'"
  fi
done < <(jq -r '.repos[] | [.id, .generator_agent, .reviewer_agent] | @tsv' "$SOURCES_FILE")

# Rule 4: contract_path must end with /
while IFS=$'\t' read -r REPO_ID CONTRACT_PATH; do
  if [[ "$CONTRACT_PATH" != */ ]]; then
    fail "Rule 4: contract_path must end with '/' in repo '$REPO_ID': $CONTRACT_PATH"
  fi
done < <(jq -r '.repos[] | [.id, .contract_path] | @tsv' "$SOURCES_FILE")

# Rule 5: intent_dir must end with / and the directory must exist relative to sources.json
while IFS=$'\t' read -r REPO_ID INTENT_DIR; do
  if [[ "$INTENT_DIR" != */ ]]; then
    fail "Rule 5: intent_dir must end with '/' in repo '$REPO_ID': $INTENT_DIR"
  fi
  if [[ ! -d "$SOURCES_DIR/$INTENT_DIR" ]]; then
    fail "Rule 5: intent_dir does not exist in repo '$REPO_ID': $INTENT_DIR (resolved to '$SOURCES_DIR/$INTENT_DIR')"
  fi
done < <(jq -r '.repos[] | [.id, .intent_dir] | @tsv' "$SOURCES_FILE")

# Rule 6: No v1 fields allowed (updates[], sparse_paths)
while IFS= read -r REPO_ID; do
  HAS_UPDATES=$(jq -r --arg id "$REPO_ID" '.repos[] | select(.id == $id) | has("updates")' "$SOURCES_FILE")
  HAS_SPARSE=$(jq -r --arg id "$REPO_ID" '.repos[] | select(.id == $id) | has("sparse_paths")' "$SOURCES_FILE")
  if [[ "$HAS_UPDATES" == "true" ]]; then
    fail "Rule 6: v1 field 'updates' found in repo '$REPO_ID' — migrate to v2 (use manifest.json target_mapping)"
  fi
  if [[ "$HAS_SPARSE" == "true" ]]; then
    fail "Rule 6: v1 field 'sparse_paths' found in repo '$REPO_ID' — migrate to v2 (use contract_path)"
  fi
done < <(jq -r '.repos[].id' "$SOURCES_FILE")

# Summary
if [[ "$ERRORS" -gt 0 ]]; then
  echo "sources.json validation FAILED with $ERRORS error(s)." >&2
  exit 1
fi

echo "sources.json validation passed."
