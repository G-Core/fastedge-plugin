#!/usr/bin/env bash
# test-docs-index-pipeline.sh — tests that write_and_push does NOT generate/stage docs-index
#
# docs-index.json generation was decoupled from the sync pipeline and moved
# to the release-plugin.yml workflow (see context/RELEASE_PIPELINE_PLAN.md).
#
# Coverage:
#   (1) write_and_push does NOT call generate-docs-index.sh or stage docs-index.json
#   (2) write_and_push still commits reference .md files when content changes
#   (3) write_and_push skips commit when reference files are unchanged (return 2)
#
# Usage: bash scripts/sync/tests/test-docs-index-pipeline.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROCESS_REPOS="$SCRIPT_DIR/../process-repos.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

# shellcheck source=../process-repos.sh
source "$PROCESS_REPOS"
set +e

TMPWORK="$(mktemp -d)"
trap 'rm -rf "$TMPWORK"' EXIT

make_manifest() {
  local manifest_path="$1"
  cat > "$manifest_path" <<'EOF'
{
  "target_mapping": {
    "sdk-reference-js": {
      "reference_file": "plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference-js.md"
    }
  }
}
EOF
}

echo ""
echo "process-repos.sh: docs-index pipeline tests"
echo "==========================================="

# ── (1) write_and_push does NOT generate or stage docs-index ────────────────

TEST1_DIR="${TMPWORK}/t1"
mkdir -p "${TEST1_DIR}/staging" "${TEST1_DIR}/plugins/gcore-fastedge/skills/fastedge-docs/reference"
printf "# generated\n" > "${TEST1_DIR}/staging/gen-1.md"
make_manifest "${TEST1_DIR}/manifest.json"

# Place a generate-docs-index.sh that writes a marker if called — it should NOT be called.
FAKE_SCRIPT_DIR="${TEST1_DIR}/scripts"
mkdir -p "$FAKE_SCRIPT_DIR"
cat > "${FAKE_SCRIPT_DIR}/generate-docs-index.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo ok > .docs-index-generated
EOF
chmod +x "${FAKE_SCRIPT_DIR}/generate-docs-index.sh"

SCRIPT_DIR="$FAKE_SCRIPT_DIR"
DEFAULT_BRANCH="main"
REPO_ID="test-repo"
RESOLVED_REF="v1.0.0"
COMMIT="abc123"
CHANGED_FILES="plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference-js.md"

GIT_ADD_CALLS=()
COMMIT_CALLED=0
git() {
  local sub="$1"
  shift
  case "$sub" in
    checkout) return 0 ;;
    add) GIT_ADD_CALLS+=("$*"); return 0 ;;
    diff) return 1 ;;   # non-zero => staged changes exist
    commit) COMMIT_CALLED=1; return 0 ;;
    push) return 0 ;;
    *) return 0 ;;
  esac
}

OLDPWD_SAVED="$(pwd)"
cd "$TEST1_DIR" || exit 1
write_and_push "${TEST1_DIR}/staging" "${TEST1_DIR}/manifest.json"
rc1=$?
cd "$OLDPWD_SAVED" || exit 1

GIT_ADD_ALL="${GIT_ADD_CALLS[*]}"
if [[ "$rc1" -eq 0 ]] \
   && [[ ! -f "${TEST1_DIR}/.docs-index-generated" ]] \
   && [[ "$GIT_ADD_ALL" != *"docs-index.json"* ]] \
   && [[ "$COMMIT_CALLED" -eq 1 ]]; then
  pass "(1) write_and_push does NOT generate or stage docs-index.json"
else
  fail "(1) write_and_push does NOT generate or stage docs-index.json" \
    "exit=${rc1}, marker=$(test -f "${TEST1_DIR}/.docs-index-generated" && echo yes || echo no), GIT_ADD_ALL='${GIT_ADD_ALL}', COMMIT_CALLED=${COMMIT_CALLED}"
fi

# ── (2) write_and_push commits reference .md files when content changes ─────

TEST2_DIR="${TMPWORK}/t2"
mkdir -p "${TEST2_DIR}/staging" "${TEST2_DIR}/plugins/gcore-fastedge/skills/fastedge-docs/reference"
printf "# generated\n" > "${TEST2_DIR}/staging/gen-1.md"
make_manifest "${TEST2_DIR}/manifest.json"

FAKE_SCRIPT_DIR="${TEST2_DIR}/scripts"
mkdir -p "$FAKE_SCRIPT_DIR"

SCRIPT_DIR="$FAKE_SCRIPT_DIR"
DEFAULT_BRANCH="main"
REPO_ID="test-repo"
RESOLVED_REF="v1.0.0"
COMMIT="abc123"
CHANGED_FILES="plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference-js.md"

GIT_ADD_CALLS=()
COMMIT_MSG=""
git() {
  local sub="$1"
  shift
  case "$sub" in
    checkout) return 0 ;;
    add) GIT_ADD_CALLS+=("$*"); return 0 ;;
    diff) return 1 ;;   # staged changes exist
    commit) COMMIT_MSG="$*"; return 0 ;;
    push) return 0 ;;
    *) return 0 ;;
  esac
}

OLDPWD_SAVED="$(pwd)"
cd "$TEST2_DIR" || exit 1
write_and_push "${TEST2_DIR}/staging" "${TEST2_DIR}/manifest.json"
rc2=$?
cd "$OLDPWD_SAVED" || exit 1

GIT_ADD_ALL="${GIT_ADD_CALLS[*]}"
if [[ "$rc2" -eq 0 ]] \
   && [[ "$GIT_ADD_ALL" == *"sdk-reference-js.md"* ]] \
   && [[ "$COMMIT_MSG" == *"auto: update reference docs"* ]]; then
  pass "(2) write_and_push commits reference .md files when content changes"
else
  fail "(2) write_and_push commits reference .md files when content changes" \
    "exit=${rc2}, GIT_ADD_ALL='${GIT_ADD_ALL}', COMMIT_MSG='${COMMIT_MSG}'"
fi

# ── (3) no ref changes → commit skipped, return 2 ──────────────────────────

TEST3_DIR="${TMPWORK}/t3"
mkdir -p "${TEST3_DIR}/staging" "${TEST3_DIR}/plugins/gcore-fastedge/skills/fastedge-docs/reference"
printf "# generated\n" > "${TEST3_DIR}/staging/gen-1.md"
make_manifest "${TEST3_DIR}/manifest.json"

FAKE_SCRIPT_DIR="${TEST3_DIR}/scripts"
mkdir -p "$FAKE_SCRIPT_DIR"

SCRIPT_DIR="$FAKE_SCRIPT_DIR"
DEFAULT_BRANCH="main"
REPO_ID="test-repo"
RESOLVED_REF="v1.0.0"
COMMIT="abc123"
CHANGED_FILES="plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference-js.md"

git() {
  local sub="$1"
  shift
  case "$sub" in
    checkout) return 0 ;;
    add) return 0 ;;
    diff) return 0 ;;   # zero => no staged changes (reference files unchanged)
    commit) return 0 ;;
    push) return 0 ;;
    *) return 0 ;;
  esac
}

OLDPWD_SAVED="$(pwd)"
cd "$TEST3_DIR" || exit 1
write_and_push "${TEST3_DIR}/staging" "${TEST3_DIR}/manifest.json"
rc3=$?
cd "$OLDPWD_SAVED" || exit 1

if [[ "$rc3" -eq 2 ]]; then
  pass "(3) no ref changes → commit skipped, return 2"
else
  fail "(3) no ref changes → commit skipped, return 2" \
    "exit=${rc3}"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
