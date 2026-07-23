#!/usr/bin/env bash
# mirror-reference.sh — Copy Claude plugin reference folders into a target plugin.
#
# Usage: mirror-reference.sh <target-plugin-dir>
#   e.g. mirror-reference.sh gcore-fastedge-codex
#        mirror-reference.sh gcore-fastedge-cursor
#
# Run by release-plugin.yml before regenerating docs-index.json, so each derived
# plugin's reference content stays in sync with the Claude plugin.
#
# The skill list comes from scripts/sync/reference-skills.json (.mirrored).
set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "ERROR: usage: $(basename "$0") <target-plugin-dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_SKILLS="$PLUGIN_ROOT/plugins/gcore-fastedge/skills"
TARGET_SKILLS="$PLUGIN_ROOT/plugins/$TARGET/skills"

if [ ! -d "$TARGET_SKILLS" ]; then
  echo "ERROR: target skills dir missing: $TARGET_SKILLS" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found" >&2; exit 1; }

REFERENCE_SKILLS=()
while IFS= read -r skill; do
  REFERENCE_SKILLS+=("$skill")
done < <(jq -r '.mirrored[]' "$SCRIPT_DIR/reference-skills.json")

for skill in "${REFERENCE_SKILLS[@]}"; do
  src="$CLAUDE_SKILLS/$skill/reference"
  dst="$TARGET_SKILLS/$skill/reference"
  if [ ! -d "$src" ]; then
    echo "ERROR: source reference root missing: $src" >&2
    exit 1
  fi
  mkdir -p "$dst"
  rsync -a --delete "$src/" "$dst/"
  count=$(find "$dst" -name "*.md" | wc -l)
  echo "mirrored $count files for $skill ($TARGET)"
done
