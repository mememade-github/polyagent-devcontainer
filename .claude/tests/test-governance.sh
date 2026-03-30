#!/bin/bash
# test-governance.sh — Governance, Knowledge Management, Evolution, Team Patterns checks
# GV-1..4, KM-1..6, EV-1..5, TP-1..2 + SKIPs

set -euo pipefail

ROOT="${1:-/workspaces}"
CLAUDE_DIR="$ROOT/.claude"
CLAUDE_MD="$ROOT/CLAUDE.md"
PASS=0; FAIL=0; SKIP=0

result() {
  local status="$1" id="$2" desc="$3" detail="${4:-}"
  if [ "$status" = "PASS" ]; then PASS=$((PASS + 1)); fi
  if [ "$status" = "FAIL" ]; then FAIL=$((FAIL + 1)); fi
  if [ "$status" = "SKIP" ]; then SKIP=$((SKIP + 1)); fi
  echo "$status: $id $desc ($detail)"
}

# Extract frontmatter from a file
get_frontmatter() {
  local file="$1"
  sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d'
}

get_field() {
  local fm="$1" field="$2"
  echo "$fm" | grep -E "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//" || true
}

has_field() {
  local fm="$1" field="$2"
  echo "$fm" | grep -qE "^${field}:"
}

# ===== GOVERNANCE (GV-1..4) =====

# GV-1: 7 immutable principles in CLAUDE.md
if [ -f "$CLAUDE_MD" ]; then
  principles_found=0
  grep -qi 'INTEGRITY' "$CLAUDE_MD" && principles_found=$((principles_found + 1))
  grep -qi 'Destructive.*approval\|APPROVAL REQUIRED' "$CLAUDE_MD" && principles_found=$((principles_found + 1))
  grep -qi 'secrets\|credentials' "$CLAUDE_MD" && principles_found=$((principles_found + 1))
  grep -qi 'Read first' "$CLAUDE_MD" && principles_found=$((principles_found + 1))
  grep -qi 'Verify.*Build\|Build and test' "$CLAUDE_MD" && principles_found=$((principles_found + 1))
  grep -qi 'root cause\|Fix root' "$CLAUDE_MD" && principles_found=$((principles_found + 1))
  grep -qi 'Explicit failure\|arbitrary success' "$CLAUDE_MD" && principles_found=$((principles_found + 1))
  if [ "$principles_found" -ge 7 ]; then
    result "PASS" "GV-1" "7 immutable principles in CLAUDE.md" "$principles_found found"
  else
    result "FAIL" "GV-1" "7 immutable principles in CLAUDE.md" "only $principles_found found"
  fi
else
  result "FAIL" "GV-1" "7 immutable principles in CLAUDE.md" "CLAUDE.md not found"
fi

# GV-2: no secrets in git-tracked .claude/ files
gv2_fails=""
if command -v git &>/dev/null; then
  tracked_files=$(git -C "$ROOT" ls-files .claude/ 2>/dev/null || true)
  while IFS= read -r tf; do
    [ -z "$tf" ] && continue
    full="$ROOT/$tf"
    [ -f "$full" ] || continue
    # Check for actual long token patterns (not just mentions in docs)
    if grep -qE 'github_pat_[a-zA-Z0-9]{20,}|glpat-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{20,}' "$full" 2>/dev/null; then
      gv2_fails+=" $tf"
    fi
  done <<< "$tracked_files"
fi
if [ -z "$gv2_fails" ]; then
  result "PASS" "GV-2" "no secrets in git-tracked .claude/ files" "no PAT patterns found"
else
  result "FAIL" "GV-2" "no secrets in git-tracked .claude/ files" "found:${gv2_fails}"
fi

# GV-3: no project-specific refs in portable rules (rules/*.md, NOT rules/project/*)
gv3_fails=""
for rf in "$CLAUDE_DIR"/rules/*.md; do
  [ -f "$rf" ] || continue
  fname=$(basename "$rf")
  if grep -iE '\bmememade\b|<internal-rag>|<internal-web>|<internal-leaf>|<internal-root>' "$rf" > /dev/null 2>&1; then
    gv3_fails+=" $fname"
  fi
done
# Only portable rules (rules/*.md) are checked, not rules/project/.
if [ -z "$gv3_fails" ]; then
  result "PASS" "GV-3" "no project-specific refs in portable rules" "clean"
else
  result "FAIL" "GV-3" "no project-specific refs in portable rules" "found:${gv3_fails}"
fi

# GV-4: block-destructive.sh registered in settings.json
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  if grep -q 'block-destructive' "$CLAUDE_DIR/settings.json"; then
    result "PASS" "GV-4" "block-destructive.sh registered in settings.json" "found"
  else
    result "FAIL" "GV-4" "block-destructive.sh registered in settings.json" "not registered"
  fi
else
  result "FAIL" "GV-4" "block-destructive.sh registered in settings.json" "settings.json not found"
fi

# ===== KNOWLEDGE MANAGEMENT (KM-1..6) =====

# KM-1: CLAUDE.md exists
if [ -f "$CLAUDE_MD" ]; then
  result "PASS" "KM-1" "CLAUDE.md exists" "at $CLAUDE_MD"
else
  result "FAIL" "KM-1" "CLAUDE.md exists" "not found"
fi

# KM-2: CLAUDE.md under 200 lines
if [ -f "$CLAUDE_MD" ]; then
  line_count=$(wc -l < "$CLAUDE_MD")
  if [ "$line_count" -le 200 ]; then
    result "PASS" "KM-2" "CLAUDE.md under 200 lines" "${line_count} lines"
  else
    result "FAIL" "KM-2" "CLAUDE.md under 200 lines" "${line_count} lines"
  fi
else
  result "FAIL" "KM-2" "CLAUDE.md under 200 lines" "file not found"
fi

# KM-3: all agents with memory:project have agent-memory/NAME/MEMORY.md
km3_fails=""
for af in "$CLAUDE_DIR"/agents/*.md; do
  [ -f "$af" ] || continue
  fm=$(get_frontmatter "$af")
  mem_val=$(get_field "$fm" "memory")
  if [ "$mem_val" = "project" ]; then
    aname=$(get_field "$fm" "name")
    if [ ! -f "$CLAUDE_DIR/agent-memory/$aname/MEMORY.md" ]; then
      km3_fails+=" $aname"
    fi
  fi
done
if [ -z "$km3_fails" ]; then
  result "PASS" "KM-3" "agents with memory:project have MEMORY.md" "all agents"
else
  result "FAIL" "KM-3" "agents with memory:project have MEMORY.md" "missing:${km3_fails}"
fi

# KM-4: rules single-topic (count H1 headers outside code blocks per file)
km4_fails=""
for rf in "$CLAUDE_DIR"/rules/*.md "$CLAUDE_DIR"/rules/project/*.md; do
  [ -f "$rf" ] || continue
  fname=$(basename "$rf")
  # Count H1 headers (^# ) outside code blocks
  h1_count=$(sed '/^```/,/^```/d' "$rf" | grep -cE '^# ' || true)
  if [ "$h1_count" -gt 1 ]; then
    km4_fails+=" $fname(${h1_count}H1)"
  fi
done
if [ -z "$km4_fails" ]; then
  result "PASS" "KM-4" "rules are single-topic (1 H1 max)" "all rules"
else
  result "FAIL" "KM-4" "rules are single-topic (1 H1 max)" "multiple H1:${km4_fails}"
fi

# KM-5: all skills have SKILL.md with description
km5_fails=""
for skill_dir in "$CLAUDE_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  sname=$(basename "$skill_dir")
  skill_file="$skill_dir/SKILL.md"
  if [ ! -f "$skill_file" ]; then
    km5_fails+=" $sname(no SKILL.md)"
  else
    fm=$(get_frontmatter "$skill_file")
    desc=$(get_field "$fm" "description")
    if [ -z "$desc" ]; then
      km5_fails+=" $sname(no description)"
    fi
  fi
done
if [ -z "$km5_fails" ]; then
  result "PASS" "KM-5" "all skills have SKILL.md with description" "all skills"
else
  result "FAIL" "KM-5" "all skills have SKILL.md with description" "issues:${km5_fails}"
fi

# ===== TEAM PATTERNS =====

# TP-1: all agents have model
tp1_fails=""
for af in "$CLAUDE_DIR"/agents/*.md; do
  [ -f "$af" ] || continue
  fm=$(get_frontmatter "$af")
  if ! has_field "$fm" "model"; then
    tp1_fails+=" $(basename "$af" .md)"
  fi
done
if [ -z "$tp1_fails" ]; then
  result "PASS" "TP-1" "all agents have model" "all agents"
else
  result "FAIL" "TP-1" "all agents have model" "missing:${tp1_fails}"
fi

# TP-2: all agents have maxTurns
tp2_fails=""
for af in "$CLAUDE_DIR"/agents/*.md; do
  [ -f "$af" ] || continue
  fm=$(get_frontmatter "$af")
  if ! has_field "$fm" "maxTurns"; then
    tp2_fails+=" $(basename "$af" .md)"
  fi
done
if [ -z "$tp2_fails" ]; then
  result "PASS" "TP-2" "all agents have maxTurns" "all agents"
else
  result "FAIL" "TP-2" "all agents have maxTurns" "missing:${tp2_fails}"
fi

# TP-3: refinement-gate registered in Stop hooks
tp3_has_refine=$(python3 -c "
import json
with open('$CLAUDE_DIR/settings.json') as f:
    data = json.load(f)
hooks = data.get('hooks', {}).get('Stop', [{}])[0].get('hooks', [])
for h in hooks:
    if 'refinement-gate' in h.get('command', ''):
        print('yes')
        break
" 2>/dev/null || echo "")
if [ "$tp3_has_refine" = "yes" ]; then
  result "PASS" "TP-3" "refinement-gate registered in Stop hooks"
else
  result "FAIL" "TP-3" "refinement-gate not found in Stop hooks"
fi

# TP-4: team sizing — all agents in agent-overrides.md exist as files
tp4_fails=""
OVERRIDES="$CLAUDE_DIR/rules/project/agent-overrides.md"
if [ -f "$OVERRIDES" ]; then
  # Extract agent names from the inventory table (2nd column is a number = maxTurns)
  override_agents=$(grep -E '^\| [a-z]' "$OVERRIDES" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); if ($3 ~ /^[0-9]+$/) print $2}' | sort -u)
  while IFS= read -r aname; do
    [ -z "$aname" ] && continue
    if [ ! -f "$CLAUDE_DIR/agents/${aname}.md" ]; then
      tp4_fails+=" $aname"
    fi
  done <<< "$override_agents"
  agent_count=$(echo "$override_agents" | grep -c . || true)
  if [ -z "$tp4_fails" ]; then
    result "PASS" "TP-4" "team sizing compliance" "$agent_count agents in overrides, all exist"
  else
    result "FAIL" "TP-4" "team sizing compliance" "missing agent files:${tp4_fails}"
  fi
else
  result "FAIL" "TP-4" "team sizing compliance" "agent-overrides.md not found"
fi

# TP-5: agent delegation — CLAUDE.md agent table matches agent-overrides.md inventory
tp5_ok=true
if [ -f "$CLAUDE_MD" ] && [ -f "$OVERRIDES" ]; then
  # Extract agent names from CLAUDE.md delegation table
  claude_agents=$(grep -E '^\| (evaluator|wip-manager) ' "$CLAUDE_MD" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' | sort)
  # Extract agent names from agent-overrides.md inventory table
  override_agents=$(grep -E '^\| (evaluator|wip-manager) ' "$OVERRIDES" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' | sort)
  if [ "$claude_agents" = "$override_agents" ] && [ -n "$claude_agents" ]; then
    agent_count=$(echo "$claude_agents" | wc -l)
    result "PASS" "TP-5" "agent delegation protocol" "$agent_count agents consistent across CLAUDE.md and overrides"
  else
    tp5_ok=false
    result "FAIL" "TP-5" "agent delegation protocol" "agent tables diverge between CLAUDE.md and overrides"
  fi
else
  result "FAIL" "TP-5" "agent delegation protocol" "CLAUDE.md or agent-overrides.md not found"
fi

TOTAL=$((PASS + FAIL + SKIP))
echo "---"
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
