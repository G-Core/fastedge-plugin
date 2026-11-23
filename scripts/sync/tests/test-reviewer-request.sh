#!/usr/bin/env bash
# test-reviewer-request.sh — the reviewer's OpenAI request and error handling
#
# Coverage (curl is mocked; no network):
#   (1) default request: model gpt-5.6-sol, reasoning_effort high, no temperature
#   (2) REVIEWER_MODEL / REVIEWER_REASONING_EFFORT=none → that model, no reasoning_effort
#   (3) API error body → exit 1 with the API message, no output file
#   (4) successful reply → VERDICT written to the output file
#   (5) a prompt over 128 KiB (one argument's limit) reaches the request whole
#
# Usage: bash scripts/sync/tests/test-reviewer-request.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVOKE="$SCRIPT_DIR/../invoke-agent.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

TMPWORK="$(mktemp -d)"
trap 'rm -rf "$TMPWORK"' EXIT

mkdir -p "$TMPWORK/src/docs" "$TMPWORK/bin"
echo "# Source" > "$TMPWORK/src/docs/SOURCE.md"
echo "# Generated" > "$TMPWORK/gen.md"

# curl mock: records the request body (read from stdin), replies with $MOCK_REPLY
cat > "$TMPWORK/bin/curl" <<'MOCK'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--data-binary" && "$2" == "@-" ]] && cat > "$MOCK_BODY_FILE"
  shift
done
printf '%s' "$MOCK_REPLY"
MOCK
chmod +x "$TMPWORK/bin/curl"

OK_REPLY='{"choices":[{"message":{"content":"VERDICT: ACCEPT\nFINDINGS: None."}}]}'

run_reviewer() {
  PATH="$TMPWORK/bin:$PATH" OPENAI_API_KEY=test MOCK_BODY_FILE="$TMPWORK/body.json" \
    bash "$INVOKE" --role reviewer \
      --input-file "$TMPWORK/gen.md" \
      --source-dir "$TMPWORK/src" \
      --source-files "docs/SOURCE.md" \
      --output-file "$TMPWORK/out.txt"
}

echo "invoke-agent.sh — reviewer request"
echo "=================================="

# (1)
rm -f "$TMPWORK/body.json" "$TMPWORK/out.txt"
MOCK_REPLY="$OK_REPLY" run_reviewer 2>/dev/null
body=$(cat "$TMPWORK/body.json" 2>/dev/null || echo "{}")
if [[ "$(jq -r .model <<<"$body")" == "gpt-5.6-sol" && "$(jq -r .reasoning_effort <<<"$body")" == "high" \
      && "$(jq -r 'has("temperature")' <<<"$body")" == "false" ]]; then
  pass "(1) default: gpt-5.6-sol, reasoning_effort high, no temperature"
else
  fail "(1) default: gpt-5.6-sol, reasoning_effort high, no temperature" "body=$body"
fi

# (2)
rm -f "$TMPWORK/body.json"
MOCK_REPLY="$OK_REPLY" REVIEWER_MODEL=gpt-4o REVIEWER_REASONING_EFFORT=none run_reviewer 2>/dev/null
body=$(cat "$TMPWORK/body.json" 2>/dev/null || echo "{}")
if [[ "$(jq -r .model <<<"$body")" == "gpt-4o" && "$(jq -r 'has("reasoning_effort")' <<<"$body")" == "false" ]]; then
  pass "(2) REVIEWER_MODEL and REVIEWER_REASONING_EFFORT=none respected"
else
  fail "(2) REVIEWER_MODEL and REVIEWER_REASONING_EFFORT=none respected" "body=$body"
fi

# (3)
rm -f "$TMPWORK/out.txt"
err=$(MOCK_REPLY='{"error":{"message":"The model `gpt-5.6-sol` does not exist or you do not have access to it."}}' \
  run_reviewer 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 && "$err" == *"OpenAI API error (model gpt-5.6-sol): The model"* && ! -f "$TMPWORK/out.txt" ]]; then
  pass "(3) API error surfaced, exit 1, no output file"
else
  fail "(3) API error surfaced, exit 1, no output file" "rc=$rc err=$err"
fi

# (4)
rm -f "$TMPWORK/out.txt"
MOCK_REPLY="$OK_REPLY" run_reviewer 2>/dev/null
if [[ "$(head -1 "$TMPWORK/out.txt" 2>/dev/null)" == "VERDICT=ACCEPT" ]]; then
  pass "(4) successful reply: VERDICT written"
else
  fail "(4) successful reply: VERDICT written" "out=$(cat "$TMPWORK/out.txt" 2>/dev/null)"
fi

# (5)
rm -f "$TMPWORK/body.json" "$TMPWORK/out.txt"
{ echo "# Source"; head -c 200000 /dev/zero | tr '\0' 'x'; echo; echo "END-OF-BIG-SOURCE"; } > "$TMPWORK/src/docs/SOURCE.md"
MOCK_REPLY="$OK_REPLY" run_reviewer 2>/dev/null
if jq -e '.messages[0].content | contains("END-OF-BIG-SOURCE")' "$TMPWORK/body.json" >/dev/null 2>&1 \
    && [[ "$(head -1 "$TMPWORK/out.txt" 2>/dev/null)" == "VERDICT=ACCEPT" ]]; then
  pass "(5) a prompt over 128 KiB reaches the request whole"
else
  fail "(5) a prompt over 128 KiB reaches the request whole"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
