#!/usr/bin/env bash
# test-bump-version.sh — unit tests for scripts/bump-version.sh
#
# Coverage:
#   (1) patch bump: 0.1.0 → 0.1.1
#   (2) minor bump: 0.1.1 → 0.2.0
#   (3) major bump: 0.2.0 → 1.0.0
#   (4) all three manifests updated to same version (Claude, Codex, marketplace gcore-fastedge entry)
#   (5) stdout contains only the new version string
#   (6) invalid bump type → exit 1
#   (7) idempotent: re-running reads the already-bumped value
#
# Usage: bash scripts/sync/tests/test-bump-version.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUMP_VERSION="$SCRIPT_DIR/../../bump-version.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

# ── Setup: create temp plugin.json files ────────────────────────────────────

TMPWORK="$(mktemp -d)"
trap 'rm -rf "$TMPWORK"' EXIT

FAKE_ROOT="$TMPWORK/repo"
CLAUDE_DIR="$FAKE_ROOT/plugins/gcore-fastedge/.claude-plugin"
CODEX_DIR="$FAKE_ROOT/plugins/gcore-fastedge-codex/.codex-plugin"
CURSOR_DIR="$FAKE_ROOT/plugins/gcore-fastedge-cursor/.cursor-plugin"
MARKETPLACE_DIR="$FAKE_ROOT/.claude-plugin"
SCRIPTS_DIR="$FAKE_ROOT/scripts"

mkdir -p "$CLAUDE_DIR" "$CODEX_DIR" "$CURSOR_DIR" "$MARKETPLACE_DIR" "$SCRIPTS_DIR"
cp "$BUMP_VERSION" "$SCRIPTS_DIR/bump-version.sh"

reset_versions() {
  local claude_v="${1:-0.1.0}" codex_v="${2:-0.1.0}" market_v="${3:-${1:-0.1.0}}" cursor_v="${4:-${2:-0.1.0}}"
  cat > "$CLAUDE_DIR/plugin.json" <<EOF
{
  "name": "gcore-fastedge",
  "version": "${claude_v}",
  "description": "test"
}
EOF
  cat > "$CODEX_DIR/plugin.json" <<EOF
{
  "name": "gcore-fastedge",
  "version": "${codex_v}",
  "description": "test"
}
EOF
  cat > "$CURSOR_DIR/plugin.json" <<EOF
{
  "name": "gcore-fastedge",
  "version": "${cursor_v}",
  "description": "test"
}
EOF
  cat > "$MARKETPLACE_DIR/marketplace.json" <<EOF
{
  "name": "gcore-fastedge-marketplace",
  "version": "0.1.0",
  "plugins": [
    {
      "name": "gcore-fastedge",
      "version": "${market_v}"
    }
  ]
}
EOF
}

read_version() {
  jq -r '.version' "$1"
}

echo ""
echo "bump-version.sh tests"
echo "====================="

# ── (1) patch bump: 0.1.0 → 0.1.1 ─────────────────────────────────────────

reset_versions "0.1.0" "0.1.0"
OUTPUT=$(bash "$SCRIPTS_DIR/bump-version.sh" patch 2>&1)
rc=$?
CLAUDE_V=$(read_version "$CLAUDE_DIR/plugin.json")
CODEX_V=$(read_version "$CODEX_DIR/plugin.json")

if [[ "$rc" -eq 0 ]] && [[ "$CLAUDE_V" == "0.1.1" ]]; then
  pass "(1) patch bump: 0.1.0 → 0.1.1"
else
  fail "(1) patch bump: 0.1.0 → 0.1.1" \
    "exit=${rc}, claude=${CLAUDE_V}, output='${OUTPUT}'"
fi

# ── (2) minor bump: 0.1.1 → 0.2.0 ─────────────────────────────────────────

reset_versions "0.1.1" "0.1.1"
OUTPUT=$(bash "$SCRIPTS_DIR/bump-version.sh" minor 2>&1)
rc=$?
CLAUDE_V=$(read_version "$CLAUDE_DIR/plugin.json")

if [[ "$rc" -eq 0 ]] && [[ "$CLAUDE_V" == "0.2.0" ]]; then
  pass "(2) minor bump: 0.1.1 → 0.2.0"
else
  fail "(2) minor bump: 0.1.1 → 0.2.0" \
    "exit=${rc}, claude=${CLAUDE_V}, output='${OUTPUT}'"
fi

# ── (3) major bump: 0.2.0 → 1.0.0 ─────────────────────────────────────────

reset_versions "0.2.0" "0.2.0"
OUTPUT=$(bash "$SCRIPTS_DIR/bump-version.sh" major 2>&1)
rc=$?
CLAUDE_V=$(read_version "$CLAUDE_DIR/plugin.json")

if [[ "$rc" -eq 0 ]] && [[ "$CLAUDE_V" == "1.0.0" ]]; then
  pass "(3) major bump: 0.2.0 → 1.0.0"
else
  fail "(3) major bump: 0.2.0 → 1.0.0" \
    "exit=${rc}, claude=${CLAUDE_V}, output='${OUTPUT}'"
fi

# ── (4) all manifests updated to same version ───────────────────────────────

reset_versions "0.3.5" "0.3.5"
bash "$SCRIPTS_DIR/bump-version.sh" patch >/dev/null 2>&1
CLAUDE_V=$(read_version "$CLAUDE_DIR/plugin.json")
CODEX_V=$(read_version "$CODEX_DIR/plugin.json")
CURSOR_V=$(read_version "$CURSOR_DIR/plugin.json")
MARKET_V=$(jq -r '.plugins[] | select(.name == "gcore-fastedge") | .version' "$MARKETPLACE_DIR/marketplace.json")

if [[ "$CLAUDE_V" == "0.3.6" ]] && [[ "$CODEX_V" == "0.3.6" ]] && [[ "$CURSOR_V" == "0.3.6" ]] && [[ "$MARKET_V" == "0.3.6" ]]; then
  pass "(4) all manifests updated to same version (0.3.6)"
else
  fail "(4) all manifests updated to same version" \
    "claude=${CLAUDE_V}, codex=${CODEX_V}, cursor=${CURSOR_V}, marketplace.plugins[0]=${MARKET_V}"
fi

# ── (5) stdout contains only the new version string ─────────────────────────

reset_versions "0.1.0" "0.1.0"
OUTPUT=$(bash "$SCRIPTS_DIR/bump-version.sh" patch 2>/dev/null)

if [[ "$OUTPUT" == "0.1.1" ]]; then
  pass "(5) stdout contains only the new version string"
else
  fail "(5) stdout contains only the new version string" \
    "output='${OUTPUT}'"
fi

# ── (6) invalid bump type → exit 1 ─────────────────────────────────────────

reset_versions "0.1.0" "0.1.0"
OUTPUT=$(bash "$SCRIPTS_DIR/bump-version.sh" bogus 2>&1)
rc=$?

if [[ "$rc" -eq 1 ]] && [[ "$OUTPUT" == *"Invalid bump type"* ]]; then
  pass "(6) invalid bump type → exit 1 with error message"
else
  fail "(6) invalid bump type → exit 1 with error message" \
    "exit=${rc}, output='${OUTPUT}'"
fi

# ── (7) idempotent: re-running reads the already-bumped value ──────────────

reset_versions "0.1.0" "0.1.0"
bash "$SCRIPTS_DIR/bump-version.sh" patch >/dev/null 2>&1
OUTPUT2=$(bash "$SCRIPTS_DIR/bump-version.sh" patch 2>/dev/null)

if [[ "$OUTPUT2" == "0.1.2" ]]; then
  pass "(7) idempotent: second patch bump 0.1.1 → 0.1.2"
else
  fail "(7) idempotent: second patch bump 0.1.1 → 0.1.2" \
    "output='${OUTPUT2}'"
fi

# ── (8) atomic: if Codex write fails, Claude manifest is not modified ────────

reset_versions "0.5.0" "0.5.0"

# Make Codex plugin.json unwritable so the jq temp file write fails
chmod 444 "$CODEX_DIR"
OUTPUT=$(bash "$SCRIPTS_DIR/bump-version.sh" patch 2>&1)
rc=$?
chmod 755 "$CODEX_DIR"

CLAUDE_V=$(read_version "$CLAUDE_DIR/plugin.json")
CODEX_V=$(read_version "$CODEX_DIR/plugin.json")
CURSOR_V=$(read_version "$CURSOR_DIR/plugin.json")
MARKET_V=$(jq -r '.plugins[] | select(.name == "gcore-fastedge") | .version' "$MARKETPLACE_DIR/marketplace.json")

if [[ "$rc" -ne 0 ]] && [[ "$CLAUDE_V" == "0.5.0" ]] && [[ "$CODEX_V" == "0.5.0" ]] && [[ "$CURSOR_V" == "0.5.0" ]] && [[ "$MARKET_V" == "0.5.0" ]]; then
  pass "(8) atomic: Codex write failure leaves all manifests unchanged"
else
  fail "(8) atomic: Codex write failure leaves all manifests unchanged" \
    "exit=${rc}, claude=${CLAUDE_V}, codex=${CODEX_V}, cursor=${CURSOR_V}, marketplace.plugins[0]=${MARKET_V}"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
