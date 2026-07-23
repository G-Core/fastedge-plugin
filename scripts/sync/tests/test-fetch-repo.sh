#!/usr/bin/env bash
# test-fetch-repo.sh — tests for fetch-repo.sh (covers T004a and T005a)
#
# T004a: arg validation, path-anchoring logic, CHANGED true/false detection
# T005a: pipe-delimited baseline tag message parse (read_baseline_commit)
#
# Usage: bash scripts/sync/tests/test-fetch-repo.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH_REPO="$SCRIPT_DIR/../fetch-repo.sh"
MOCKS_DIR="$SCRIPT_DIR/mocks"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

assert_exit() {
  local label="$1" expect_exit="$2"
  shift 2
  local output actual_exit
  output=$("$@" 2>&1) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -ne "$expect_exit" ]]; then
    fail "$label" "expected exit $expect_exit, got $actual_exit. Output: $output"
    return 1
  fi
  echo "$output"
  return 0
}

# ── Setup: temporary work dir ─────────────────────────────────────────────────

TMPWORK="$(mktemp -d)"
trap 'rm -rf "$TMPWORK"' EXIT

# ── Setup: local bare git repo fixture (used by path-anchoring + CHANGED tests) ─

BARE_REPO="$TMPWORK/bare-remote.git"

# Build a local bare repo with a contract directory structure.
REAL_GIT="$(which git)"
setup_bare_repo() {
  local work="$TMPWORK/work-init"
  mkdir -p "$work"
  "$REAL_GIT" -C "$work" init -q
  "$REAL_GIT" -C "$work" config user.email "test@test.com"
  "$REAL_GIT" -C "$work" config user.name "Test"

  # Contract directory (what sparse checkout should fetch)
  mkdir -p "$work/fastedge-plugin-source"
  echo '{"repo_id":"test"}' > "$work/fastedge-plugin-source/manifest.json"
  echo "# API Reference" > "$work/fastedge-plugin-source/api-reference.md"

  # Files outside the contract (should NOT be checked out)
  mkdir -p "$work/src" "$work/nested/fastedge-plugin-source"
  echo "source code" > "$work/src/foo.txt"
  echo "nested contract — should be excluded" > "$work/nested/fastedge-plugin-source/manifest.json"

  "$REAL_GIT" -C "$work" add .
  "$REAL_GIT" -C "$work" commit -qm "initial"
  "$REAL_GIT" -C "$work" tag v1.0.0
  "$REAL_GIT" -C "$work" clone --bare -q "$work" "$BARE_REPO"
  "$REAL_GIT" -C "$work" push --quiet "$BARE_REPO" --tags
}

setup_bare_repo

# Get the HEAD SHA from the bare repo (used for CHANGED tests)
HEAD_SHA=$("$REAL_GIT" -C "$BARE_REPO" rev-parse HEAD)

# ── Prepend mocks to PATH ─────────────────────────────────────────────────────
export PATH="$MOCKS_DIR:$PATH"

# ── Source fetch-repo.sh as a library (defines functions, runs nothing) ────────
# shellcheck source=../fetch-repo.sh
source "$FETCH_REPO"
set +e

# =============================================================================
# T004a — arg validation + path anchoring + CHANGED detection
# =============================================================================

echo ""
echo "T004a — fetch-repo.sh: argument validation, path anchoring, CHANGED detection"
echo "=============================================================================="

# (1) Missing args → exit 1 listing all missing flags
output=$(bash "$FETCH_REPO" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$output" | grep -q "Missing"; then
  pass "(1) missing args → exit 1 with 'Missing'"
else
  fail "(1) missing args → exit 1 with 'Missing'" "exit=$rc, output=$output"
fi

# (2) Unknown arg → exit 1
output=$(bash "$FETCH_REPO" --unknown-flag value 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$output" | grep -q "Unknown"; then
  pass "(2) unknown arg → exit 1 with 'Unknown'"
else
  fail "(2) unknown arg → exit 1 with 'Unknown'" "exit=$rc, output=$output"
fi

# (3) Path-anchoring: given contract-path "fastedge-plugin-source/",
#     only contract dir is checked out (nested/fastedge-plugin-source/ must be absent)
CHECKOUT_DIR_3="$TMPWORK/checkout-3"
export MOCK_GIT_REMOTE="$BARE_REPO"
export MOCK_GH_LATEST_TAG="v1.0.0"
export MOCK_GIT_LS_REMOTE=""   # no baseline → CHANGED=true

output3=$(bash "$FETCH_REPO" \
  --repo-url "https://github.com/example/test-repo" \
  --contract-path "fastedge-plugin-source/" \
  --repo-id "test-repo" \
  --ref "v1.0.0" \
  --checkout-dir "$CHECKOUT_DIR_3" 2>&1) && rc3=0 || rc3=$?

if [[ "$rc3" -ne 0 ]]; then
  fail "(3) path-anchoring: script exited $rc3. Output: $output3"
else
  # Contract files should be present
  if [[ -f "$CHECKOUT_DIR_3/fastedge-plugin-source/manifest.json" ]] && \
     [[ -f "$CHECKOUT_DIR_3/fastedge-plugin-source/api-reference.md" ]]; then
    # Files outside contract must NOT be present
    if [[ ! -f "$CHECKOUT_DIR_3/src/foo.txt" ]] && \
       [[ ! -f "$CHECKOUT_DIR_3/nested/fastedge-plugin-source/manifest.json" ]]; then
      pass "(3) path-anchoring: contract dir checked out, other paths excluded"
    else
      fail "(3) path-anchoring: files outside contract_path were incorrectly checked out"
    fi
  else
    fail "(3) path-anchoring: contract files missing in checkout"
  fi
fi

unset MOCK_GIT_REMOTE MOCK_GH_LATEST_TAG MOCK_GIT_LS_REMOTE

# (4) CHANGED=true when no baseline exists (ls-remote returns empty)
export MOCK_GIT_REMOTE="$BARE_REPO"
export MOCK_GH_LATEST_TAG="v1.0.0"
export MOCK_GIT_LS_REMOTE=""  # no tag on remote → first run

stdout4=$(bash "$FETCH_REPO" \
  --repo-url "https://github.com/example/test-repo" \
  --contract-path "fastedge-plugin-source/" \
  --repo-id "test-repo" \
  --ref "v1.0.0" \
  --checkout-dir "$TMPWORK/checkout-4" 2>/dev/null) && rc4=0 || rc4=$?

if [[ "$rc4" -eq 0 ]] && echo "$stdout4" | grep -q "CHANGED=true"; then
  pass "(4) CHANGED=true when no baseline (first run)"
else
  fail "(4) CHANGED=true when no baseline" "exit=$rc4, stdout=$stdout4"
fi

unset MOCK_GIT_REMOTE MOCK_GH_LATEST_TAG MOCK_GIT_LS_REMOTE

# (5) CHANGED=false when HEAD SHA matches baseline
export MOCK_GIT_REMOTE="$BARE_REPO"
export MOCK_GH_LATEST_TAG="v1.0.0"
export MOCK_GIT_LS_REMOTE="abc000def111 refs/tags/ref-update/test-repo"
export MOCK_GIT_CAT_FILE_OUTPUT="v1.0.0 | ${HEAD_SHA} | 2026-03-01T00:00:00Z"

stdout5=$(bash "$FETCH_REPO" \
  --repo-url "https://github.com/example/test-repo" \
  --contract-path "fastedge-plugin-source/" \
  --repo-id "test-repo" \
  --ref "v1.0.0" \
  --checkout-dir "$TMPWORK/checkout-5" 2>/dev/null) && rc5=0 || rc5=$?

if [[ "$rc5" -eq 0 ]] && echo "$stdout5" | grep -q "CHANGED=false"; then
  pass "(5) CHANGED=false when HEAD SHA matches baseline"
else
  fail "(5) CHANGED=false when HEAD SHA matches baseline" "exit=$rc5, stdout=$stdout5"
fi

unset MOCK_GIT_REMOTE MOCK_GH_LATEST_TAG MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# (6) CHANGED=true when HEAD SHA differs from baseline
export MOCK_GIT_REMOTE="$BARE_REPO"
export MOCK_GH_LATEST_TAG="v1.0.0"
export MOCK_GIT_LS_REMOTE="abc000def111 refs/tags/ref-update/test-repo"
export MOCK_GIT_CAT_FILE_OUTPUT="v0.9.0 | oldsha000000000000000000000000000000000000 | 2026-02-01T00:00:00Z"

stdout6=$(bash "$FETCH_REPO" \
  --repo-url "https://github.com/example/test-repo" \
  --contract-path "fastedge-plugin-source/" \
  --repo-id "test-repo" \
  --ref "v1.0.0" \
  --checkout-dir "$TMPWORK/checkout-6" 2>/dev/null) && rc6=0 || rc6=$?

if [[ "$rc6" -eq 0 ]] && echo "$stdout6" | grep -q "CHANGED=true"; then
  pass "(6) CHANGED=true when HEAD SHA differs from baseline"
else
  fail "(6) CHANGED=true when HEAD SHA differs from baseline" "exit=$rc6, stdout=$stdout6"
fi

unset MOCK_GIT_REMOTE MOCK_GH_LATEST_TAG MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# =============================================================================
# T005a — read_baseline_commit: pipe-delimited message parse
# (uses the sourced read_baseline_commit function + mocks/git via PATH)
# =============================================================================

echo ""
echo "T005a — read_baseline_commit: baseline tag message parse"
echo "========================================================="

# (1) Valid message "v2.0.0 | abc123 | 2026-03-09T00:00:00Z" → extracted SHA is "abc123"
export MOCK_GIT_LS_REMOTE="tagsha000 refs/tags/ref-update/repo-a"
export MOCK_GIT_CAT_FILE_OUTPUT="v2.0.0 | abc123 | 2026-03-09T00:00:00Z"

result1=$(read_baseline_commit "repo-a")
if [[ "$result1" == "abc123" ]]; then
  pass "(1) valid message → extracted SHA is 'abc123'"
else
  fail "(1) valid message → extracted SHA is 'abc123'" "got: '$result1'"
fi

unset MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# (2) Message with extra whitespace around pipes → SHA still extracted correctly
export MOCK_GIT_LS_REMOTE="tagsha000 refs/tags/ref-update/repo-b"
export MOCK_GIT_CAT_FILE_OUTPUT="v2.0.0  |  abc123  |  2026-03-09T00:00:00Z"

result2=$(read_baseline_commit "repo-b")
if [[ "$result2" == "abc123" ]]; then
  pass "(2) extra whitespace around pipes → SHA still extracted correctly"
else
  fail "(2) extra whitespace around pipes → SHA still extracted correctly" "got: '$result2'"
fi

unset MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# (3) Empty tag message → function returns empty string (not error)
export MOCK_GIT_LS_REMOTE="tagsha000 refs/tags/ref-update/repo-c"
export MOCK_GIT_CAT_FILE_OUTPUT=""

result3=$(read_baseline_commit "repo-c" 2>/dev/null)
if [[ -z "$result3" ]]; then
  pass "(3) empty tag message → returns empty string"
else
  fail "(3) empty tag message → returns empty string" "got: '$result3'"
fi

unset MOCK_GIT_LS_REMOTE MOCK_GIT_CAT_FILE_OUTPUT

# (4) No remote tag (ls-remote returns empty) → function returns empty string
export MOCK_GIT_LS_REMOTE=""

result4=$(read_baseline_commit "repo-d")
if [[ -z "$result4" ]]; then
  pass "(4) no remote tag → returns empty string"
else
  fail "(4) no remote tag → returns empty string" "got: '$result4'"
fi

unset MOCK_GIT_LS_REMOTE

# =============================================================================
# T013 — assert_allowed_paths_only(): post-checkout sparse-checkout assertion
# =============================================================================

echo ""
echo "T013 — assert_allowed_paths_only(): post-checkout sparse-checkout assertion"
echo "================================================================"

# (1) All files match a directory pattern → exit 0
ASSERT_DIR_1="$TMPWORK/assert-1"
mkdir -p "$ASSERT_DIR_1/src"
echo "content" > "$ASSERT_DIR_1/src/foo.txt"
echo "content" > "$ASSERT_DIR_1/src/bar.txt"
export MOCK_GIT_LS_FILES_OUTPUT="src/foo.txt
src/bar.txt"

output_a1=$( ( cd "$ASSERT_DIR_1" && assert_allowed_paths_only "test-repo" "/src/" ) 2>&1 ) \
  && rc_a1=0 || rc_a1=$?
if [[ "$rc_a1" -eq 0 ]]; then
  pass "(1) all files under /src/ → exit 0"
else
  fail "(1) all files under /src/ → exit 0" "exit=${rc_a1}, output=${output_a1}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (2) Exact file pattern → exit 0
ASSERT_DIR_2="$TMPWORK/assert-2"
mkdir -p "$ASSERT_DIR_2"
echo "content" > "$ASSERT_DIR_2/README.md"
export MOCK_GIT_LS_FILES_OUTPUT="README.md"

output_a2=$( ( cd "$ASSERT_DIR_2" && assert_allowed_paths_only "test-repo" "/README.md" ) 2>&1 ) \
  && rc_a2=0 || rc_a2=$?
if [[ "$rc_a2" -eq 0 ]]; then
  pass "(2) exact file pattern /README.md → exit 0"
else
  fail "(2) exact file pattern /README.md → exit 0" "exit=${rc_a2}, output=${output_a2}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (3) File outside declared paths → exit 1, names the offending file
ASSERT_DIR_3="$TMPWORK/assert-3"
mkdir -p "$ASSERT_DIR_3/src" "$ASSERT_DIR_3/docs"
echo "content" > "$ASSERT_DIR_3/src/foo.txt"
echo "content" > "$ASSERT_DIR_3/docs/guide.md"
export MOCK_GIT_LS_FILES_OUTPUT="src/foo.txt
docs/guide.md"

output_a3=$( ( cd "$ASSERT_DIR_3" && assert_allowed_paths_only "test-repo" "/src/" ) 2>&1 ) \
  && rc_a3=0 || rc_a3=$?
if [[ "$rc_a3" -eq 1 ]] && echo "$output_a3" | grep -qF "docs/guide.md"; then
  pass "(3) file outside /src/ → exit 1, offending path named"
else
  fail "(3) file outside /src/ → exit 1, offending path named" \
    "exit=${rc_a3}, output=${output_a3}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (4) Skip-worktree entry (in ls-files but not on disk) → not flagged
ASSERT_DIR_4="$TMPWORK/assert-4"
mkdir -p "$ASSERT_DIR_4/src"
echo "content" > "$ASSERT_DIR_4/src/foo.txt"
export MOCK_GIT_LS_FILES_OUTPUT="src/foo.txt
docs/guide.md"

output_a4=$( ( cd "$ASSERT_DIR_4" && assert_allowed_paths_only "test-repo" "/src/" ) 2>&1 ) \
  && rc_a4=0 || rc_a4=$?
if [[ "$rc_a4" -eq 0 ]]; then
  pass "(4) skip-worktree entry absent from disk → not flagged, exit 0"
else
  fail "(4) skip-worktree entry absent from disk → not flagged, exit 0" \
    "exit=${rc_a4}, output=${output_a4}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (5) Nested path does not match root-anchored directory pattern
ASSERT_DIR_5="$TMPWORK/assert-5"
mkdir -p "$ASSERT_DIR_5/src" "$ASSERT_DIR_5/nested/src"
echo "content" > "$ASSERT_DIR_5/src/foo.txt"
echo "content" > "$ASSERT_DIR_5/nested/src/bar.txt"
export MOCK_GIT_LS_FILES_OUTPUT="src/foo.txt
nested/src/bar.txt"

output_a5=$( ( cd "$ASSERT_DIR_5" && assert_allowed_paths_only "test-repo" "/src/" ) 2>&1 ) \
  && rc_a5=0 || rc_a5=$?
if [[ "$rc_a5" -eq 1 ]] && echo "$output_a5" | grep -qF "nested/src/bar.txt"; then
  pass "(5) nested/src/bar.txt does not match root-anchored /src/ → exit 1"
else
  fail "(5) nested/src/bar.txt does not match root-anchored /src/ → exit 1" \
    "exit=${rc_a5}, output=${output_a5}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# =============================================================================
# T013b — assert_allowed_paths_only(): glob pattern matching
# =============================================================================

echo ""
echo "T013b — assert_allowed_paths_only(): glob pattern matching"
echo "==========================================================="

# (6) Glob pattern matches files with prefix → exit 0
ASSERT_DIR_6="$TMPWORK/assert-6"
mkdir -p "$ASSERT_DIR_6/examples"
echo "content" > "$ASSERT_DIR_6/examples/cdn_auth.rs"
echo "content" > "$ASSERT_DIR_6/examples/cdn_geoblock.rs"
export MOCK_GIT_LS_FILES_OUTPUT="examples/cdn_auth.rs
examples/cdn_geoblock.rs"

output_a6=$( ( cd "$ASSERT_DIR_6" && assert_allowed_paths_only "test-repo" "/examples/cdn_*" ) 2>&1 ) \
  && rc_a6=0 || rc_a6=$?
if [[ "$rc_a6" -eq 0 ]]; then
  pass "(6) glob /examples/cdn_* matches cdn_ prefixed files → exit 0"
else
  fail "(6) glob /examples/cdn_* matches cdn_ prefixed files → exit 0" \
    "exit=${rc_a6}, output=${output_a6}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (7) Glob pattern rejects files that don't match → exit 1
ASSERT_DIR_7="$TMPWORK/assert-7"
mkdir -p "$ASSERT_DIR_7/examples"
echo "content" > "$ASSERT_DIR_7/examples/cdn_auth.rs"
echo "content" > "$ASSERT_DIR_7/examples/http_fetch.rs"
export MOCK_GIT_LS_FILES_OUTPUT="examples/cdn_auth.rs
examples/http_fetch.rs"

output_a7=$( ( cd "$ASSERT_DIR_7" && assert_allowed_paths_only "test-repo" "/examples/cdn_*" ) 2>&1 ) \
  && rc_a7=0 || rc_a7=$?
if [[ "$rc_a7" -eq 1 ]] && echo "$output_a7" | grep -qF "examples/http_fetch.rs"; then
  pass "(7) glob /examples/cdn_* rejects http_fetch.rs → exit 1"
else
  fail "(7) glob /examples/cdn_* rejects http_fetch.rs → exit 1" \
    "exit=${rc_a7}, output=${output_a7}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (8) Multiple patterns: glob + directory prefix → exit 0
ASSERT_DIR_8="$TMPWORK/assert-8"
mkdir -p "$ASSERT_DIR_8/examples" "$ASSERT_DIR_8/fastedge-plugin-source"
echo "content" > "$ASSERT_DIR_8/examples/cdn_auth.rs"
echo "content" > "$ASSERT_DIR_8/examples/cdn_geoblock.rs"
echo "content" > "$ASSERT_DIR_8/fastedge-plugin-source/manifest.json"
export MOCK_GIT_LS_FILES_OUTPUT="examples/cdn_auth.rs
examples/cdn_geoblock.rs
fastedge-plugin-source/manifest.json"

output_a8=$( ( cd "$ASSERT_DIR_8" && assert_allowed_paths_only "test-repo" \
  "/fastedge-plugin-source/" "/examples/cdn_*" ) 2>&1 ) \
  && rc_a8=0 || rc_a8=$?
if [[ "$rc_a8" -eq 0 ]]; then
  pass "(8) mixed: dir prefix + glob pattern → exit 0"
else
  fail "(8) mixed: dir prefix + glob pattern → exit 0" \
    "exit=${rc_a8}, output=${output_a8}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (9) Question-mark glob pattern → matches single character
ASSERT_DIR_9="$TMPWORK/assert-9"
mkdir -p "$ASSERT_DIR_9/examples"
echo "content" > "$ASSERT_DIR_9/examples/app_a.rs"
echo "content" > "$ASSERT_DIR_9/examples/app_b.rs"
export MOCK_GIT_LS_FILES_OUTPUT="examples/app_a.rs
examples/app_b.rs"

output_a9=$( ( cd "$ASSERT_DIR_9" && assert_allowed_paths_only "test-repo" "/examples/app_?.rs" ) 2>&1 ) \
  && rc_a9=0 || rc_a9=$?
if [[ "$rc_a9" -eq 0 ]]; then
  pass "(9) glob /examples/app_?.rs matches single-char wildcard → exit 0"
else
  fail "(9) glob /examples/app_?.rs matches single-char wildcard → exit 0" \
    "exit=${rc_a9}, output=${output_a9}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# (10) Glob does NOT match across path separators (no recursive match)
ASSERT_DIR_10="$TMPWORK/assert-10"
mkdir -p "$ASSERT_DIR_10/examples/cdn_subdir"
echo "content" > "$ASSERT_DIR_10/examples/cdn_subdir/nested.rs"
export MOCK_GIT_LS_FILES_OUTPUT="examples/cdn_subdir/nested.rs"

output_a10=$( ( cd "$ASSERT_DIR_10" && assert_allowed_paths_only "test-repo" "/examples/cdn_*" ) 2>&1 ) \
  && rc_a10=0 || rc_a10=$?
if [[ "$rc_a10" -eq 1 ]] && echo "$output_a10" | grep -qF "examples/cdn_subdir/nested.rs"; then
  pass "(10) glob /examples/cdn_* does not match across / → exit 1"
else
  fail "(10) glob /examples/cdn_* does not match across / → exit 1" \
    "exit=${rc_a10}, output=${output_a10}"
fi
unset MOCK_GIT_LS_FILES_OUTPUT

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
