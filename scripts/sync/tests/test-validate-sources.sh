#!/usr/bin/env bash
# test-validate-sources.sh — test suite for validate-sources.sh (v2 format)
# Usage: bash scripts/sync/tests/test-validate-sources.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/../validate-sources.sh"
FIXTURES="$SCRIPT_DIR/fixtures/validate-sources"

# Prepend mocks dir so our gh mock takes precedence over the real gh
export PATH="$SCRIPT_DIR/mocks:$PATH"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "       $2"; FAIL=$((FAIL + 1)); }

run() {
  local label="$1" fixture="$2" expect_exit="$3" expect_pattern="$4"
  local output
  output=$(bash "$VALIDATE" "$fixture" 2>&1)
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

echo "validate-sources.sh tests (v2)"
echo "==============================="

# Happy path
run "valid sources.json passes all rules" \
  "$FIXTURES/valid.json" 0 "validation passed"

# Rule 0: version must be 2.0
run "Rule 0: v1 version rejected" \
  "$FIXTURES/rule0-bad-version.json" 1 "Rule 0"

# Rule 1
run "Rule 1: duplicate repo IDs fail" \
  "$FIXTURES/rule1-duplicate-ids.json" 1 "Rule 1"

# Rule 2
run "Rule 2: unreachable github_url fails" \
  "$FIXTURES/rule2-bad-url.json" 1 "Rule 2"

# Rule 3 (was rule 4 — same agent)
run "Rule 3: generator_agent equals reviewer_agent fails" \
  "$FIXTURES/rule4-same-agent.json" 1 "Rule 3"

# Rule 4: contract_path must end with /
run "Rule 4: contract_path without trailing slash fails" \
  "$FIXTURES/rule4-no-trailing-slash-contract.json" 1 "Rule 4"

# Rule 5: intent_dir must exist
run "Rule 5: nonexistent intent_dir fails" \
  "$FIXTURES/rule5-missing-intent-dir.json" 1 "Rule 5"

# Rule 6: no v1 fields
run "Rule 6: v1 fields (updates[], sparse_paths) rejected" \
  "$FIXTURES/rule6-v1-fields.json" 1 "Rule 6"

# Missing argument
label="no argument: exits with usage error"
no_arg_output=$(bash "$VALIDATE" 2>&1) && no_arg_exit=0 || no_arg_exit=$?
if [[ "$no_arg_exit" -eq 1 ]] && echo "$no_arg_output" | grep -q "Usage"; then
  pass "$label"
else
  fail "$label" "exit=$no_arg_exit. Output: $no_arg_output"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
