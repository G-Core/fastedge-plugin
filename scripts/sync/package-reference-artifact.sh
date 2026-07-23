#!/usr/bin/env bash
# package-reference-artifact.sh — Package Claude plugin reference docs into a tarball.
#
# Inputs:
#   VERSION  (env var, e.g. "1.2.3")
# Outputs:
#   dist/fastedge-reference-docs-v<VERSION>.tar.gz
#   dist/fastedge-reference-docs-v<VERSION>.tar.gz.sha256
#
# The tarball is standalone-consumable by any MCP client:
#   fastedge-reference-docs-vX.Y.Z/
#   ├── docs-index.json     (paths rewritten to reference/<skill>/...)
#   ├── reference/
#   │   ├── fastedge-docs/  (contents of skills/fastedge-docs/reference/)
#   │   └── test/           (contents of skills/test/reference/)
#   └── METADATA.json
#
# The skill list comes from scripts/sync/reference-skills.json (.indexed) —
# the tarball must package exactly the docs-index'd skills or paths dangle.
set -euo pipefail

: "${VERSION:?VERSION env var is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ARTIFACT_NAME="fastedge-reference-docs-v${VERSION}"
STAGE="$PLUGIN_ROOT/dist/stage/$ARTIFACT_NAME"
TARBALL="$PLUGIN_ROOT/dist/$ARTIFACT_NAME.tar.gz"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found" >&2; exit 1; }

PACKAGE_SKILLS=()
while IFS= read -r skill; do
  PACKAGE_SKILLS+=("$skill")
done < <(jq -r '.indexed[]' "$SCRIPT_DIR/reference-skills.json")

rm -rf "$STAGE"
mkdir -p "$STAGE/reference"

for skill in "${PACKAGE_SKILLS[@]}"; do
  src="$PLUGIN_ROOT/plugins/gcore-fastedge/skills/$skill/reference"
  if [ ! -d "$src" ]; then
    echo "ERROR: source reference root missing: $src" >&2
    exit 1
  fi
  cp -r "$src" "$STAGE/reference/$skill"
done

# Generate artifact-relative docs-index (paths start with reference/<skill>/...)
node "$SCRIPT_DIR/rewrite-docs-index-paths.mjs" \
  --input "$PLUGIN_ROOT/plugins/gcore-fastedge/docs-index.json" \
  --output "$STAGE/docs-index.json" \
  --prefix "reference"

cat > "$STAGE/METADATA.json" <<EOF
{
  "version": "${VERSION}",
  "schema_version": "1.0.0",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source_repo": "G-Core/fastedge-plugin",
  "source_commit": "$(git -C "$PLUGIN_ROOT" rev-parse HEAD)",
  "tag": "v${VERSION}"
}
EOF

tar -czf "$TARBALL" -C "$PLUGIN_ROOT/dist/stage" "$ARTIFACT_NAME"
sha256sum "$TARBALL" > "$TARBALL.sha256"

echo "Packaged: $TARBALL"
echo "SHA256:   $TARBALL.sha256"
