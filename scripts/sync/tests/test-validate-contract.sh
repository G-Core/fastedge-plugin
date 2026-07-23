#!/usr/bin/env bash
# test-validate-contract.sh — test suite for validate-contract.sh
# Usage: bash scripts/sync/tests/test-validate-contract.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/../validate-contract.sh"
FIXTURES="$SCRIPT_DIR/fixtures/validate-contract"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "       $2"; FAIL=$((FAIL + 1)); }

# run <label> <fixture> <expect_exit> <expect_pattern> [repo_root]
run() {
  local label="$1" fixture="$2" expect_exit="$3" expect_pattern="$4" repo_root="${5:-}"
  local output
  if [[ -n "$repo_root" ]]; then
    output=$(bash "$VALIDATE" "$fixture" "$repo_root" 2>&1)
  else
    output=$(bash "$VALIDATE" "$fixture" 2>&1)
  fi
  local actual_exit=$?
  if [[ "$actual_exit" -ne "$expect_exit" ]]; then
    fail "$label" "expected exit $expect_exit, got $actual_exit. Output: $output"
    return
  fi
  if [[ -n "$expect_pattern" ]] && ! echo "$output" | grep -q "$expect_pattern"; then
    fail "$label" "output did not match '$expect_pattern'. Got: $output"
    return
  fi
  pass "$label"
}

echo "validate-contract.sh tests"
echo "=========================="

# Happy path — with repo_root so Rule 3 checks file existence
run "valid contract passes all rules (with repo_root)" \
  "$FIXTURES/valid" 0 "validation passed" "$FIXTURES/valid"

# Happy path — without repo_root (manifest-only validation)
run "valid contract passes manifest-only validation (no repo_root)" \
  "$FIXTURES/valid" 0 "validation passed"

# Rule 1: manifest exists
run "Rule 1: missing manifest.json fails" \
  "$FIXTURES/missing-manifest" 1 "Rule 1"

run "Rule 1: invalid JSON fails" \
  "$FIXTURES/bad-json" 1 "Rule 1"

# Rule 2: schema version
run "Rule 2: missing \$schema field fails" \
  "$FIXTURES/no-schema" 1 "Rule 2"

# Rule 3: required files (with repo_root)
run "Rule 3: missing required file in strict mode fails" \
  "$FIXTURES/missing-required" 1 "Rule 3" "$FIXTURES/missing-required"

run "Rule 3: empty required file in strict mode fails" \
  "$FIXTURES/empty-required" 1 "Rule 3" "$FIXTURES/empty-required"

# Rule 3: without repo_root, manifest-only — no file checks, should pass
run "Rule 3: missing required file without repo_root passes (manifest-only)" \
  "$FIXTURES/missing-required" 0 "validation passed"

# Rule 5: target_mapping paths
run "Rule 5: target_mapping path outside plugins/ fails" \
  "$FIXTURES/bad-target-path" 1 "Rule 5"

# Rule 3 + strict mode: required file missing (with repo_root)
run "strict mode: missing required file fails" \
  "$FIXTURES/strict-mode" 1 "Rule 3" "$FIXTURES/strict-mode"

# strict_fields: api-reference missing fails even in advisory mode (with repo_root)
run "strict_fields: strict field missing fails in advisory mode" \
  "$FIXTURES/strict-fields" 1 "Rule 3" "$FIXTURES/strict-fields"

# Rule 3: path traversal rejected (always an error, even without repo_root)
run "Rule 3: path traversal (../) in files rejected" \
  "$FIXTURES/path-traversal" 1 "Unsafe file path"

run "Rule 3: .git/ access in files rejected" \
  "$FIXTURES/dotgit-access" 1 "Unsafe file path"

run "Rule 3: absolute path in files rejected" \
  "$FIXTURES/absolute-path" 1 "Unsafe file path"

# No argument
label="no argument: exits with usage error"
no_arg_output=$(bash "$VALIDATE" 2>&1) && no_arg_exit=0 || no_arg_exit=$?
if [[ "$no_arg_exit" -eq 1 ]] && echo "$no_arg_output" | grep -q "Usage"; then
  pass "$label"
else
  fail "$label" "exit=$no_arg_exit. Output: $no_arg_output"
fi

# Nonexistent directory
run "nonexistent directory fails" \
  "$FIXTURES/does-not-exist" 1 "Contract directory not found"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
