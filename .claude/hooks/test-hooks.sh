#!/bin/bash
# Test all hooks without triggering PreToolUse interception
# Run: bash .claude/hooks/test-hooks.sh

set -e
PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
export CLAUDE_PROJECT_DIR="$PROJECT_DIR"

echo "=== Hook Test Suite ==="
echo ""

# --- Test 1: Pre-commit gate (no marker) ---
echo -n "1. Pre-commit gate (no marker): "
rm -f "$PROJECT_DIR/.claude/.last-verification"
RESULT=$(echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" 2>&1)
if echo "$RESULT" | grep -q "permissionDecision.*deny"; then
  echo "PASS (denied)"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected deny, got: $RESULT)"
  FAIL=$((FAIL + 1))
fi

# --- Test 2: Pre-commit gate (with fresh marker) ---
echo -n "2. Pre-commit gate (fresh marker): "
touch "$PROJECT_DIR/.claude/.last-verification"
RESULT=$(echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && [ -z "$RESULT" ]; then
  echo "PASS (allowed)"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow, got exit=$EXIT_CODE, output=$RESULT)"
  FAIL=$((FAIL + 1))
fi

# --- Test 3: Pre-commit gate (non-commit command) ---
echo -n "3. Pre-commit gate (npm install): "
RESULT=$(echo '{"tool_input":{"command":"npm install"}}' | bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && [ -z "$RESULT" ]; then
  echo "PASS (ignored)"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected ignore)"
  FAIL=$((FAIL + 1))
fi

# --- Test 4: Code review reminder (products/ file) ---
echo -n "4. Code review reminder (products/ file): "
rm -f "$PROJECT_DIR/.claude/.pending-review"
RESULT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT_DIR"'/products/example/src/main.py"},"tool_response":{"success":true}}' | bash "$PROJECT_DIR/.claude/hooks/code-review-reminder.sh" 2>&1)
if echo "$RESULT" | grep -q "additionalContext" && [ -f "$PROJECT_DIR/.claude/.pending-review" ]; then
  echo "PASS (marker created + context injected)"
  PASS=$((PASS + 1))
else
  echo "FAIL (result=$RESULT, marker exists=$([ -f $PROJECT_DIR/.claude/.pending-review ] && echo yes || echo no))"
  FAIL=$((FAIL + 1))
fi

# --- Test 5: Code review reminder (non-products file) ---
echo -n "5. Code review reminder (non-products file): "
rm -f "$PROJECT_DIR/.claude/.pending-review"
RESULT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT_DIR"'/scripts/test.sh"},"tool_response":{"success":true}}' | bash "$PROJECT_DIR/.claude/hooks/code-review-reminder.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && [ ! -f "$PROJECT_DIR/.claude/.pending-review" ]; then
  echo "PASS (ignored)"
  PASS=$((PASS + 1))
else
  echo "FAIL"
  FAIL=$((FAIL + 1))
fi

# --- Test 6: Stop gate (pending review exists) ---
echo -n "6. Stop gate (pending review): "
echo "products/example/src/main.py" > "$PROJECT_DIR/.claude/.pending-review"
RESULT=$(echo '{"stop_hook_active":false}' | bash "$PROJECT_DIR/.claude/hooks/stop-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && echo "$RESULT" | grep -q '"decision".*"block"'; then
  echo "PASS (blocked, exit=$EXIT_CODE)"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected block with exit 0, got exit=$EXIT_CODE, output: $RESULT)"
  FAIL=$((FAIL + 1))
fi

# --- Test 6b: Stop gate release path (review-complete.sh clears block) ---
echo -n "6b. Stop gate release path: "
echo "products/example/src/main.py" > "$PROJECT_DIR/.claude/.pending-review"
bash "$PROJECT_DIR/.claude/hooks/review-complete.sh" > /dev/null 2>&1
RESULT=$(echo '{"stop_hook_active":false}' | bash "$PROJECT_DIR/.claude/hooks/stop-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && [ -z "$RESULT" ]; then
  echo "PASS (unblocked after review-complete.sh)"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow after review-complete.sh, got exit=$EXIT_CODE, output: $RESULT)"
  FAIL=$((FAIL + 1))
fi

# --- Test 7: Stop gate (no pending review) ---
echo -n "7. Stop gate (no pending review): "
rm -f "$PROJECT_DIR/.claude/.pending-review"
RESULT=$(echo '{"stop_hook_active":false}' | bash "$PROJECT_DIR/.claude/hooks/stop-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && [ -z "$RESULT" ]; then
  echo "PASS (allowed)"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow)"
  FAIL=$((FAIL + 1))
fi

# --- Test 8: Stop gate (stop_hook_active = true, infinite loop prevention) ---
echo -n "8. Stop gate (loop prevention): "
echo "products/example/test.py" > "$PROJECT_DIR/.claude/.pending-review"
RESULT=$(echo '{"stop_hook_active":true}' | bash "$PROJECT_DIR/.claude/hooks/stop-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && [ -z "$RESULT" ]; then
  echo "PASS (allowed despite pending - loop prevention)"
  PASS=$((PASS + 1))
else
  echo "FAIL (should allow to prevent loop)"
  FAIL=$((FAIL + 1))
fi

# --- Test 9: Block destructive (rm -rf) ---
echo -n "9. Block destructive (rm -rf /): "
RESULT=$(echo '{"tool_input":{"command":"rm -rf /"}}' | bash "$PROJECT_DIR/.claude/hooks/block-destructive.sh" 2>&1)
if echo "$RESULT" | grep -q "permissionDecision.*deny"; then
  echo "PASS (denied)"
  PASS=$((PASS + 1))
else
  echo "FAIL"
  FAIL=$((FAIL + 1))
fi

# --- Test 10: SessionStart Known Issues parsing ---
echo -n "10. SessionStart Known Issues: "
RESULT=$(echo '{"source":"startup"}' | bash "$PROJECT_DIR/.claude/hooks/session-start.sh" 2>&1)
# session-start.sh reads from Claude auto-memory (same path used by session-start.sh)
PROJECT_KEY=$(echo "$PROJECT_DIR" | tr "/" "-" | sed "s/^-//")
AUTO_MEMORY_FILE="${HOME}/.claude/projects/${PROJECT_KEY}/memory/MEMORY.md"
HAS_ISSUES=$(grep -l "ISSUE-" "$AUTO_MEMORY_FILE" 2>/dev/null | head -1)
if [ -n "$HAS_ISSUES" ]; then
  # MEMORY.md has Known Issues — session-start should report them
  if echo "$RESULT" | grep -q "ISSUE-"; then
    echo "PASS (Known Issues found in output)"
    PASS=$((PASS + 1))
  else
    echo "FAIL (MEMORY.md has ISSUE- but session-start didn't report)"
    FAIL=$((FAIL + 1))
  fi
else
  # No Known Issues in MEMORY.md — expected for fresh template
  echo "PASS (no Known Issues — expected for base template)"
  PASS=$((PASS + 1))
fi

# --- Test 11: Utility scripts ---
echo -n "11. mark-verified.sh: "
rm -f "$PROJECT_DIR/.claude/.last-verification"
export CLAUDE_PROJECT_DIR="$PROJECT_DIR"
bash "$PROJECT_DIR/.claude/hooks/mark-verified.sh" > /dev/null
if [ -f "$PROJECT_DIR/.claude/.last-verification" ]; then
  echo "PASS (marker created)"
  PASS=$((PASS + 1))
else
  echo "FAIL"
  FAIL=$((FAIL + 1))
fi

echo -n "12. review-complete.sh: "
echo "test.py" > "$PROJECT_DIR/.claude/.pending-review"
bash "$PROJECT_DIR/.claude/hooks/review-complete.sh" > /dev/null
if [ ! -f "$PROJECT_DIR/.claude/.pending-review" ]; then
  echo "PASS (marker cleared)"
  PASS=$((PASS + 1))
else
  echo "FAIL"
  FAIL=$((FAIL + 1))
fi

# --- Test 13: Error tracker (tool failure) ---
echo -n "13. Error tracker (tool failure): "
rm -f "$PROJECT_DIR/.claude/.error-log"
RESULT=$(echo '{"tool_name":"Bash","tool_input":{"command":"failing-cmd"},"error":"Command not found"}' | bash "$PROJECT_DIR/.claude/hooks/error-tracker.sh" 2>&1)
if echo "$RESULT" | grep -q "additionalContext" && [ -f "$PROJECT_DIR/.claude/.error-log" ]; then
  echo "PASS (error logged + context injected)"
  PASS=$((PASS + 1))
else
  echo "FAIL (result=$RESULT, log exists=$([ -f $PROJECT_DIR/.claude/.error-log ] && echo yes || echo no))"
  FAIL=$((FAIL + 1))
fi

# --- Test 14: Error tracker (empty error) ---
echo -n "14. Error tracker (empty error): "
rm -f "$PROJECT_DIR/.claude/.error-log"
RESULT=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/nonexistent"}}' | bash "$PROJECT_DIR/.claude/hooks/error-tracker.sh" 2>&1)
if echo "$RESULT" | grep -q "additionalContext" && [ -f "$PROJECT_DIR/.claude/.error-log" ]; then
  echo "PASS (handles missing error field)"
  PASS=$((PASS + 1))
else
  echo "FAIL"
  FAIL=$((FAIL + 1))
fi

# --- Test 15: Standards reminder (.claude/ file) ---
echo -n "15. Standards reminder (.claude/ file): "
RESULT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT_DIR"'/.claude/hooks/example.sh"},"tool_response":{"success":true}}' | bash "$PROJECT_DIR/.claude/hooks/standards-reminder.sh" 2>&1)
if echo "$RESULT" | grep -q "hooks-and-lifecycle"; then
  echo "PASS (standard mapped: hooks-and-lifecycle)"
  PASS=$((PASS + 1))
else
  echo "FAIL (result=$RESULT)"
  FAIL=$((FAIL + 1))
fi

# --- Test 16: Standards reminder (non-.claude file) ---
echo -n "16. Standards reminder (non-.claude file): "
RESULT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT_DIR"'/src/main.py"},"tool_response":{"success":true}}' | bash "$PROJECT_DIR/.claude/hooks/standards-reminder.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && [ -z "$RESULT" ]; then
  echo "PASS (ignored)"
  PASS=$((PASS + 1))
else
  echo "FAIL"
  FAIL=$((FAIL + 1))
fi

# --- Cleanup ---
rm -f "$PROJECT_DIR/.claude/.pending-review"
rm -f "$PROJECT_DIR/.claude/.error-log"
touch "$PROJECT_DIR/.claude/.last-verification"

echo ""
echo "=== Results: $PASS PASS / $FAIL FAIL (total $((PASS + FAIL))) ==="
[ $FAIL -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
