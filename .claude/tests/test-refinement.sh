#!/bin/bash
# test-refinement.sh — Refinement loop infrastructure tests (RF-1..RF-17)
# v3: autoresearch pattern — memory-ops, trajectory, gate, rubric

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
SCRIPTS="$ROOT/.claude/skills/refine"
PASS=0; FAIL=0; SKIP=0

result() {
  local status="$1" id="$2" desc="$3" detail="${4:-}"
  case "$status" in PASS) PASS=$((PASS+1));; FAIL) FAIL=$((FAIL+1));; SKIP) SKIP=$((SKIP+1));; esac
  echo "$status: $id $desc${detail:+ ($detail)}"
}

# --- Temp directory for test isolation ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
export CLAUDE_AGENT_MEMORY="$TMPDIR/agent-memory"

# =============================================================================
# RF-1: memory-ops.sh exists + bash -n
# =============================================================================
if [ -f "$SCRIPTS/memory-ops.sh" ]; then
  if bash -n "$SCRIPTS/memory-ops.sh" 2>/dev/null; then
    result PASS RF-1 "memory-ops.sh exists + syntax OK"
  else
    result FAIL RF-1 "memory-ops.sh syntax error"
  fi
else
  result FAIL RF-1 "memory-ops.sh not found"
fi

# =============================================================================
# RF-2: memory-ops.sh CRUD cycle (add->list->best->count->clear)
# =============================================================================
TASK_TEST="test-crud-$$"

# add two entries
ADD1=$(bash "$SCRIPTS/memory-ops.sh" add --task "$TASK_TEST" --agent "tdd-guide" --score 0.3 --result "3 errors" --feedback "lint fail")
ADD2=$(bash "$SCRIPTS/memory-ops.sh" add --task "$TASK_TEST" --agent "tdd-guide" --score 0.7 --result "1 error" --feedback "partial")

# list
LIST=$(bash "$SCRIPTS/memory-ops.sh" list --task "$TASK_TEST")
LIST_COUNT=$(echo "$LIST" | jq 'length')

# best
BEST=$(bash "$SCRIPTS/memory-ops.sh" best --task "$TASK_TEST")
BEST_SCORE=$(echo "$BEST" | jq '.score')

# count
COUNT=$(bash "$SCRIPTS/memory-ops.sh" count --task "$TASK_TEST")

# clear
CLEAR=$(bash "$SCRIPTS/memory-ops.sh" clear --task "$TASK_TEST")
COUNT_AFTER=$(bash "$SCRIPTS/memory-ops.sh" count --task "$TASK_TEST")

if [ "$LIST_COUNT" = "2" ] && [ "$BEST_SCORE" = "0.7" ] && [ "$COUNT" = "2" ] && [ "$COUNT_AFTER" = "0" ]; then
  result PASS RF-2 "CRUD cycle (add x2->list=2->best=0.7->count=2->clear->count=0)"
else
  result FAIL RF-2 "CRUD cycle" "list=$LIST_COUNT best=$BEST_SCORE count=$COUNT after=$COUNT_AFTER"
fi

# =============================================================================
# RF-3: memory-ops.sh task_id injection rejection
# =============================================================================
REJECT_OK=true

# Path traversal
if bash "$SCRIPTS/memory-ops.sh" add --task "../inject" --agent "x" --score 0.5 --result "x" --feedback "x" 2>/dev/null; then
  REJECT_OK=false
fi

# Empty string
if bash "$SCRIPTS/memory-ops.sh" add --task "" --agent "x" --score 0.5 --result "x" --feedback "x" 2>/dev/null; then
  REJECT_OK=false
fi

# Spaces
if bash "$SCRIPTS/memory-ops.sh" add --task "bad id" --agent "x" --score 0.5 --result "x" --feedback "x" 2>/dev/null; then
  REJECT_OK=false
fi

if $REJECT_OK; then
  result PASS RF-3 "task_id injection rejected (../inject, empty, spaces)"
else
  result FAIL RF-3 "task_id injection not rejected"
fi

# =============================================================================
# RF-4: trajectory.sh worst-first sort
# =============================================================================
TASK_TRAJ="test-traj-$$"

bash "$SCRIPTS/memory-ops.sh" add --task "$TASK_TRAJ" --agent "ber" --score 0.8 --result "good" --feedback "almost" >/dev/null
bash "$SCRIPTS/memory-ops.sh" add --task "$TASK_TRAJ" --agent "ber" --score 0.2 --result "bad" --feedback "many errors" >/dev/null
bash "$SCRIPTS/memory-ops.sh" add --task "$TASK_TRAJ" --agent "ber" --score 0.5 --result "ok" --feedback "some errors" >/dev/null

TRAJ_XML=$(bash "$SCRIPTS/trajectory.sh" --task "$TASK_TRAJ")

# Extract scores in order from <attempt> tags — should be 0.2, 0.5, 0.8 (worst first)
TRAJ_SCORES=$(echo "$TRAJ_XML" | grep '<attempt ' | grep -oP 'score="\K[0-9.]+' | tr '\n' ',')

if [ "$TRAJ_SCORES" = "0.2,0.5,0.8," ]; then
  result PASS RF-4 "trajectory worst->best sort (0.2->0.5->0.8)"
else
  result FAIL RF-4 "trajectory sort" "got: $TRAJ_SCORES"
fi

# =============================================================================
# RF-5: trajectory.sh --max limit
# =============================================================================
TRAJ_MAX=$(bash "$SCRIPTS/trajectory.sh" --task "$TASK_TRAJ" --max 2)
TRAJ_MAX_COUNT=$(echo "$TRAJ_MAX" | grep '<previous_attempts' | grep -oP 'count="\K[0-9]+')
TRAJ_MAX_SCORES=$(echo "$TRAJ_MAX" | grep '<attempt ' | grep -oP 'score="\K[0-9.]+' | tr '\n' ',')

if [ "$TRAJ_MAX_COUNT" = "2" ] && [ "$TRAJ_MAX_SCORES" = "0.5,0.8," ]; then
  result PASS RF-5 "trajectory --max 2 (top-2 by score: 0.5->0.8)"
else
  result FAIL RF-5 "trajectory --max" "count=$TRAJ_MAX_COUNT scores=$TRAJ_MAX_SCORES"
fi

# =============================================================================
# RF-6: trajectory.sh CDATA format
# =============================================================================
if echo "$TRAJ_XML" | grep -q '<!\[CDATA\['; then
  if echo "$TRAJ_XML" | grep -q '</previous_attempts>'; then
    result PASS RF-6 "trajectory CDATA + XML structure"
  else
    result FAIL RF-6 "trajectory missing closing tag"
  fi
else
  result FAIL RF-6 "trajectory CDATA not found"
fi

# =============================================================================
# RF-7: refinement-gate.sh exists + bash -n
# =============================================================================
GATE="$ROOT/.claude/hooks/refinement-gate.sh"
if [ -f "$GATE" ]; then
  if bash -n "$GATE" 2>/dev/null; then
    result PASS RF-7 "refinement-gate.sh exists + syntax OK"
  else
    result FAIL RF-7 "refinement-gate.sh syntax error"
  fi
else
  result FAIL RF-7 "refinement-gate.sh not found"
fi

# =============================================================================
# RF-8: refinement-gate.sh — no marker -> exit 0
# =============================================================================
GATE_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$GATE_TMPDIR"' EXIT
GATE_OUT=$(echo '{}' | CLAUDE_PROJECT_DIR="$GATE_TMPDIR" bash "$GATE" 2>/dev/null)
GATE_EXIT=$?
if [ "$GATE_EXIT" -eq 0 ] && [ -z "$GATE_OUT" ]; then
  result PASS RF-8 "gate: no marker -> exit 0 (silent pass)"
else
  result FAIL RF-8 "gate: no marker" "exit=$GATE_EXIT out=$GATE_OUT"
fi

# =============================================================================
# RF-9: refinement-gate.sh — marker + score below threshold -> block
# =============================================================================
GATE_DIR_9=$(mktemp -d)
mkdir -p "$GATE_DIR_9/.claude"
mkdir -p "$GATE_DIR_9/.claude/skills/refine"
echo '{"task_id":"test-rf9","threshold":0.9,"max_iterations":5}' > "$GATE_DIR_9/.claude/.refinement-active"
cat > "$GATE_DIR_9/.claude/skills/refine/memory-ops.sh" <<'STUB'
#!/bin/bash
case "$1" in
  best)  echo '{"score":0.3}' ;;
  count) echo "1" ;;
esac
STUB
chmod +x "$GATE_DIR_9/.claude/skills/refine/memory-ops.sh"

GATE_OUT_9=$(echo '{}' | CLAUDE_PROJECT_DIR="$GATE_DIR_9" bash "$GATE" 2>/dev/null)
if echo "$GATE_OUT_9" | jq -e '.decision == "block"' >/dev/null 2>&1; then
  result PASS RF-9 "gate: below threshold -> block"
else
  result FAIL RF-9 "gate: expected block" "out=$GATE_OUT_9"
fi
rm -rf "$GATE_DIR_9"

# =============================================================================
# RF-10: refinement-gate.sh — score meets threshold -> exit 0
# =============================================================================
GATE_DIR_10=$(mktemp -d)
mkdir -p "$GATE_DIR_10/.claude"
mkdir -p "$GATE_DIR_10/.claude/skills/refine"
echo '{"task_id":"test-rf10","threshold":0.8,"max_iterations":5}' > "$GATE_DIR_10/.claude/.refinement-active"
cat > "$GATE_DIR_10/.claude/skills/refine/memory-ops.sh" <<'STUB'
#!/bin/bash
case "$1" in
  best)  echo '{"score":0.85}' ;;
  count) echo "2" ;;
esac
STUB
chmod +x "$GATE_DIR_10/.claude/skills/refine/memory-ops.sh"

GATE_OUT_10=$(echo '{}' | CLAUDE_PROJECT_DIR="$GATE_DIR_10" bash "$GATE" 2>/dev/null)
GATE_EXIT_10=$?
if [ "$GATE_EXIT_10" -eq 0 ] && ! echo "$GATE_OUT_10" | grep -q '"decision".*"block"'; then
  result PASS RF-10 "gate: score >= threshold -> exit 0"
else
  result FAIL RF-10 "gate: expected pass" "exit=$GATE_EXIT_10 out=$GATE_OUT_10"
fi
rm -rf "$GATE_DIR_10"

# =============================================================================
# RF-11: refinement-gate.sh — symlink marker rejected
# =============================================================================
GATE_DIR_11=$(mktemp -d)
mkdir -p "$GATE_DIR_11/.claude"
ln -sf /etc/passwd "$GATE_DIR_11/.claude/.refinement-active"

GATE_OUT_11=$(echo '{}' | CLAUDE_PROJECT_DIR="$GATE_DIR_11" bash "$GATE" 2>/dev/null)
GATE_EXIT_11=$?
if [ "$GATE_EXIT_11" -eq 0 ] && [ ! -L "$GATE_DIR_11/.claude/.refinement-active" ]; then
  result PASS RF-11 "gate: symlink marker rejected + removed"
else
  result FAIL RF-11 "gate: symlink" "exit=$GATE_EXIT_11"
fi
rm -rf "$GATE_DIR_11"

# =============================================================================
# RF-12: task-quality-gate.sh — no marker -> existing behavior
# =============================================================================
TQG="$ROOT/.claude/hooks/task-quality-gate.sh"
if [ -f "$TQG" ]; then
  TQG_DIR_12=$(mktemp -d)
  mkdir -p "$TQG_DIR_12/.claude"
  TQG_OUT=$(echo '{"tool_input":"{}"}' | CLAUDE_PROJECT_DIR="$TQG_DIR_12" bash "$TQG" 2>/dev/null)
  if echo "$TQG_OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    if echo "$TQG_OUT" | grep -q 'Refinement active'; then
      result FAIL RF-12 "task-quality-gate shows refinement without marker"
    else
      result PASS RF-12 "task-quality-gate: no marker -> existing behavior"
    fi
  else
    result FAIL RF-12 "task-quality-gate: no hookSpecificOutput"
  fi
  rm -rf "$TQG_DIR_12"
else
  result SKIP RF-12 "task-quality-gate.sh not found"
fi

# =============================================================================
# RF-13: settings.json has refinement-gate registered
# =============================================================================
SETTINGS="$ROOT/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  if jq -r '.hooks.Stop[0].hooks[].command' "$SETTINGS" 2>/dev/null | grep -q 'refinement-gate'; then
    result PASS RF-13 "settings.json: refinement-gate in Stop hooks"
  else
    result FAIL RF-13 "settings.json: refinement-gate not found in Stop hooks"
  fi
else
  result FAIL RF-13 "settings.json not found"
fi

# =============================================================================
# RF-14: SKILL.md contains autoresearch evaluation protocol
# =============================================================================
SKILL="$ROOT/.claude/skills/refine/SKILL.md"
if [ -f "$SKILL" ]; then
  HAS_RUBRIC=$(grep -c 'immutable rubric\|Evaluation Protocol\|rubrics/default.yml' "$SKILL" || true)
  HAS_BINARY=$(grep -c 'KEEP\|DISCARD' "$SKILL" || true)
  if [ "$HAS_RUBRIC" -ge 2 ] && [ "$HAS_BINARY" -ge 2 ]; then
    result PASS RF-14 "SKILL.md: autoresearch pattern (rubric=$HAS_RUBRIC, binary=$HAS_BINARY)"
  else
    result FAIL RF-14 "SKILL.md: autoresearch markers" "rubric=$HAS_RUBRIC binary=$HAS_BINARY"
  fi
else
  result FAIL RF-14 "SKILL.md not found"
fi

# =============================================================================
# RF-15: SKILL.md does NOT reference deleted scripts
# =============================================================================
if [ -f "$SKILL" ]; then
  DELETED_REFS=$(grep -c 'verify-score\.sh\|score\.sh\|feedback-builder\.sh' "$SKILL" || true)
  if [ "$DELETED_REFS" -eq 0 ]; then
    result PASS RF-15 "SKILL.md: no references to deleted scripts"
  else
    result FAIL RF-15 "SKILL.md: still references deleted scripts" "count=$DELETED_REFS"
  fi
else
  result FAIL RF-15 "SKILL.md not found"
fi

# =============================================================================
# RF-16: rubric file exists with required dimensions
# =============================================================================
RUBRIC="$ROOT/.claude/skills/refine/rubrics/default.yml"
if [ -f "$RUBRIC" ]; then
  HAS_DIMS=true
  for DIM in correctness improvement completeness consistency; do
    if ! grep -q "^    $DIM:" "$RUBRIC"; then
      HAS_DIMS=false
      break
    fi
  done
  HAS_ANCHORS=$(grep -c '"0\.\(0\|25\|5\|75\|0\)"' "$RUBRIC" || true)
  if $HAS_DIMS && [ "$HAS_ANCHORS" -ge 16 ]; then
    result PASS RF-16 "rubric: 4 dimensions + anchors present (anchors=$HAS_ANCHORS)"
  else
    result FAIL RF-16 "rubric structure" "dims=$HAS_DIMS anchors=$HAS_ANCHORS"
  fi
else
  result FAIL RF-16 "rubric not found"
fi

# =============================================================================
# RF-17: file inventory — only 4 files remain (v3 minimal)
# =============================================================================
EXPECTED_FILES="SKILL.md memory-ops.sh trajectory.sh rubrics/default.yml"
ACTUAL_COUNT=0
MISSING=""
for F in $EXPECTED_FILES; do
  if [ -f "$SCRIPTS/$F" ]; then
    ACTUAL_COUNT=$((ACTUAL_COUNT + 1))
  else
    MISSING="$MISSING $F"
  fi
done

# Check no deleted scripts remain
GHOST=""
for G in verify-score.sh score.sh feedback-builder.sh; do
  if [ -f "$SCRIPTS/$G" ]; then
    GHOST="$GHOST $G"
  fi
done

if [ "$ACTUAL_COUNT" -eq 4 ] && [ -z "$GHOST" ]; then
  result PASS RF-17 "file inventory: 4 expected files, 0 ghost files"
else
  result FAIL RF-17 "file inventory" "found=$ACTUAL_COUNT missing=$MISSING ghost=$GHOST"
fi

# =============================================================================
# Summary
# =============================================================================
TOTAL=$((PASS + FAIL + SKIP))
echo "---"
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
