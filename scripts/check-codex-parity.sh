#!/usr/bin/env bash
set -euo pipefail

# check-codex-parity.sh — Codex drift tripwire.
#
# The Codex SKILL.md are hand-maintained rewrites of the Claude skills (no
# generate-from-Claude like Cursor), so a Claude SKILL.md change without a
# matching Codex touch silently drifts the Codex target. This check fails a PR
# when plugins/gcore-fastedge/skills/<skill>/SKILL.md changed but
# plugins/gcore-fastedge-codex/skills/<skill>/SKILL.md did not.
#
# Intentional no-op cases (Claude-only wording fix, etc.): apply the
# skip-codex-parity label to the PR — the workflow skips this check.
#
# Usage: check-codex-parity.sh <base-sha> [head-sha]

BASE="${1:-}"
HEAD="${2:-HEAD}"
if [ -z "$BASE" ]; then
  echo "ERROR: usage: $(basename "$0") <base-sha> [head-sha]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CHANGED="$(git -C "$REPO_ROOT" diff --name-only "$BASE" "$HEAD")"

violations=()
while IFS= read -r file; do
  case "$file" in
    plugins/gcore-fastedge/skills/*/SKILL.md) ;;
    *) continue ;;
  esac
  skill="$(basename "$(dirname "$file")")"
  codex_skill="plugins/gcore-fastedge-codex/skills/${skill}/SKILL.md"
  # Counterpart touched in the same diff (modified/added/deleted) — parity OK.
  grep -qxF "$codex_skill" <<< "$CHANGED" && continue
  if [ ! -f "$REPO_ROOT/$codex_skill" ]; then
    violations+=("${file} changed, but ${codex_skill} does not exist (new Claude skill needs a Codex counterpart)")
  else
    violations+=("${file} changed, but ${codex_skill} was not touched")
  fi
done <<< "$CHANGED"

if [ "${#violations[@]}" -gt 0 ]; then
  echo "ERROR: Claude SKILL.md changed without a matching Codex touch:" >&2
  for v in "${violations[@]}"; do
    echo "  - $v" >&2
  done
  echo "" >&2
  echo "Update the Codex counterpart(s), or add the skip-codex-parity label if no Codex change is needed." >&2
  exit 1
fi

echo "Codex parity OK: all changed Claude SKILL.md have a matching Codex touch."
