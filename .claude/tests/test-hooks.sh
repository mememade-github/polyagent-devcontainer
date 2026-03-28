#!/bin/bash
# test-hooks.sh — Hooks and Lifecycle Standard compliance checks (HK-1..HK-18)
# Validates all .claude/hooks/*.sh against hooks-and-lifecycle + explicit-failure standards.

set -euo pipefail

ROOT="${1:-/workspaces}"
HOOKS_DIR="$ROOT/.claude/hooks"
SETTINGS="$ROOT/.claude/settings.json"
ACTUAL_ROOT="$ROOT"
PASS=0; FAIL=0; SKIP=0

result() {
  local status="$1" id="$2" desc="$3" detail="${4:-}"
  if [ "$status" = "PASS" ]; then PASS=$((PASS + 1)); fi
  if [ "$status" = "FAIL" ]; then FAIL=$((FAIL + 1)); fi
  if [ "$status" = "SKIP" ]; then SKIP=$((SKIP + 1)); fi
  echo "$status: $id $desc ($detail)"
}

# --- HK-1: all .sh have #!/bin/bash ---
hk1_fails=""
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  first=$(head -1 "$f")
  if [ "$first" != "#!/bin/bash" ]; then
    hk1_fails+=" $(basename "$f")"
  fi
done
if [ -z "$hk1_fails" ]; then
  result "PASS" "HK-1" "all hooks have #!/bin/bash shebang" "all hooks"
else
  result "FAIL" "HK-1" "all hooks have #!/bin/bash shebang" "missing:${hk1_fails}"
fi

# --- HK-2: all pass bash -n ---
hk2_fails=""
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  if ! bash -n "$f" 2>/dev/null; then
    hk2_fails+=" $(basename "$f")"
  fi
done
if [ -z "$hk2_fails" ]; then
  result "PASS" "HK-2" "all hooks pass bash -n syntax check" "all hooks"
else
  result "FAIL" "HK-2" "all hooks pass bash -n syntax check" "failed:${hk2_fails}"
fi

# --- HK-3: bash prefix in settings.json commands referencing .sh files ---
hk3_fails=""
hk3_cmds=$(python3 -c "
import json, sys
with open('$SETTINGS') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
for event, entries in hooks.items():
    for entry in entries:
        for hook in entry.get('hooks', []):
            cmd = hook.get('command', '')
            if '.sh' in cmd:
                print(cmd)
" 2>/dev/null || true)

while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  if ! echo "$cmd" | grep -q '^bash '; then
    hk3_fails+=" $(echo "$cmd" | head -c 60)"
  fi
done <<< "$hk3_cmds"
if [ -z "$hk3_fails" ]; then
  result "PASS" "HK-3" "bash prefix on all .sh commands in settings.json" "all commands"
else
  result "FAIL" "HK-3" "bash prefix on all .sh commands in settings.json" "missing:${hk3_fails}"
fi

# --- HK-4: all registered hook paths exist (resolve $CLAUDE_PROJECT_DIR) ---
hk4_fails=""
hk4_paths=$(python3 -c "
import json, re
with open('$SETTINGS') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
for event, entries in hooks.items():
    for entry in entries:
        for hook in entry.get('hooks', []):
            cmd = hook.get('command', '')
            m = re.search(r'\.claude/hooks/[^\s\"]+\.sh', cmd)
            if m:
                print(m.group(0))
" 2>/dev/null || true)

while IFS= read -r rel_path; do
  [ -z "$rel_path" ] && continue
  full_path="$ROOT/$rel_path"
  if [ ! -f "$full_path" ]; then
    hk4_fails+=" $rel_path"
  fi
done <<< "$hk4_paths"
if [ -z "$hk4_fails" ]; then
  result "PASS" "HK-4" "all registered hook paths exist" "all paths resolved"
else
  result "FAIL" "HK-4" "all registered hook paths exist" "missing:${hk4_fails}"
fi

# HK-5, HK-6: removed (observe.sh removed — autoresearch simplification 2026-03-28)

# --- HK-7: gate hooks use exit 2 ---
GATE_HOOKS=("block-destructive.sh" "pre-commit-gate.sh" "pre-push-gate.sh")
hk7_fails=""
for gh in "${GATE_HOOKS[@]}"; do
  gf="$HOOKS_DIR/$gh"
  [ -f "$gf" ] || continue
  if ! grep -vE '^\s*#' "$gf" | grep -q 'exit 2'; then
    hk7_fails+=" $gh"
  fi
done
if [ -z "$hk7_fails" ]; then
  result "PASS" "HK-7" "gate hooks use exit 2 for blocking" "all gate hooks"
else
  result "FAIL" "HK-7" "gate hooks use exit 2 for blocking" "missing:${hk7_fails}"
fi

# --- HK-8: gate hooks write to stderr ---
hk8_fails=""
for gh in "${GATE_HOOKS[@]}"; do
  gf="$HOOKS_DIR/$gh"
  [ -f "$gf" ] || continue
  if ! grep -vE '^\s*#' "$gf" | grep -q '>&2'; then
    hk8_fails+=" $gh"
  fi
done
if [ -z "$hk8_fails" ]; then
  result "PASS" "HK-8" "gate hooks write to stderr" "all gate hooks"
else
  result "FAIL" "HK-8" "gate hooks write to stderr" "missing:${hk8_fails}"
fi

# --- HK-9: all hook events in settings.json are valid ---
VALID_EVENTS="SessionStart UserPromptSubmit PreToolUse PermissionRequest PostToolUse PostToolUseFailure Notification SubagentStart SubagentStop Stop StopFailure TeammateIdle TaskCompleted ConfigChange WorktreeCreate WorktreeRemove PreCompact PostCompact InstructionsLoaded Elicitation ElicitationResult SessionEnd"

hk9_fails=""
registered_events=$(python3 -c "
import json
with open('$SETTINGS') as f:
    data = json.load(f)
for event in data.get('hooks', {}).keys():
    print(event)
" 2>/dev/null || true)

while IFS= read -r ev; do
  [ -z "$ev" ] && continue
  if ! echo "$VALID_EVENTS" | grep -qw "$ev"; then
    hk9_fails+=" $ev"
  fi
done <<< "$registered_events"
if [ -z "$hk9_fails" ]; then
  result "PASS" "HK-9" "all hook events in settings.json are valid" "all events recognized"
else
  result "FAIL" "HK-9" "all hook events in settings.json are valid" "invalid:${hk9_fails}"
fi

# --- HK-10: hookSpecificOutput only on supported events ---
SUPPORTED_HSO="PreToolUse PostToolUse PostToolUseFailure PermissionRequest SessionStart SubagentStart UserPromptSubmit Notification Elicitation ElicitationResult TaskCompleted TeammateIdle"

hk10_fails=""
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  # Only match non-comment lines that actually output hookSpecificOutput JSON
  if grep -vE '^\s*#' "$f" | grep -q 'hookSpecificOutput\|hookEventName'; then
    fname=$(basename "$f")
    hook_events=$(python3 -c "
import json, re
with open('$SETTINGS') as fh:
    data = json.load(fh)
for event, entries in data.get('hooks', {}).items():
    for entry in entries:
        for hook in entry.get('hooks', []):
            cmd = hook.get('command', '')
            if '$fname' in cmd:
                print(event)
" 2>/dev/null || true)
    while IFS= read -r ev; do
      [ -z "$ev" ] && continue
      if ! echo "$SUPPORTED_HSO" | grep -qw "$ev"; then
        hk10_fails+=" $fname($ev)"
      fi
    done <<< "$hook_events"
  fi
done
if [ -z "$hk10_fails" ]; then
  result "PASS" "HK-10" "hookSpecificOutput only on supported events" "no violations"
else
  result "FAIL" "HK-10" "hookSpecificOutput only on supported events" "violations:${hk10_fails}"
fi

# --- HK-11: no 2>/dev/null on data writes (printf>>, echo>>, touch) ---
# Exempt: heartbeat.sh — non-blocking by design (must never block session)
hk11_fails=""
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  [ "$fname" = "heartbeat.sh" ] && continue
  if grep -vE '^\s*#' "$f" | grep -E '(printf|echo)\s.*>>' | grep -q '2>/dev/null'; then
    hk11_fails+=" $fname"
  fi
  if grep -vE '^\s*#' "$f" | grep -E 'touch\s' | grep -q '2>/dev/null'; then
    hk11_fails+=" $fname"
  fi
done
if [ -z "$hk11_fails" ]; then
  result "PASS" "HK-11" "no 2>/dev/null on data writes" "no violations"
else
  result "FAIL" "HK-11" "no 2>/dev/null on data writes" "violations:${hk11_fails}"
fi

# --- HK-12: no || true on writes ---
# Exempt: heartbeat.sh — non-blocking by design (must never block session)
hk12_fails=""
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  [ "$fname" = "heartbeat.sh" ] && continue
  if grep -vE '^\s*#' "$f" | grep -E '(printf|echo|touch|>>)' | grep -q '||[[:space:]]*true'; then
    hk12_fails+=" $fname"
  fi
done
if [ -z "$hk12_fails" ]; then
  result "PASS" "HK-12" "no || true on write operations" "no violations"
else
  result "FAIL" "HK-12" "no || true on write operations" "violations:${hk12_fails}"
fi

# --- HK-13: no || echo 0 arithmetic fallback ---
hk13_fails=""
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  # Match bare || echo 0 (numeric injection). Exclude || echo "0" with quotes (honest "no data" signal for wc -l)
  if grep -vE '^\s*#' "$f" | grep -E '\|\|[[:space:]]*(echo|printf)[[:space:]]+0[^"'"'"']' | grep -qv 'echo "0"'; then
    hk13_fails+=" $fname"
  fi
done
if [ -z "$hk13_fails" ]; then
  result "PASS" "HK-13" "no || echo 0 arithmetic fallback" "no violations"
else
  result "FAIL" "HK-13" "no || echo 0 arithmetic fallback" "violations:${hk13_fails}"
fi

# --- HK-14: stat chains don't end with echo 0 ---
hk14_fails=""
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  if grep -vE '^\s*#' "$f" | grep -E 'stat\s' | grep -qE '\|\|[[:space:]]*(echo|printf)[[:space:]]+"?0'; then
    hk14_fails+=" $fname"
  fi
done
if [ -z "$hk14_fails" ]; then
  result "PASS" "HK-14" "stat chains dont end with echo 0" "no violations"
else
  result "FAIL" "HK-14" "stat chains dont end with echo 0" "violations:${hk14_fails}"
fi

# --- HK-15: remaining 2>/dev/null have adjacent comments ---
hk15_fails=""
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  # Read file into array for context window lookup
  mapfile -t lines < "$f"
  total=${#lines[@]}
  for i in $(seq 0 $((total - 1))); do
    line="${lines[$i]}"
    line_num=$((i + 1))
    # Skip comment lines
    echo "$line" | grep -qE '^\s*#' && continue
    if echo "$line" | grep -q '2>/dev/null'; then
      justified=false
      # Accept if: same line has comment
      echo "$line" | grep -qE '#' && justified=true
      # Accept if: any of 3 preceding lines is a comment
      for offset in 1 2 3; do
        prev_idx=$((i - offset))
        [ "$prev_idx" -ge 0 ] && echo "${lines[$prev_idx]}" | grep -qE '^\s*#' && justified=true
      done
      # Accept if same line has explicit error handling after 2>/dev/null
      echo "$line" | grep -qE '2>/dev/null\)?\s*\|\|' && justified=true
      # Accept capability detection: command -v, which, type
      echo "$line" | grep -qE 'command -v|which |type ' && justified=true
      if ! $justified; then
        hk15_fails+=" $fname:${line_num}"
      fi
    fi
    prev_line="$line"
  done < "$f"
done
if [ -z "$hk15_fails" ]; then
  result "PASS" "HK-15" "2>/dev/null have adjacent comments" "all annotated"
else
  result "FAIL" "HK-15" "2>/dev/null have adjacent comments" "unannotated:${hk15_fails}"
fi

# --- HK-16: utility scripts have set -euo pipefail or set -eu ---
UTILITY_SCRIPTS=("mark-verified.sh" "review-complete.sh")
hk16_fails=""
for us in "${UTILITY_SCRIPTS[@]}"; do
  uf="$HOOKS_DIR/$us"
  [ -f "$uf" ] || continue
  if ! grep -qE 'set -eu|set -euo pipefail' "$uf"; then
    hk16_fails+=" $us"
  fi
done
if [ -z "$hk16_fails" ]; then
  result "PASS" "HK-16" "utility scripts have set -euo pipefail" "all utility scripts"
else
  result "FAIL" "HK-16" "utility scripts have set -euo pipefail" "missing:${hk16_fails}"
fi

# HK-17: removed (observe.sh removed — autoresearch simplification 2026-03-28)

# --- HK-18: helper scripts called from hooks are not silenced with || true ---
HELPER_SCRIPTS=("mark-verified.sh" "review-complete.sh")
hk18_fails=""
for hs in "${HELPER_SCRIPTS[@]}"; do
  for f in "$HOOKS_DIR"/*.sh; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    [ "$fname" = "$hs" ] && continue  # skip self-reference
    # Check for lines calling the helper with error suppression
    if grep -vE '^\s*#' "$f" | grep -q "$hs" && \
       grep -vE '^\s*#' "$f" | grep "$hs" | grep -qE '\|\|[[:space:]]*(true|:)'; then
      hk18_fails+=" $fname->$hs"
    fi
  done
done
if [ -z "$hk18_fails" ]; then
  result "PASS" "HK-18" "helper script error propagation" "no error suppression on helper calls"
else
  result "FAIL" "HK-18" "helper script error propagation" "suppressed:${hk18_fails}"
fi

# --- HK-19: Stop hooks count (refinement-gate included) ---
STOP_COUNT=$(jq '.hooks.Stop[0].hooks | length' "$SETTINGS" 2>/dev/null || echo "0")
if [ "$STOP_COUNT" -ge 2 ]; then
  result "PASS" "HK-19" "Stop hooks count" "$STOP_COUNT hooks (incl. refinement-gate)"
else
  result "FAIL" "HK-19" "Stop hooks count" "expected >=2, got $STOP_COUNT"
fi

# --- HK-20: refinement-gate.sh registered in settings.json ---
if jq -r '.hooks.Stop[0].hooks[].command' "$SETTINGS" 2>/dev/null | grep -q 'refinement-gate'; then
  result "PASS" "HK-20" "refinement-gate registered in Stop hooks"
else
  result "FAIL" "HK-20" "refinement-gate registered in Stop hooks" "not found"
fi

# --- HK-21: subagent-start-report.sh functional test ---
SUBSTART_HOOK="$HOOKS_DIR/subagent-start-report.sh"
if [ -f "$SUBSTART_HOOK" ]; then
  SUBSTART_OUT=$(echo '{"agent_type":"test-agent","agent_id":"test-123","session_id":"s1"}' | bash "$SUBSTART_HOOK" 2>&1)
  if grep -q 'SubagentStart.*agent=test-agent.*id=test-123' "$ACTUAL_ROOT/.claude/subagent.log" 2>/dev/null; then
    result "PASS" "HK-21" "subagent-start-report functional" "logged agent_type+agent_id"
  else
    result "FAIL" "HK-21" "subagent-start-report functional" "log entry not found"
  fi
else
  result "SKIP" "HK-21" "subagent-start-report functional" "file missing"
fi

# --- HK-22: session-end.sh functional test ---
SESSEND_HOOK="$HOOKS_DIR/session-end.sh"
if [ -f "$SESSEND_HOOK" ]; then
  echo '{"source":"test","session_id":"test-sess"}' | bash "$SESSEND_HOOK" 2>&1 >/dev/null
  if [ -f "$ACTUAL_ROOT/.claude/session-metrics.log" ] && \
     grep -q '"event":"session_end".*"session_id":"test-sess"' "$ACTUAL_ROOT/.claude/session-metrics.log" 2>/dev/null; then
    result "PASS" "HK-22" "session-end functional" "JSONL entry written"
  else
    result "FAIL" "HK-22" "session-end functional" "log entry not found"
  fi
else
  result "SKIP" "HK-22" "session-end functional" "file missing"
fi

# --- HK-23: user-prompt-submit.sh functional test (no active state) ---
UPS_HOOK="$HOOKS_DIR/user-prompt-submit.sh"
if [ -f "$UPS_HOOK" ]; then
  UPS_OUT=$(echo '{}' | bash "$UPS_HOOK" 2>&1)
  if [ -z "$UPS_OUT" ]; then
    result "PASS" "HK-23" "user-prompt-submit no-state" "silent when no active markers"
  else
    result "FAIL" "HK-23" "user-prompt-submit no-state" "unexpected output: $UPS_OUT"
  fi
else
  result "SKIP" "HK-23" "user-prompt-submit no-state" "file missing"
fi

# --- HK-24: all hooks on disk are either registered or documented helpers ---
REGISTERED_HOOKS=$(jq -r '.. | .command? // empty' "$SETTINGS" 2>/dev/null | grep -oE '[^/]+\.sh' | sort -u)
HELPER_HOOKS="claude-update-check.sh worker-guard.sh mark-verified.sh review-complete.sh test-hooks.sh"
hk24_fails=""
for hook_file in "$HOOKS_DIR"/*.sh; do
  fname=$(basename "$hook_file")
  if ! echo "$REGISTERED_HOOKS" | grep -qF "$fname" && ! echo "$HELPER_HOOKS" | grep -qwF "$fname"; then
    hk24_fails+=" $fname"
  fi
done
if [ -z "$hk24_fails" ]; then
  result "PASS" "HK-24" "all hooks registered or documented helpers" "no orphans"
else
  result "FAIL" "HK-24" "all hooks registered or documented helpers" "orphans:${hk24_fails}"
fi

TOTAL=$((PASS + FAIL + SKIP))
echo "---"
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
