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
# Note: rules/standards/ is NOT checked — it is being replaced by tests/
# and will be deleted. Only portable rules (rules/*.md) are checked.
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

# KM-6: instincts dirs exist (personal, inherited, archive)
km6_missing=""
for subdir in personal inherited archive; do
  if [ ! -d "$CLAUDE_DIR/instincts/$subdir" ]; then
    km6_missing+=" $subdir"
  fi
done
if [ -z "$km6_missing" ]; then
  result "PASS" "KM-6" "instincts dirs exist" "personal, inherited, archive"
else
  result "FAIL" "KM-6" "instincts dirs exist" "missing:${km6_missing}"
fi

# ===== EVOLUTION (EV-1..5) =====

# EV-1: instinct frontmatter has id, trigger, confidence, domain
ev1_fails=""
instinct_count=0
for inst in "$CLAUDE_DIR"/instincts/personal/*.md "$CLAUDE_DIR"/instincts/inherited/*.md; do
  [ -f "$inst" ] || continue
  instinct_count=$((instinct_count + 1))
  fm=$(get_frontmatter "$inst")
  missing=""
  has_field "$fm" "id" || missing+="id,"
  has_field "$fm" "trigger" || missing+="trigger,"
  has_field "$fm" "confidence" || missing+="confidence,"
  has_field "$fm" "domain" || missing+="domain,"
  if [ -n "$missing" ]; then
    ev1_fails+=" $(basename "$inst")(${missing%,})"
  fi
done
if [ "$instinct_count" -eq 0 ]; then
  result "SKIP" "EV-1" "instinct frontmatter has required fields" "no instincts found"
else
  if [ -z "$ev1_fails" ]; then
    result "PASS" "EV-1" "instinct frontmatter has required fields" "$instinct_count instincts"
  else
    result "FAIL" "EV-1" "instinct frontmatter has required fields" "missing:${ev1_fails}"
  fi
fi

# EV-2: confidence in [0.0, 1.0]
ev2_fails=""
ev2_count=0
for inst in "$CLAUDE_DIR"/instincts/personal/*.md "$CLAUDE_DIR"/instincts/inherited/*.md; do
  [ -f "$inst" ] || continue
  fm=$(get_frontmatter "$inst")
  conf=$(get_field "$fm" "confidence")
  if [ -n "$conf" ]; then
    ev2_count=$((ev2_count + 1))
    in_range=$(python3 -c "c=float('$conf'); print('yes' if 0.0 <= c <= 1.0 else 'no')" 2>/dev/null || echo "no")
    if [ "$in_range" != "yes" ]; then
      ev2_fails+=" $(basename "$inst")($conf)"
    fi
  fi
done
if [ "$ev2_count" -eq 0 ]; then
  result "SKIP" "EV-2" "confidence in [0.0, 1.0]" "no instincts with confidence"
else
  if [ -z "$ev2_fails" ]; then
    result "PASS" "EV-2" "confidence in [0.0, 1.0]" "$ev2_count instincts"
  else
    result "FAIL" "EV-2" "confidence in [0.0, 1.0]" "out of range:${ev2_fails}"
  fi
fi

# EV-3: archived instincts below 0.2
ev3_fails=""
ev3_count=0
for inst in "$CLAUDE_DIR"/instincts/archive/*.md; do
  [ -f "$inst" ] || continue
  ev3_count=$((ev3_count + 1))
  fm=$(get_frontmatter "$inst")
  conf=$(get_field "$fm" "confidence")
  if [ -n "$conf" ]; then
    below=$(python3 -c "c=float('$conf'); print('yes' if c < 0.2 else 'no')" 2>/dev/null || echo "no")
    if [ "$below" != "yes" ]; then
      ev3_fails+=" $(basename "$inst")($conf)"
    fi
  fi
done
if [ "$ev3_count" -eq 0 ]; then
  result "SKIP" "EV-3" "archived instincts below 0.2" "no archived instincts"
else
  if [ -z "$ev3_fails" ]; then
    result "PASS" "EV-3" "archived instincts below 0.2" "$ev3_count archived"
  else
    result "FAIL" "EV-3" "archived instincts below 0.2" "above threshold:${ev3_fails}"
  fi
fi

# EV-4: SKIP (evolved artifact locations — requires runtime tracing)
result "SKIP" "EV-4" "evolved artifact locations" "runtime only"

# EV-5: mark-evolved.sh exists
if [ -f "$CLAUDE_DIR/hooks/mark-evolved.sh" ]; then
  result "PASS" "EV-5" "mark-evolved.sh exists" "found"
else
  result "FAIL" "EV-5" "mark-evolved.sh exists" "not found"
fi

# ===== TEAM PATTERNS (TP-1..2 + 4 SKIPs) =====

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

# TP-3..6: SKIP (runtime only — team lifecycle, communication, etc.)
result "SKIP" "TP-3" "team lifecycle enforcement" "runtime only"
result "SKIP" "TP-4" "team sizing compliance" "runtime only"
result "SKIP" "TP-5" "task assignment protocol" "runtime only"
result "SKIP" "TP-6" "communication protocol" "runtime only"

TOTAL=$((PASS + FAIL + SKIP))
echo "---"
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
