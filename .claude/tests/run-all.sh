#!/bin/bash
# run-all.sh — Execute all test-*.sh scripts and report grand totals
# Exit 0 = all pass, exit 1 = any fail

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-/workspaces}"

GRAND_PASS=0
GRAND_FAIL=0
GRAND_SKIP=0
GRAND_TOTAL=0
ANY_FAIL=0

echo "=========================================="
echo "  Executable Standards Test Suite"
echo "=========================================="
echo ""

# Include hooks/test-hooks.sh (functional integration tests) if present
HOOKS_FUNC_TEST="$ROOT/.claude/hooks/test-hooks.sh"
ALL_TESTS=("$TESTS_DIR"/test-*.sh)
if [ -f "$HOOKS_FUNC_TEST" ]; then
  ALL_TESTS+=("$HOOKS_FUNC_TEST")
fi

for test_script in "${ALL_TESTS[@]}"; do
  [ -f "$test_script" ] || continue
  test_name=$(basename "$test_script" .sh)

  echo "--- $test_name ---"

  # Run test, capture output (allow non-zero exit)
  output=$(bash "$test_script" "$ROOT" 2>&1) || true
  echo "$output"

  # Parse TOTAL line
  total_line=$(echo "$output" | grep -E '^TOTAL:' | tail -1)
  if [ -n "$total_line" ]; then
    t=$(echo "$total_line" | sed -n 's/.*TOTAL:[[:space:]]*\([0-9]*\).*/\1/p')
    p=$(echo "$total_line" | sed -n 's/.*PASS:[[:space:]]*\([0-9]*\).*/\1/p')
    f=$(echo "$total_line" | sed -n 's/.*FAIL:[[:space:]]*\([0-9]*\).*/\1/p')
    s=$(echo "$total_line" | sed -n 's/.*SKIP:[[:space:]]*\([0-9]*\).*/\1/p')
    GRAND_TOTAL=$((GRAND_TOTAL + ${t:-0}))
    GRAND_PASS=$((GRAND_PASS + ${p:-0}))
    GRAND_FAIL=$((GRAND_FAIL + ${f:-0}))
    GRAND_SKIP=$((GRAND_SKIP + ${s:-0}))
    if [ "${f:-0}" -gt 0 ]; then
      ANY_FAIL=1
    fi
  fi
  echo ""
done

echo "=========================================="
echo "  GRAND TOTAL"
echo "=========================================="
echo "TOTAL: $GRAND_TOTAL  PASS: $GRAND_PASS  FAIL: $GRAND_FAIL  SKIP: $GRAND_SKIP"
echo ""

if [ "$ANY_FAIL" -eq 0 ]; then
  echo "Result: ALL PASS"
  exit 0
else
  echo "Result: FAILURES DETECTED"
  exit 1
fi
