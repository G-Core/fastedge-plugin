#!/usr/bin/env bash
set -euo pipefail

# validate-codex-plugin.sh
# Validates Codex plugin wiring in the fastedge-plugin repo.
#
# Usage:
#   bash scripts/validate-codex-plugin.sh
#   bash scripts/validate-codex-plugin.sh --with-runtime-checks

WITH_RUNTIME_CHECKS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-runtime-checks)
      WITH_RUNTIME_CHECKS=true
      shift
      ;;
    -h|--help)
      cat <<USAGE
Usage: bash scripts/validate-codex-plugin.sh [--with-runtime-checks]

Checks:
  - Required Codex plugin files exist
  - plugin.json and marketplace.json are valid and consistent
  - docs-index.json is valid and references existing markdown files
  - section line ranges are sane
  - .mcp.json contains fastedge docker server config

Optional runtime checks (--with-runtime-checks):
  - codex CLI exists
  - codex mcp get fastedge-assistant succeeds
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

PLUGIN_DIR="${REPO_ROOT}/plugins/gcore-fastedge-codex"
PLUGIN_JSON="${PLUGIN_DIR}/.codex-plugin/plugin.json"
MCP_JSON="${PLUGIN_DIR}/.mcp.json"
MARKETPLACE_JSON="${REPO_ROOT}/.agents/plugins/marketplace.json"
DOCS_INDEX_JSON="${REPO_ROOT}/plugins/gcore-fastedge/docs-index.json"

ok() { echo "[OK] $1"; }
err() { echo "[ERROR] $1" >&2; exit 1; }

check_file() {
  local f="$1"
  [[ -f "$f" ]] || err "Missing required file: $f"
}

check_file "$PLUGIN_JSON"
check_file "$MCP_JSON"
check_file "$MARKETPLACE_JSON"
check_file "$DOCS_INDEX_JSON"

# Validate files referenced by plugin.json exist
HOOKS_JSON="${PLUGIN_DIR}/hooks.json"
APP_JSON="${PLUGIN_DIR}/.app.json"
SKILLS_DIR="${PLUGIN_DIR}/skills"
check_file "$HOOKS_JSON"
check_file "$APP_JSON"
[[ -d "$SKILLS_DIR" ]] || err "Missing required directory: $SKILLS_DIR"
ok "Required files exist"

jq empty "$PLUGIN_JSON" >/dev/null || err "Invalid JSON: $PLUGIN_JSON"
jq empty "$MCP_JSON" >/dev/null || err "Invalid JSON: $MCP_JSON"
jq empty "$HOOKS_JSON" >/dev/null || err "Invalid JSON: $HOOKS_JSON"
jq empty "$APP_JSON" >/dev/null || err "Invalid JSON: $APP_JSON"
jq empty "$MARKETPLACE_JSON" >/dev/null || err "Invalid JSON: $MARKETPLACE_JSON"
jq empty "$DOCS_INDEX_JSON" >/dev/null || err "Invalid JSON: $DOCS_INDEX_JSON"
ok "JSON files parse"

plugin_name="$(jq -r '.name' "$PLUGIN_JSON")"
[[ "$plugin_name" == "gcore-fastedge" ]] || err "plugin.json name must be gcore-fastedge (got: $plugin_name)"

skills_path="$(jq -r '.skills' "$PLUGIN_JSON")"
[[ "$skills_path" == "./skills/" ]] || err "plugin.json skills path must be ./skills/ (got: $skills_path)"

mcp_path="$(jq -r '.mcpServers' "$PLUGIN_JSON")"
[[ "$mcp_path" == "./.mcp.json" ]] || err "plugin.json mcpServers path must be ./.mcp.json (got: $mcp_path)"

apps_path="$(jq -r '.apps' "$PLUGIN_JSON")"
[[ "$apps_path" == "./.app.json" ]] || err "plugin.json apps path must be ./.app.json (got: $apps_path)"
ok "plugin.json core fields valid"

market_entry_count="$(jq '[.plugins[] | select(.name == "gcore-fastedge" and .source.path == "./plugins/gcore-fastedge-codex")] | length' "$MARKETPLACE_JSON")"
[[ "$market_entry_count" -ge 1 ]] || err "marketplace entry for gcore-fastedge (path ./plugins/gcore-fastedge-codex) not found or has wrong source.path"
ok "marketplace entry exists"

mcp_command="$(jq -r '.mcpServers["fastedge-assistant"].command // empty' "$MCP_JSON")"
# Preferred form is a direct docker invocation with a relative "-v ./:/workspace" bind mount
# (docker resolves it against its own cwd — no host shell, works on Windows too).
# sh/bash -c "exec docker ..." wrappers are still accepted for backward compatibility.
[[ "$mcp_command" == "docker" || "$mcp_command" == "sh" || "$mcp_command" == "bash" ]] || err ".mcp.json fastedge-assistant.command must be docker, sh, or bash"

mcp_args_joined="$(jq -r '.mcpServers["fastedge-assistant"].args // [] | join(" ")' "$MCP_JSON")"
[[ "$mcp_args_joined" == *"fastedge-mcp-server"* ]] || err ".mcp.json fastedge-assistant args must include fastedge-mcp-server image"
[[ "$mcp_args_joined" == *"GCORE_API_KEY"* || "$mcp_args_joined" == *"FASTEDGE_API_KEY"* ]] || err ".mcp.json fastedge-assistant args must include GCORE_API_KEY or FASTEDGE_API_KEY env"
ok ".mcp.json fastedge-assistant server config valid"

schema_version="$(jq -r '.schema_version' "$DOCS_INDEX_JSON")"
[[ -n "$schema_version" && "$schema_version" != "null" ]] || err "docs-index.json missing schema_version"

topic_count="$(jq '.topics | length' "$DOCS_INDEX_JSON")"
[[ "$topic_count" -gt 0 ]] || err "docs-index.json has no topics"
ok "docs-index has topics ($topic_count)"

# Validate referenced markdown paths and section ranges.
while IFS= read -r relpath; do
  [[ -f "${REPO_ROOT}/${relpath}" ]] || err "docs-index topic path does not exist: ${relpath}"
done < <(jq -r '.topics[].path' "$DOCS_INDEX_JSON")
ok "docs-index topic paths resolve"

bad_ranges="$(jq '[.topics[].sections[]? | select((.line_start|type)!="number" or (.line_end|type)!="number" or .line_start < 1 or .line_end < .line_start)] | length' "$DOCS_INDEX_JSON")"
[[ "$bad_ranges" -eq 0 ]] || err "docs-index has invalid section line ranges (${bad_ranges} bad entries)"
ok "docs-index section ranges valid"

if [[ "$WITH_RUNTIME_CHECKS" == "true" ]]; then
  command -v codex >/dev/null 2>&1 || err "codex CLI not found in PATH"
  codex --version >/dev/null || err "codex --version failed"
  ok "codex CLI available"

  codex mcp get fastedge-assistant >/dev/null || err "codex mcp get fastedge-assistant failed (configure MCP first)"
  ok "codex fastedge-assistant MCP server is configured"
fi

echo ""
echo "Codex plugin validation passed."
