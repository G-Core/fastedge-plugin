#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Emit docs-index.json for the Claude plugin (always).
node "$SCRIPT_DIR/generate-docs-index.mjs" --plugin-dir gcore-fastedge
# Emit docs-index.json for the Codex plugin. Requires `mirror-reference.sh
# gcore-fastedge-codex` to have run first — the Codex reference folders must exist.
node "$SCRIPT_DIR/generate-docs-index.mjs" --plugin-dir gcore-fastedge-codex
# Emit docs-index.json for the Cursor plugin. Requires generate-cursor-plugin.mjs
# and `mirror-reference.sh gcore-fastedge-cursor` to have run first. Skip (don't
# silently emit an empty index) when the generated skills tree is absent.
if [ -d "$SCRIPT_DIR/../../plugins/gcore-fastedge-cursor/skills" ]; then
  node "$SCRIPT_DIR/generate-docs-index.mjs" --plugin-dir gcore-fastedge-cursor
else
  echo "WARNING: skipping Cursor docs-index — plugins/gcore-fastedge-cursor/skills missing (run generate-cursor-plugin.mjs + mirror-reference.sh gcore-fastedge-cursor first)" >&2
fi
