#!/usr/bin/env bash
set -euo pipefail

# validate-cursor-plugin.sh
# Validates Cursor plugin wiring in the fastedge-plugin repo.
#
# The Cursor skills, knowledge rule, reference/, and docs-index.json are
# generated (gitignored on main) — run the generators first:
#   node scripts/sync/generate-cursor-plugin.mjs
#   bash scripts/sync/mirror-reference.sh gcore-fastedge-cursor
#   bash scripts/sync/generate-docs-index.sh
#
# Usage:
#   bash scripts/validate-cursor-plugin.sh

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<USAGE
Usage: bash scripts/validate-cursor-plugin.sh

Checks:
  - Required committed and generated files exist (see header for generators)
  - plugin.json is valid; name and version in lockstep with the Claude plugin
  - mcp.json declares the fastedge-assistant docker server config
  - every Claude skill has a generated Cursor SKILL.md (frontmatter + no
    stale cross-references)
  - rules/fastedge-knowledge.mdc carries alwaysApply frontmatter
  - generated artifacts are covered by .gitignore
  - docs-index.json is valid and references existing markdown files
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found. Install with: apt-get install jq (Linux) or brew install jq (macOS)" >&2; exit 1; }

CLAUDE_DIR="${REPO_ROOT}/plugins/gcore-fastedge"
PLUGIN_DIR="${REPO_ROOT}/plugins/gcore-fastedge-cursor"
PLUGIN_JSON="${PLUGIN_DIR}/.cursor-plugin/plugin.json"
MCP_JSON="${PLUGIN_DIR}/mcp.json"
RULE_MDC="${PLUGIN_DIR}/rules/fastedge-knowledge.mdc"
SKILLS_DIR="${PLUGIN_DIR}/skills"
DOCS_INDEX_JSON="${PLUGIN_DIR}/docs-index.json"

ok() { echo "[OK] $1"; }
err() { echo "[ERROR] $1" >&2; exit 1; }

check_file() {
  local f="$1"
  [[ -f "$f" ]] || err "Missing required file: $f"
}

GENERATE_HINT="run: node scripts/sync/generate-cursor-plugin.mjs && bash scripts/sync/mirror-reference.sh gcore-fastedge-cursor && bash scripts/sync/generate-docs-index.sh"

check_file "$PLUGIN_JSON"
check_file "$MCP_JSON"
check_file "${PLUGIN_DIR}/README.md"
ok "Required committed files exist"

[[ -d "$SKILLS_DIR" ]] || err "Missing generated skills dir: $SKILLS_DIR — $GENERATE_HINT"
[[ -f "$RULE_MDC" ]] || err "Missing generated knowledge rule: $RULE_MDC — $GENERATE_HINT"
[[ -f "$DOCS_INDEX_JSON" ]] || err "Missing generated docs-index: $DOCS_INDEX_JSON — $GENERATE_HINT"
ok "Generated files exist"

jq empty "$PLUGIN_JSON" >/dev/null || err "Invalid JSON: $PLUGIN_JSON"
jq empty "$MCP_JSON" >/dev/null || err "Invalid JSON: $MCP_JSON"
jq empty "$DOCS_INDEX_JSON" >/dev/null || err "Invalid JSON: $DOCS_INDEX_JSON"
ok "JSON files parse"

plugin_name="$(jq -r '.name' "$PLUGIN_JSON")"
[[ "$plugin_name" == "gcore-fastedge" ]] || err "plugin.json name must be gcore-fastedge (got: $plugin_name)"

plugin_version="$(jq -r '.version // empty' "$PLUGIN_JSON")"
[[ -n "$plugin_version" ]] || err "plugin.json missing version"

# bump-version.sh bumps the Cursor manifest in lockstep with the Claude plugin.
claude_version="$(jq -r '.version // empty' "${CLAUDE_DIR}/.claude-plugin/plugin.json")"
[[ "$plugin_version" == "$claude_version" ]] || err "plugin.json version (${plugin_version}) out of lockstep with Claude plugin (${claude_version})"
ok "plugin.json core fields valid (version ${plugin_version})"

mcp_command="$(jq -r '.mcpServers["fastedge-assistant"].command // empty' "$MCP_JSON")"
[[ "$mcp_command" == "docker" ]] || err "mcp.json fastedge-assistant.command must be docker (got: $mcp_command)"

mcp_args_joined="$(jq -r '.mcpServers["fastedge-assistant"].args // [] | join(" ")' "$MCP_JSON")"
[[ "$mcp_args_joined" == *"fastedge-mcp-server"* ]] || err "mcp.json fastedge-assistant args must include fastedge-mcp-server image"
# ${workspaceFolder} is resolved by Cursor natively — keeps the mount cross-platform.
[[ "$mcp_args_joined" == *'${workspaceFolder}:/workspace'* ]] || err "mcp.json fastedge-assistant args must mount \${workspaceFolder}:/workspace"
[[ "$mcp_args_joined" == *"GCORE_API_KEY"* ]] || err "mcp.json fastedge-assistant args must pass GCORE_API_KEY through"
ok "mcp.json fastedge-assistant server config valid"

# Every Claude skill must have a generated Cursor SKILL.md.
skill_count=0
for skill_dir in "${CLAUDE_DIR}/skills"/*/; do
  skill="$(basename "$skill_dir")"
  cursor_skill="${SKILLS_DIR}/${skill}/SKILL.md"
  [[ -f "$cursor_skill" ]] || err "Missing generated SKILL.md for skill: ${skill} — $GENERATE_HINT"

  frontmatter_name="$(awk '/^name:/ {print $2; exit}' "$cursor_skill")"
  [[ "$frontmatter_name" == "$skill" ]] || err "${skill}/SKILL.md frontmatter name must be ${skill} (got: ${frontmatter_name:-<missing>})"

  # The exact tokens applySubstitutions() rewrites must not survive. Bare
  # "CLAUDE.md" mentions are fine (they refer to the user's project files).
  ! grep -q 'plugins/gcore-fastedge/CLAUDE\.md' "$cursor_skill" || err "${skill}/SKILL.md still references plugins/gcore-fastedge/CLAUDE.md (generator transform incomplete?)"
  ! grep -q '\.mcp\.json' "$cursor_skill" || err "${skill}/SKILL.md still references .mcp.json (Cursor uses mcp.json)"
  skill_count=$((skill_count + 1))
done
ok "Generated SKILL.md valid for all ${skill_count} skills"

head -5 "$RULE_MDC" | grep -q '^alwaysApply: true$' || err "fastedge-knowledge.mdc frontmatter must set alwaysApply: true"
head -5 "$RULE_MDC" | grep -q '^description:' || err "fastedge-knowledge.mdc frontmatter must set description"
ok "Knowledge rule frontmatter valid"

# Generated artifacts must stay gitignored (release commits them via git add
# --force; check-ignore tests patterns, so this passes on release checkouts too).
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  for rel in \
    "plugins/gcore-fastedge-cursor/docs-index.json" \
    "plugins/gcore-fastedge-cursor/rules/fastedge-knowledge.mdc" \
    "plugins/gcore-fastedge-cursor/skills/deploy/SKILL.md" \
    "plugins/gcore-fastedge-cursor/skills/fastedge-docs/reference/x.md"; do
    git -C "$REPO_ROOT" check-ignore -q "$rel" || err "Generated artifact not covered by .gitignore: $rel"
  done
  ok "Generated artifacts covered by .gitignore"
else
  echo "[SKIP] gitignore coverage (not a git checkout)"
fi

schema_version="$(jq -r '.schema_version' "$DOCS_INDEX_JSON")"
[[ -n "$schema_version" && "$schema_version" != "null" ]] || err "docs-index.json missing schema_version"

topic_count="$(jq '.topics | length' "$DOCS_INDEX_JSON")"
[[ "$topic_count" -gt 0 ]] || err "docs-index.json has no topics"
ok "docs-index has topics ($topic_count)"

while IFS= read -r relpath; do
  [[ "$relpath" == plugins/gcore-fastedge-cursor/* ]] || err "docs-index topic path must live in the Cursor plugin: ${relpath}"
  [[ -f "${REPO_ROOT}/${relpath}" ]] || err "docs-index topic path does not exist: ${relpath}"
done < <(jq -r '.topics[].path' "$DOCS_INDEX_JSON")
ok "docs-index topic paths resolve"

bad_ranges="$(jq '[.topics[].sections[]? | select((.line_start|type)!="number" or (.line_end|type)!="number" or .line_start < 1 or .line_end < .line_start)] | length' "$DOCS_INDEX_JSON")"
[[ "$bad_ranges" -eq 0 ]] || err "docs-index has invalid section line ranges (${bad_ranges} bad entries)"
ok "docs-index section ranges valid"

echo ""
echo "Cursor plugin validation passed."
