#!/usr/bin/env bash
# test-manage-pr.sh — tests for manage-pr.sh
#
# Verifies --base flag propagation, PR URL emission, and findings table formatting.
#
# Usage: bash scripts/sync/tests/test-manage-pr.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGE_PR="$SCRIPT_DIR/../manage-pr.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

# ── Helper: create a self-contained gh mock ───────────────────────────────────
# make_gh_mock <mock_dir> [existing_pr_number]
#
# Writes a gh stub to <mock_dir>/gh that:
#   - handles label list/create, pr list/create/edit/view
#   - writes "pr create" invocation args to <mock_dir>/pr-create.log
#   - returns <existing_pr_number> for "pr list" (empty = no existing PR)
make_gh_mock() {
  local mock_dir="$1" existing_pr="${2:-}"
  mkdir -p "$mock_dir"
  printf '%s\n' "$existing_pr" > "$mock_dir/existing_pr"
  cat > "$mock_dir/gh" <<'GHEOF'
#!/usr/bin/env bash
MOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXISTING_PR="$(cat "$MOCK_DIR/existing_pr" 2>/dev/null || echo "")"

case "$1 $2" in
  "label list")
    printf 'auto-ref-update\nneeds-review\nmissing-intent-skill\n'
    exit 0 ;;
  "label create")
    exit 0 ;;
  "pr list")
    echo "$EXISTING_PR"
    exit 0 ;;
  "pr create")
    echo "$*" >> "$MOCK_DIR/pr-create.log"
    # Capture --body content to a separate file for assertion
    body_next=0
    for arg in "$@"; do
      if [[ "$body_next" -eq 1 ]]; then
        printf '%s' "$arg" > "$MOCK_DIR/pr-body.txt"
        body_next=0
      elif [[ "$arg" == "--body" ]]; then
        body_next=1
      fi
    done
    echo "42" > "$MOCK_DIR/existing_pr"
    echo "https://github.com/example/repo/pull/42" >&2
    exit 0 ;;
  "pr edit")
    echo "$*" >> "$MOCK_DIR/pr-edit.log"
    exit 0 ;;
  "pr view")
    echo "https://github.com/example/repo/pull/$3"
    exit 0 ;;
  *)
    echo "gh stub: unhandled: $*" >&2
    exit 1 ;;
esac
GHEOF
  chmod +x "$mock_dir/gh"
}

# ── Common required args for manage-pr.sh ────────────────────────────────────
COMMON_ARGS=(
  --repo-id       "fastedge-test"
  --ref           "v1.2.3"
  --commit        "abc123def456"
  --changed-files "skills/fastedge-docs/reference/sdk-reference-js.md"
  --verdict       "ACCEPT"
  --findings      "Looks good."
)

TMPWORK="$(mktemp -d)"
trap 'rm -rf "$TMPWORK"' EXIT

# =============================================================================
echo ""
echo "manage-pr.sh — --base argument propagation"
echo "==========================================="
# =============================================================================

# (1) --base my-feature-branch → gh pr create called with --base my-feature-branch
MOCK_DIR_1="$TMPWORK/mock-1"
make_gh_mock "$MOCK_DIR_1"
LOG_1="$MOCK_DIR_1/pr-create.log"

output1=$(PATH="$MOCK_DIR_1:$PATH" bash "$MANAGE_PR" \
  "${COMMON_ARGS[@]}" --base "my-feature-branch" 2>&1) && rc1=0 || rc1=$?

if [[ "$rc1" -eq 0 ]] && grep -q -- "--base my-feature-branch" "$LOG_1" 2>/dev/null; then
  pass "(1) --base my-feature-branch → gh pr create called with --base my-feature-branch"
else
  fail "(1) --base my-feature-branch → gh pr create called with --base my-feature-branch" \
    "exit=$rc1, log=$(cat "$LOG_1" 2>/dev/null || echo '(empty)'), output=$output1"
fi

# (2) --base main → gh pr create called with --base main
MOCK_DIR_2="$TMPWORK/mock-2"
make_gh_mock "$MOCK_DIR_2"
LOG_2="$MOCK_DIR_2/pr-create.log"

output2=$(PATH="$MOCK_DIR_2:$PATH" bash "$MANAGE_PR" \
  "${COMMON_ARGS[@]}" --base "main" 2>&1) && rc2=0 || rc2=$?

if [[ "$rc2" -eq 0 ]] && grep -q -- "--base main" "$LOG_2" 2>/dev/null; then
  pass "(2) --base main → gh pr create called with --base main"
else
  fail "(2) --base main → gh pr create called with --base main" \
    "exit=$rc2, log=$(cat "$LOG_2" 2>/dev/null || echo '(empty)'), output=$output2"
fi

# (3) --base omitted → fallback: gh pr create called with --base main
MOCK_DIR_3="$TMPWORK/mock-3"
make_gh_mock "$MOCK_DIR_3"
LOG_3="$MOCK_DIR_3/pr-create.log"

output3=$(PATH="$MOCK_DIR_3:$PATH" bash "$MANAGE_PR" \
  "${COMMON_ARGS[@]}" 2>&1) && rc3=0 || rc3=$?

if [[ "$rc3" -eq 0 ]] && grep -q -- "--base main" "$LOG_3" 2>/dev/null; then
  pass "(3) --base omitted → fallback to --base main"
else
  fail "(3) --base omitted → fallback to --base main" \
    "exit=$rc3, log=$(cat "$LOG_3" 2>/dev/null || echo '(empty)'), output=$output3"
fi

# (4) Existing PR → gh pr edit path taken; gh pr create NOT called
MOCK_DIR_4="$TMPWORK/mock-4"
make_gh_mock "$MOCK_DIR_4" "99"
LOG_4="$MOCK_DIR_4/pr-create.log"

output4=$(PATH="$MOCK_DIR_4:$PATH" bash "$MANAGE_PR" \
  "${COMMON_ARGS[@]}" --base "my-feature-branch" 2>&1) && rc4=0 || rc4=$?

if [[ "$rc4" -eq 0 ]] && [[ ! -s "$LOG_4" ]]; then
  pass "(4) existing PR → gh pr edit used; gh pr create not called"
else
  fail "(4) existing PR → gh pr edit used; gh pr create not called" \
    "exit=$rc4, log=$(cat "$LOG_4" 2>/dev/null || echo '(empty)'), output=$output4"
fi

# =============================================================================
echo ""
echo "manage-pr.sh — PR URL emitted to stdout"
echo "========================================"
# =============================================================================

# (5) Create path → stdout contains the PR URL
MOCK_DIR_5="$TMPWORK/mock-5"
make_gh_mock "$MOCK_DIR_5"

url5=$(PATH="$MOCK_DIR_5:$PATH" bash "$MANAGE_PR" \
  "${COMMON_ARGS[@]}" --base "main" 2>/dev/null) && rc5=0 || rc5=$?

if [[ "$rc5" -eq 0 ]] && [[ "$url5" == "https://github.com/example/repo/pull/42" ]]; then
  pass "(5) create path: stdout contains PR URL"
else
  fail "(5) create path: stdout contains PR URL" \
    "exit=$rc5, url='$url5'"
fi

# (6) Edit path (existing PR #99) → stdout contains the PR URL
MOCK_DIR_6="$TMPWORK/mock-6"
make_gh_mock "$MOCK_DIR_6" "99"

url6=$(PATH="$MOCK_DIR_6:$PATH" bash "$MANAGE_PR" \
  "${COMMON_ARGS[@]}" --base "main" 2>/dev/null) && rc6=0 || rc6=$?

if [[ "$rc6" -eq 0 ]] && [[ "$url6" == "https://github.com/example/repo/pull/99" ]]; then
  pass "(6) edit path: stdout contains PR URL"
else
  fail "(6) edit path: stdout contains PR URL" \
    "exit=$rc6, url='$url6'"
fi

# =============================================================================
echo ""
echo "manage-pr.sh — findings table formatting"
echo "========================================="
# =============================================================================

# Multi-file ACCEPT findings in the format process-repos.sh produces
ACCEPT_FINDINGS="**plugins/gcore-fastedge/skills/test/reference/test-framework.md**: ACCEPT

None.

**plugins/gcore-fastedge/skills/test/reference/server-api.md**: ACCEPT

None.

**plugins/gcore-fastedge/skills/test/reference/runner-internals.md**: ACCEPT

None."

ACCEPT_ARGS=(
  --repo-id       "fastedge-test"
  --ref           "v1.2.3"
  --commit        "abc123def456"
  --changed-files "skills/test/reference/test-framework.md skills/test/reference/server-api.md skills/test/reference/runner-internals.md"
  --verdict       "ACCEPT"
  --findings      "$ACCEPT_FINDINGS"
  --base          "main"
)

# (7) ACCEPT findings → table header present in PR body
MOCK_DIR_7="$TMPWORK/mock-7"
make_gh_mock "$MOCK_DIR_7"

output7=$(PATH="$MOCK_DIR_7:$PATH" bash "$MANAGE_PR" \
  "${ACCEPT_ARGS[@]}" 2>&1) && rc7=0 || rc7=$?
BODY_7="$(cat "$MOCK_DIR_7/pr-body.txt" 2>/dev/null || echo "")"

if [[ "$rc7" -eq 0 ]] && echo "$BODY_7" | grep -qF "| File | Status | Comments |"; then
  pass "(7) ACCEPT findings: table header present in PR body"
else
  fail "(7) ACCEPT findings: table header present in PR body" \
    "exit=$rc7, body=$(head -20 "$MOCK_DIR_7/pr-body.txt" 2>/dev/null || echo '(empty)')"
fi

# (8) ACCEPT findings → ✅ icon in verdict line
if echo "$BODY_7" | grep -qF '✅ **ACCEPT**'; then
  pass "(8) ACCEPT findings: ✅ ACCEPT verdict icon in body"
else
  fail "(8) ACCEPT findings: ✅ ACCEPT verdict icon in body" \
    "body snippet=$(echo "$BODY_7" | grep -i 'verdict' || echo '(not found)')"
fi

# (9) ACCEPT findings → all files show ✅ status, dash for comments
if echo "$BODY_7" | grep -q '| ✅ | — |'; then
  pass "(9) ACCEPT findings: files show ✅ with — for comments"
else
  fail "(9) ACCEPT findings: files show ✅ with — for comments" \
    "table rows=$(echo "$BODY_7" | grep '^\|' || echo '(none)')"
fi

# (10) ACCEPT findings → no Reviewer Details section (no rejects)
if ! echo "$BODY_7" | grep -qF "### Reviewer Details"; then
  pass "(10) ACCEPT findings: no Reviewer Details section"
else
  fail "(10) ACCEPT findings: no Reviewer Details section (should only appear for REJECT)"
fi

# Mixed ACCEPT/REJECT findings
REJECT_FINDINGS="**plugins/gcore-fastedge/skills/test/reference/test-framework.md**: ACCEPT

None.

**plugins/gcore-fastedge/skills/test/reference/server-api.md**: REJECT

Missing parameter documentation for handleRequest method. The return type is incorrectly documented as void when it should be Response.

**plugins/gcore-fastedge/skills/test/reference/runner-internals.md**: ACCEPT

None."

REJECT_ARGS=(
  --repo-id       "fastedge-test"
  --ref           "v1.2.3"
  --commit        "abc123def456"
  --changed-files "skills/test/reference/test-framework.md skills/test/reference/server-api.md skills/test/reference/runner-internals.md"
  --verdict       "REJECT"
  --findings      "$REJECT_FINDINGS"
  --base          "main"
)

# (11) REJECT findings → ❌ REJECT verdict icon
MOCK_DIR_11="$TMPWORK/mock-11"
make_gh_mock "$MOCK_DIR_11"

output11=$(PATH="$MOCK_DIR_11:$PATH" bash "$MANAGE_PR" \
  "${REJECT_ARGS[@]}" 2>&1) && rc11=0 || rc11=$?
BODY_11="$(cat "$MOCK_DIR_11/pr-body.txt" 2>/dev/null || echo "")"

if [[ "$rc11" -eq 0 ]] && echo "$BODY_11" | grep -qF '❌ **REJECT**'; then
  pass "(11) REJECT findings: ❌ REJECT verdict icon in body"
else
  fail "(11) REJECT findings: ❌ REJECT verdict icon in body" \
    "exit=$rc11, body snippet=$(echo "$BODY_11" | grep -i 'verdict' || echo '(not found)')"
fi

# (12) REJECT findings → rejected file shows ❌ with issue count in table
if echo "$BODY_11" | grep -q 'server-api.md.*| ❌ |.*issue.*see details'; then
  pass "(12) REJECT findings: rejected file shows ❌ with issue count"
else
  fail "(12) REJECT findings: rejected file shows ❌ with issue count" \
    "table rows=$(echo "$BODY_11" | grep 'server-api' || echo '(none)')"
fi

# (13) REJECT findings → accepted files still show ✅ in table
if echo "$BODY_11" | grep -q 'test-framework.md.*| ✅ |' && \
   echo "$BODY_11" | grep -q 'runner-internals.md.*| ✅ |'; then
  pass "(13) REJECT findings: accepted files still show ✅ in table"
else
  fail "(13) REJECT findings: accepted files still show ✅ in table" \
    "table rows=$(echo "$BODY_11" | grep '| ✅ |' || echo '(none)')"
fi

# (14) REJECT findings → Reviewer Details section present with expandable details
if echo "$BODY_11" | grep -qF "### Reviewer Details" && \
   echo "$BODY_11" | grep -qF "<details>" && \
   echo "$BODY_11" | grep -qF "server-api.md"; then
  pass "(14) REJECT findings: Reviewer Details section with expandable details"
else
  fail "(14) REJECT findings: Reviewer Details section with expandable details" \
    "body tail=$(echo "$BODY_11" | tail -15 || echo '(empty)')"
fi

# (15) REJECT findings → detail section contains full findings text
if echo "$BODY_11" | grep -qF "Missing parameter documentation for handleRequest"; then
  pass "(15) REJECT findings: full findings text in details section"
else
  fail "(15) REJECT findings: full findings text in details section"
fi

# =============================================================================
echo ""
echo "manage-pr.sh — multi-line REJECT findings"
echo "=========================================="
# =============================================================================

# Multi-line bullet-point findings (realistic reviewer output)
MULTILINE_FINDINGS="**plugins/gcore-fastedge/skills/test/reference/test-framework.md**: ACCEPT

None.

**plugins/gcore-fastedge/skills/test/reference/server-api.md**: REJECT

- Missing parameter documentation for handleRequest method
- Return type incorrectly documented as void, should be Response
- Error codes section references non-existent enum FastEdgeError

**plugins/gcore-fastedge/skills/test/reference/runner-internals.md**: ACCEPT

None."

MULTILINE_ARGS=(
  --repo-id       "fastedge-test"
  --ref           "v1.2.3"
  --commit        "abc123def456"
  --changed-files "skills/test/reference/test-framework.md skills/test/reference/server-api.md skills/test/reference/runner-internals.md"
  --verdict       "REJECT"
  --findings      "$MULTILINE_FINDINGS"
  --base          "main"
)

MOCK_DIR_16="$TMPWORK/mock-16"
make_gh_mock "$MOCK_DIR_16"

output16=$(PATH="$MOCK_DIR_16:$PATH" bash "$MANAGE_PR" \
  "${MULTILINE_ARGS[@]}" 2>&1) && rc16=0 || rc16=$?
BODY_16="$(cat "$MOCK_DIR_16/pr-body.txt" 2>/dev/null || echo "")"

# (16) Multi-line REJECT → table shows "3 issues — see details"
if [[ "$rc16" -eq 0 ]] && echo "$BODY_16" | grep -q 'server-api.md.*| ❌ | 3 issues'; then
  pass "(16) multi-line REJECT: table shows issue count"
else
  fail "(16) multi-line REJECT: table shows issue count" \
    "exit=$rc16, row=$(echo "$BODY_16" | grep 'server-api' || echo '(none)')"
fi

# (17) Multi-line REJECT → details block preserves all bullet points
# Extract only content between <details> and </details> to avoid matching Changes section
details_content=$(echo "$BODY_16" | sed -n '/<details>/,/<\/details>/p')
bullet_count=$(echo "$details_content" | grep -c '^\- ' || true)
if [[ "$bullet_count" -eq 3 ]]; then
  pass "(17) multi-line REJECT: all 3 bullet points preserved in details"
else
  fail "(17) multi-line REJECT: all 3 bullet points preserved in details" \
    "expected 3 bullets, found $bullet_count"
fi

# (18) Multi-line REJECT → each finding line is intact
if echo "$BODY_16" | grep -qF "Missing parameter documentation for handleRequest" && \
   echo "$BODY_16" | grep -qF "Return type incorrectly documented as void" && \
   echo "$BODY_16" | grep -qF "Error codes section references non-existent enum"; then
  pass "(18) multi-line REJECT: each finding line intact in details"
else
  fail "(18) multi-line REJECT: each finding line intact in details"
fi

# (19) Single-line REJECT → shows "1 issue — see details"
SINGLE_REJECT_FINDINGS="**plugins/gcore-fastedge/skills/test/reference/server-api.md**: REJECT

Frontmatter commit SHA does not match the source."

SINGLE_REJECT_ARGS=(
  --repo-id       "fastedge-test"
  --ref           "v1.2.3"
  --commit        "abc123def456"
  --changed-files "skills/test/reference/server-api.md"
  --verdict       "REJECT"
  --findings      "$SINGLE_REJECT_FINDINGS"
  --base          "main"
)

MOCK_DIR_19="$TMPWORK/mock-19"
make_gh_mock "$MOCK_DIR_19"

output19=$(PATH="$MOCK_DIR_19:$PATH" bash "$MANAGE_PR" \
  "${SINGLE_REJECT_ARGS[@]}" 2>&1) && rc19=0 || rc19=$?
BODY_19="$(cat "$MOCK_DIR_19/pr-body.txt" 2>/dev/null || echo "")"

if [[ "$rc19" -eq 0 ]] && echo "$BODY_19" | grep -q 'server-api.md.*| ❌ | 1 issue — see details'; then
  pass "(19) single-line REJECT: table shows '1 issue — see details'"
else
  fail "(19) single-line REJECT: table shows '1 issue — see details'" \
    "exit=$rc19, row=$(echo "$BODY_19" | grep 'server-api' || echo '(none)')"
fi

# =============================================================================
echo ""
echo "manage-pr.sh — unstructured findings fallback"
echo "==============================================="
# =============================================================================

# (20) Unstructured findings (no **file**: VERDICT headers) → raw text in collapsible block
UNSTRUCTURED_FINDINGS="All files look good. No issues found with the generated documentation."

UNSTRUCTURED_ARGS=(
  --repo-id       "fastedge-test"
  --ref           "v1.2.3"
  --commit        "abc123def456"
  --changed-files "skills/test/reference/server-api.md"
  --verdict       "ACCEPT"
  --findings      "$UNSTRUCTURED_FINDINGS"
  --base          "main"
)

MOCK_DIR_20="$TMPWORK/mock-20"
make_gh_mock "$MOCK_DIR_20"

output20=$(PATH="$MOCK_DIR_20:$PATH" bash "$MANAGE_PR" \
  "${UNSTRUCTURED_ARGS[@]}" 2>&1) && rc20=0 || rc20=$?
BODY_20="$(cat "$MOCK_DIR_20/pr-body.txt" 2>/dev/null || echo "")"

if [[ "$rc20" -eq 0 ]] && echo "$BODY_20" | grep -qF "Reviewer Findings"; then
  pass "(20) unstructured findings: collapsible Reviewer Findings section present"
else
  fail "(20) unstructured findings: collapsible Reviewer Findings section present" \
    "exit=$rc20, body=$(echo "$BODY_20" | head -20 || echo '(empty)')"
fi

# (21) Unstructured findings → raw text preserved in body
if echo "$BODY_20" | grep -qF "All files look good"; then
  pass "(21) unstructured findings: raw findings text preserved in body"
else
  fail "(21) unstructured findings: raw findings text preserved in body"
fi

# (22) Unstructured findings → no table header (no rows to show)
if ! echo "$BODY_20" | grep -qF "| File | Status | Comments |"; then
  pass "(22) unstructured findings: no empty table rendered"
else
  fail "(22) unstructured findings: no empty table rendered"
fi

# (23) Unstructured findings → verdict line still present
if echo "$BODY_20" | grep -qF '✅ **ACCEPT**'; then
  pass "(23) unstructured findings: verdict line still present"
else
  fail "(23) unstructured findings: verdict line still present"
fi

# =============================================================================
echo ""
echo "manage-pr.sh — missing-intent-skill label"
echo "==========================================="
# =============================================================================

# (24) --missing-intent true → gh pr edit --add-label missing-intent-skill called
MOCK_DIR_24="$TMPWORK/mock-24"
make_gh_mock "$MOCK_DIR_24"

output24=$(PATH="$MOCK_DIR_24:$PATH" bash "$MANAGE_PR" \
  "${COMMON_ARGS[@]}" --missing-intent "true" --base "main" 2>&1) && rc24=0 || rc24=$?
EDIT_LOG_24="$(cat "$MOCK_DIR_24/pr-edit.log" 2>/dev/null || echo "")"

if [[ "$rc24" -eq 0 ]] && echo "$EDIT_LOG_24" | grep -qF -- "--add-label missing-intent-skill"; then
  pass "(24) --missing-intent true: missing-intent-skill label added"
else
  fail "(24) --missing-intent true: missing-intent-skill label added" \
    "exit=$rc24, edit_log='$EDIT_LOG_24'"
fi

# (25) --missing-intent omitted → missing-intent-skill label NOT added
MOCK_DIR_25="$TMPWORK/mock-25"
make_gh_mock "$MOCK_DIR_25"

output25=$(PATH="$MOCK_DIR_25:$PATH" bash "$MANAGE_PR" \
  "${COMMON_ARGS[@]}" --base "main" 2>&1) && rc25=0 || rc25=$?
EDIT_LOG_25="$(cat "$MOCK_DIR_25/pr-edit.log" 2>/dev/null || echo "")"

if [[ "$rc25" -eq 0 ]] && ! echo "$EDIT_LOG_25" | grep -qF "missing-intent-skill"; then
  pass "(25) --missing-intent omitted: missing-intent-skill label not added"
else
  fail "(25) --missing-intent omitted: missing-intent-skill label not added" \
    "exit=$rc25, edit_log='$EDIT_LOG_25'"
fi

# =============================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
