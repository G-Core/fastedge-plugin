#!/usr/bin/env bash
# bump-version.sh — Bump the version in all plugin manifests in lockstep.
#
# Usage: bump-version.sh [patch|minor|major]
#
# Reads the current version from the Claude plugin.json, bumps according
# to semver rules, writes the new version to the Claude, Codex, and Cursor
# plugin.json files, and prints the new version to stdout.
#
# All manifests are set to the SAME version so that Claude plugin, Codex
# plugin, Cursor plugin, and MCP server all share one version number.

set -euo pipefail

BUMP_TYPE="${1:-patch}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAUDE_PLUGIN_JSON="$REPO_ROOT/plugins/gcore-fastedge/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$REPO_ROOT/plugins/gcore-fastedge-codex/.codex-plugin/plugin.json"
CURSOR_PLUGIN_JSON="$REPO_ROOT/plugins/gcore-fastedge-cursor/.cursor-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

if [[ ! -f "$CLAUDE_PLUGIN_JSON" ]]; then
  echo "ERROR: Claude plugin.json not found at $CLAUDE_PLUGIN_JSON" >&2
  exit 1
fi

if [[ ! -f "$CODEX_PLUGIN_JSON" ]]; then
  echo "ERROR: Codex plugin.json not found at $CODEX_PLUGIN_JSON" >&2
  exit 1
fi

if [[ ! -f "$CURSOR_PLUGIN_JSON" ]]; then
  echo "ERROR: Cursor plugin.json not found at $CURSOR_PLUGIN_JSON" >&2
  exit 1
fi

if [[ ! -f "$MARKETPLACE_JSON" ]]; then
  echo "ERROR: marketplace.json not found at $MARKETPLACE_JSON" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed" >&2
  exit 1
fi

CURRENT_VERSION=$(jq -r '.version' "$CLAUDE_PLUGIN_JSON")

if [[ ! "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: Current version '$CURRENT_VERSION' is not valid semver" >&2
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$BUMP_TYPE" in
  patch)
    PATCH=$((PATCH + 1))
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  *)
    echo "ERROR: Invalid bump type '$BUMP_TYPE'. Use: patch, minor, major" >&2
    exit 1
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# Write all temp files first so jq errors are caught before any file is touched.
jq --arg v "$NEW_VERSION" '.version = $v' "$CLAUDE_PLUGIN_JSON" > "${CLAUDE_PLUGIN_JSON}.tmp"
jq --arg v "$NEW_VERSION" '.version = $v' "$CODEX_PLUGIN_JSON" > "${CODEX_PLUGIN_JSON}.tmp"
jq --arg v "$NEW_VERSION" '.version = $v' "$CURSOR_PLUGIN_JSON" > "${CURSOR_PLUGIN_JSON}.tmp"
entry_count=$(jq '[.plugins[] | select(.name == "gcore-fastedge")] | length' "$MARKETPLACE_JSON")
if [[ "$entry_count" -eq 0 ]]; then
  echo "ERROR: no entry with .name == \"gcore-fastedge\" found in $MARKETPLACE_JSON" >&2
  exit 1
fi
jq --arg v "$NEW_VERSION" '(.plugins[] | select(.name == "gcore-fastedge") | .version) = $v' "$MARKETPLACE_JSON" > "${MARKETPLACE_JSON}.tmp"

# Back up originals so we can roll back if any rename fails mid-sequence.
cp "$CLAUDE_PLUGIN_JSON" "${CLAUDE_PLUGIN_JSON}.bak"
cp "$CODEX_PLUGIN_JSON"  "${CODEX_PLUGIN_JSON}.bak"
cp "$CURSOR_PLUGIN_JSON" "${CURSOR_PLUGIN_JSON}.bak"
cp "$MARKETPLACE_JSON"   "${MARKETPLACE_JSON}.bak"

rollback() {
  echo "ERROR: version bump failed mid-write; rolling back to original versions" >&2
  mv "${CLAUDE_PLUGIN_JSON}.bak" "$CLAUDE_PLUGIN_JSON" 2>/dev/null || true
  mv "${CODEX_PLUGIN_JSON}.bak"  "$CODEX_PLUGIN_JSON"  2>/dev/null || true
  mv "${CURSOR_PLUGIN_JSON}.bak" "$CURSOR_PLUGIN_JSON" 2>/dev/null || true
  mv "${MARKETPLACE_JSON}.bak"   "$MARKETPLACE_JSON"   2>/dev/null || true
  rm -f "${CLAUDE_PLUGIN_JSON}.tmp" "${CODEX_PLUGIN_JSON}.tmp" "${CURSOR_PLUGIN_JSON}.tmp" "${MARKETPLACE_JSON}.tmp"
}
trap rollback ERR

mv "${CLAUDE_PLUGIN_JSON}.tmp" "$CLAUDE_PLUGIN_JSON"
mv "${CODEX_PLUGIN_JSON}.tmp"  "$CODEX_PLUGIN_JSON"
mv "${CURSOR_PLUGIN_JSON}.tmp" "$CURSOR_PLUGIN_JSON"
mv "${MARKETPLACE_JSON}.tmp"   "$MARKETPLACE_JSON"

trap - ERR
rm -f "${CLAUDE_PLUGIN_JSON}.bak" "${CODEX_PLUGIN_JSON}.bak" "${CURSOR_PLUGIN_JSON}.bak" "${MARKETPLACE_JSON}.bak"

echo "$NEW_VERSION"
