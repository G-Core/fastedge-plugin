#!/usr/bin/env bash
# test-process-repos.sh — unit tests for process-repos.sh orchestration logic (v2)
#
# Coverage (things testable without GitHub, Claude, or OpenAI):
#   (1) trigger=release → skipped when no FILTER_REPO_ID set
#   (2) FILTER_REPO_ID overrides trigger check, repo is processed
#   (3) CHANGED=false from fetch → no-changes skip, run_agents not called
#   (4) dry_run=true gate → fetch+generate+review run, writes/PR/baseline skipped
#   (5) REJECT verdict propagates → summary icon is ⚠️, not ✅
#   (6) fetch failure → OVERALL_FAILED set, exits 1, summary row shows ❌ failed
#
# Usage: bash scripts/sync/tests/test-process-repos.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROCESS_REPOS="$SCRIPT_DIR/../process-repos.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

# Source process-repos.sh as a library (sourcing guard skips _process_repos_main)
# shellcheck source=../process-repos.sh
source "$PROCESS_REPOS"
set +e  # process-repos.sh sets -euo pipefail; restore for test assertions

# ── Shared fixtures ───────────────────────────────────────────────────────────

TMPWORK="$(mktemp -d)"
trap 'rm -rf "$TMPWORK"' EXIT

# Redirect step summary to a temp file so tests can ignore it cleanly
export GITHUB_STEP_SUMMARY="${TMPWORK}/step-summary.md"
STEP_SUMMARY="$GITHUB_STEP_SUMMARY"

# Helper: write a one-repo sources.json v2 fixture
# Usage: make_fixture <trigger> [<id>]
make_fixture() {
  local trigger="${1:-release}" id="${2:-test-repo}"
  cat > "${TMPWORK}/sources.json" <<EOF
{
  "version": "2.0",
  "repos": [
    {
      "id": "${id}",
      "github_url": "https://github.com/test/${id}",
      "ref": "latest-release",
      "trigger": "${trigger}",
      "contract_path": "fastedge-plugin-source/",
      "intent_dir": "agent-intent-skills/fastedge-test/",
      "generator_agent": "claude",
      "reviewer_agent": "kimi"
    }
  ]
}
EOF
  export SOURCES_FILE="${TMPWORK}/sources.json"
}

# Helper: write a two-repo sources.json v2 fixture (both trigger=schedule)
make_fixture_two_repos() {
  cat > "${TMPWORK}/sources.json" <<'EOF'
{
  "version": "2.0",
  "repos": [
    {
      "id": "repo-a",
      "github_url": "https://github.com/test/repo-a",
      "ref": "latest-release",
      "trigger": "schedule",
      "contract_path": "fastedge-plugin-source/",
      "intent_dir": "agent-intent-skills/repo-a/",
      "generator_agent": "claude",
      "reviewer_agent": "kimi"
    },
    {
      "id": "repo-b",
      "github_url": "https://github.com/test/repo-b",
      "ref": "latest-release",
      "trigger": "schedule",
      "contract_path": "fastedge-plugin-source/",
      "intent_dir": "agent-intent-skills/repo-b/",
      "generator_agent": "claude",
      "reviewer_agent": "kimi"
    }
  ]
}
EOF
  export SOURCES_FILE="${TMPWORK}/sources.json"
}

# ── Default stub implementations ─────────────────────────────────────────────
# Tests override these per-scenario.

# Save the real run_agents before stubbing it — test (7) exercises it directly.
_real_run_agents=$(declare -f run_agents)

fetch_repo()         { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
read_manifest()      { MANIFEST_FILE="/dev/null"; }
validate_contract()  { return 0; }
run_agents()         { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }
write_and_push()     { return 0; }
open_or_update_pr()  { PR_URL="https://github.com/test/pr/1"; }
write_baseline_tag() { :; }

echo ""
echo "process-repos.sh: orchestration logic tests (v2)"
echo "================================================="

# ── (1) trigger=release repo skipped when no FILTER_REPO_ID ──────────────────

make_fixture "release"
export FILTER_REPO_ID=""
export DRY_RUN="false"

FETCH_CALLED=0
fetch_repo() { FETCH_CALLED=1; CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }

_process_repos_main
rc1=$?

if [[ "$rc1" -eq 0 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "trigger=release" \
   && [[ "$FETCH_CALLED" -eq 0 ]]; then
  pass "(1) trigger=release → skipped, fetch not called"
else
  fail "(1) trigger=release → skipped, fetch not called" \
    "exit=${rc1}, FETCH_CALLED=${FETCH_CALLED}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo() { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }

# ── (2) FILTER_REPO_ID overrides trigger — repo is processed ─────────────────

make_fixture "release" "my-repo"
export FILTER_REPO_ID="my-repo"
export DRY_RUN="false"

FETCH_CALLED=0
fetch_repo() { FETCH_CALLED=1; CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }

_process_repos_main
rc2=$?

if [[ "$rc2" -eq 0 ]] \
   && [[ "$FETCH_CALLED" -eq 1 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "no changes"; then
  pass "(2) FILTER_REPO_ID overrides trigger → fetch called, no-changes skip"
else
  fail "(2) FILTER_REPO_ID overrides trigger → fetch called, no-changes skip" \
    "exit=${rc2}, FETCH_CALLED=${FETCH_CALLED}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo() { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }

# ── (3) CHANGED=false → no-changes skip, run_agents not called ───────────────

make_fixture "schedule"
export FILTER_REPO_ID=""
export DRY_RUN="false"

fetch_repo() { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
RUN_AGENTS_CALLED=0
run_agents() { RUN_AGENTS_CALLED=1; OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }

_process_repos_main
rc3=$?

if [[ "$rc3" -eq 0 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "no changes" \
   && [[ "$RUN_AGENTS_CALLED" -eq 0 ]]; then
  pass "(3) CHANGED=false → no-changes skip, run_agents not called"
else
  fail "(3) CHANGED=false → no-changes skip, run_agents not called" \
    "exit=${rc3}, RUN_AGENTS_CALLED=${RUN_AGENTS_CALLED}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo()  { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
run_agents()  { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }

# ── (4) dry_run=true → fetch+agents run, write_and_push not called ───────────

make_fixture "schedule"
export FILTER_REPO_ID=""
export DRY_RUN="true"

fetch_repo()        { CHANGED=true; RESOLVED_REF="v2.0.0"; COMMIT="def456"; }
read_manifest()     { MANIFEST_FILE="/dev/null"; }
validate_contract() { return 0; }
run_agents()        { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }
WRITE_CALLED=0
write_and_push() { WRITE_CALLED=1; return 0; }

_process_repos_main
rc4=$?

if [[ "$rc4" -eq 0 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "dry-run" \
   && [[ "$WRITE_CALLED" -eq 0 ]]; then
  pass "(4) dry_run=true → summary shows dry-run, write_and_push not called"
else
  fail "(4) dry_run=true → summary shows dry-run, write_and_push not called" \
    "exit=${rc4}, WRITE_CALLED=${WRITE_CALLED}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo()        { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
read_manifest()     { MANIFEST_FILE="/dev/null"; }
validate_contract() { return 0; }
run_agents()        { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }
write_and_push()    { return 0; }

# ── (5) REJECT verdict propagates to summary icon ────────────────────────────

make_fixture "schedule"
export FILTER_REPO_ID=""
export DRY_RUN="false"

fetch_repo()        { CHANGED=true; RESOLVED_REF="v2.0.0"; COMMIT="def456"; }
read_manifest()     { MANIFEST_FILE="/dev/null"; }
validate_contract() { return 0; }
run_agents()        { OVERALL_VERDICT="REJECT"; CHANGED_FILES="plugins/test/ref.md"; }
write_and_push()    { return 0; }
open_or_update_pr() { PR_URL="https://github.com/test/pr/42"; }

_process_repos_main
rc5=$?

if [[ "$rc5" -eq 0 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "⚠️" \
   && ! echo "$SUMMARY_ROWS" | grep -qF "✅"; then
  pass "(5) REJECT verdict → summary icon is ⚠️, not ✅"
else
  fail "(5) REJECT verdict → summary icon is ⚠️, not ✅" \
    "exit=${rc5}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# Restore default stubs
fetch_repo()        { CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"; }
read_manifest()     { MANIFEST_FILE="/dev/null"; }
validate_contract() { return 0; }
run_agents()        { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }
write_and_push()    { return 0; }
open_or_update_pr() { PR_URL="https://github.com/test/pr/1"; }

# ── (6) fetch failure → exits 1, failed row + skipped row in summary ─────────

make_fixture_two_repos
export FILTER_REPO_ID=""
export DRY_RUN="false"

fetch_repo() {
  local idx="$1"
  if [[ "$idx" -eq 0 ]]; then
    return 1  # repo-a fails
  else
    CHANGED=false; RESOLVED_REF="v1.0.0"; COMMIT="abc123"  # repo-b: no changes
  fi
}

_process_repos_main 2>/dev/null
rc6=$?

if [[ "$rc6" -eq 1 ]] \
   && echo "$SUMMARY_ROWS" | grep -qF "repo-a" \
   && echo "$SUMMARY_ROWS" | grep -qF "failed" \
   && echo "$SUMMARY_ROWS" | grep -qF "repo-b" \
   && echo "$SUMMARY_ROWS" | grep -qF "no changes"; then
  pass "(6) fetch failure → exits 1, repo-a 'failed' row + repo-b 'skipped' row in summary"
else
  fail "(6) fetch failure → exits 1, repo-a 'failed' row + repo-b 'skipped' row in summary" \
    "exit=${rc6}, SUMMARY_ROWS='${SUMMARY_ROWS}'"
fi

# ── (7) run_agents: one failing entry causes run_agents to return 1 ──────────
#
# Exercises run_agents directly (not via _process_repos_main) with a real
# manifest.json and a stub invoke-agent.sh that fails the generator for
# entry 2, leaving entry 1 to succeed.

# Restore the real run_agents (currently stubbed out by the default stubs above)
eval "$_real_run_agents"

_ra_orig_script_dir="$SCRIPT_DIR"
_ra_work="${TMPWORK}/run-agents"
_ra_checkout="${_ra_work}/checkout"
_ra_staging="${_ra_work}/staging"
_ra_mocks="${_ra_work}/mocks"
_ra_contract="fastedge-plugin-source/"

mkdir -p "${_ra_checkout}/${_ra_contract}" "$_ra_staging" "$_ra_mocks"

cat > "${_ra_checkout}/${_ra_contract}manifest.json" <<'MANIFEST'
{
  "target_mapping": {
    "key-a": {"reference_file": "docs/a.md"},
    "key-b": {"reference_file": "docs/b.md"}
  },
  "sources": {
    "key-a": {"files": ["src/a.rs"]},
    "key-b": {"files": ["src/b.rs"]}
  }
}
MANIFEST

cat > "${_ra_work}/sources.json" <<EOF
{
  "version": "2.0",
  "repos": [
    {
      "id": "test-repo-ra",
      "github_url": "https://github.com/test/test-repo-ra",
      "ref": "latest-release",
      "trigger": "schedule",
      "contract_path": "${_ra_contract}",
      "intent_dir": "agent-intent/",
      "generator_agent": "claude",
      "reviewer_agent": "kimi"
    }
  ]
}
EOF

# Stub: succeed for all entries except the generator call for entry MOCK_INVOKE_AGENT_FAIL_ENTRY
cat > "${_ra_mocks}/invoke-agent.sh" <<'STUB'
#!/usr/bin/env bash
role="" output_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)        role="$2";        shift 2 ;;
    --output-file) output_file="$2"; shift 2 ;;
    *)             shift ;;
  esac
done
if [[ -n "${MOCK_INVOKE_AGENT_FAIL_ENTRY:-}" \
      && "$role" == "generator" \
      && "$output_file" == *"/gen-${MOCK_INVOKE_AGENT_FAIL_ENTRY}.md" ]]; then
  exit 1
fi
[[ "$role" == "generator" ]] && echo "# Generated"  > "$output_file"
[[ "$role" == "reviewer"  ]] && printf 'VERDICT=ACCEPT\n\nLooks good.\n' > "$output_file"
exit 0
STUB
chmod +x "${_ra_mocks}/invoke-agent.sh"

export SOURCES_FILE="${_ra_work}/sources.json"
RESOLVED_REF="v1.0.0"
COMMIT="abc123"
SCRIPT_DIR="$_ra_mocks"
export MOCK_INVOKE_AGENT_FAIL_ENTRY=2

run_agents 0 "$_ra_staging" "$_ra_checkout" 2>/dev/null
rc7=$?

unset MOCK_INVOKE_AGENT_FAIL_ENTRY
SCRIPT_DIR="$_ra_orig_script_dir"
export SOURCES_FILE="${TMPWORK}/sources.json"

if [[ "$rc7" -eq 1 ]]; then
  pass "(7) run_agents: one failing entry → returns 1"
else
  fail "(7) run_agents: one failing entry → returns 1" "exit=${rc7}"
fi

# Restore stub so any future tests added below see the expected default
run_agents() { OVERALL_VERDICT="ACCEPT"; CHANGED_FILES="plugins/test/ref.md"; }

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
