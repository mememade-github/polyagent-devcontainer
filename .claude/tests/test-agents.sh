#!/bin/bash
# test-agents.sh — Agent Definition Standard compliance checks (AD-1..AD-13)
# Validates all .claude/agents/*.md against agent-definition + project-overrides standards.

set -euo pipefail

ROOT="${1:-/workspaces}"
AGENTS_DIR="$ROOT/.claude/agents"
PASS=0; FAIL=0; SKIP=0

result() {
  local status="$1" id="$2" desc="$3" detail="${4:-}"
  if [ "$status" = "PASS" ]; then PASS=$((PASS + 1)); fi
  if [ "$status" = "FAIL" ]; then FAIL=$((FAIL + 1)); fi
  if [ "$status" = "SKIP" ]; then SKIP=$((SKIP + 1)); fi
  echo "$status: $id $desc ($detail)"
}

# Extract frontmatter (between first --- and second ---)
get_frontmatter() {
  local file="$1"
  sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d'
}

# Get single-line field value from frontmatter text
get_field() {
  local fm="$1" field="$2"
  echo "$fm" | grep -E "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//" || true
}

# Check if field exists in frontmatter
has_field() {
  local fm="$1" field="$2"
  echo "$fm" | grep -qE "^${field}:"
}

# Check if multi-line YAML list field has items (for mcpServers, skills, hooks)
# These use:
#   field:
#     - item1
# NOT inline [item1] format
has_list_field_items() {
  local file="$1" field="$2"
  local in_fm=0 found=0
  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; fi
      break
    fi
    if [ "$in_fm" -eq 1 ]; then
      if [ "$found" -eq 1 ]; then
        if echo "$line" | grep -qE '^[[:space:]]+-'; then
          return 0
        else
          return 1
        fi
      fi
      if echo "$line" | grep -qE "^${field}:"; then
        local val
        val=$(echo "$line" | sed "s/^${field}:[[:space:]]*//" )
        if [ -n "$val" ]; then
          return 0
        fi
        found=1
      fi
    fi
  done < "$file"
  return 1
}

# Role-based tool sets (from agent-overrides.md)
declare -A EXPECTED_TOOLS_MAP
EXPECTED_TOOLS_MAP[agent-evolver]='["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]'
EXPECTED_TOOLS_MAP[architect]='["Read", "Grep", "Glob"]'
EXPECTED_TOOLS_MAP[build-error-resolver]='["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]'
EXPECTED_TOOLS_MAP[code-reviewer]='["Read", "Grep", "Glob"]'
EXPECTED_TOOLS_MAP[database-reviewer]='["Read", "Grep", "Glob"]'
EXPECTED_TOOLS_MAP[debugger]='["Read", "Bash", "Grep", "Glob"]'
EXPECTED_TOOLS_MAP[doc-updater]='["Read", "Write", "Edit", "Grep", "Glob"]'
EXPECTED_TOOLS_MAP[e2e-runner]='["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]'
EXPECTED_TOOLS_MAP[environment-checker]='["Read", "Bash", "Grep", "Glob"]'
EXPECTED_TOOLS_MAP[planner]='["Read", "Grep", "Glob", "WebSearch", "WebFetch"]'
EXPECTED_TOOLS_MAP[refactor-cleaner]='["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]'
EXPECTED_TOOLS_MAP[security-reviewer]='["Read", "Grep", "Glob"]'
EXPECTED_TOOLS_MAP[tdd-guide]='["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]'
EXPECTED_TOOLS_MAP[wip-manager]='["Read", "Write", "Grep", "Glob"]'

# Agents that require memory: project
declare -A MEMORY_REQUIRED
MEMORY_REQUIRED[agent-evolver]=1
MEMORY_REQUIRED[wip-manager]=1

declare -A CHECK_PASS CHECK_FAIL CHECK_DETAIL

for id in AD-{1,2,3,4,5,6,7,8,9,10,11,12,13}; do
  CHECK_PASS[$id]=0
  CHECK_FAIL[$id]=0
  CHECK_DETAIL[$id]=""
done

AGENT_COUNT=0
for agent_file in "$AGENTS_DIR"/*.md; do
  [ -f "$agent_file" ] || continue
  AGENT_COUNT=$((AGENT_COUNT + 1))
  fname=$(basename "$agent_file" .md)
  fm=$(get_frontmatter "$agent_file")

  # AD-1: name matches filename
  name_val=$(get_field "$fm" "name")
  if [ "$name_val" = "$fname" ]; then
    CHECK_PASS[AD-1]=$((${CHECK_PASS[AD-1]} + 1))
  else
    CHECK_FAIL[AD-1]=$((${CHECK_FAIL[AD-1]} + 1))
    CHECK_DETAIL[AD-1]+=" $fname"
  fi

  # AD-2: tools matches role-based expected set
  tools_val=$(get_field "$fm" "tools")
  expected_tools="${EXPECTED_TOOLS_MAP[$fname]:-}"
  if [ -n "$expected_tools" ] && [ "$tools_val" = "$expected_tools" ]; then
    CHECK_PASS[AD-2]=$((${CHECK_PASS[AD-2]} + 1))
  else
    CHECK_FAIL[AD-2]=$((${CHECK_FAIL[AD-2]} + 1))
    CHECK_DETAIL[AD-2]+=" $fname"
  fi

  # AD-3: model = opus
  model_val=$(get_field "$fm" "model")
  if [ "$model_val" = "opus" ]; then
    CHECK_PASS[AD-3]=$((${CHECK_PASS[AD-3]} + 1))
  else
    CHECK_FAIL[AD-3]=$((${CHECK_FAIL[AD-3]} + 1))
    CHECK_DETAIL[AD-3]+=" $fname"
  fi

  # AD-4: maxTurns in 8-20
  mt_val=$(get_field "$fm" "maxTurns")
  if [ -n "$mt_val" ] && [ "$mt_val" -ge 8 ] 2>/dev/null && [ "$mt_val" -le 20 ] 2>/dev/null; then
    CHECK_PASS[AD-4]=$((${CHECK_PASS[AD-4]} + 1))
  else
    CHECK_FAIL[AD-4]=$((${CHECK_FAIL[AD-4]} + 1))
    CHECK_DETAIL[AD-4]+=" $fname($mt_val)"
  fi

  # AD-5: memory = project if required, optional otherwise
  mem_val=$(get_field "$fm" "memory")
  if [ "${MEMORY_REQUIRED[$fname]:-0}" = "1" ]; then
    if [ "$mem_val" = "project" ]; then
      CHECK_PASS[AD-5]=$((${CHECK_PASS[AD-5]} + 1))
    else
      CHECK_FAIL[AD-5]=$((${CHECK_FAIL[AD-5]} + 1))
      CHECK_DETAIL[AD-5]+=" $fname(required)"
    fi
  else
    if [ -z "$mem_val" ] || [ "$mem_val" = "project" ]; then
      CHECK_PASS[AD-5]=$((${CHECK_PASS[AD-5]} + 1))
    else
      CHECK_FAIL[AD-5]=$((${CHECK_FAIL[AD-5]} + 1))
      CHECK_DETAIL[AD-5]+=" $fname($mem_val)"
    fi
  fi

  # AD-6: effort not in frontmatter (global effortLevel in settings.json)
  if has_field "$fm" "effort"; then
    CHECK_FAIL[AD-6]=$((${CHECK_FAIL[AD-6]} + 1))
    CHECK_DETAIL[AD-6]+=" $fname"
  else
    CHECK_PASS[AD-6]=$((${CHECK_PASS[AD-6]} + 1))
  fi

  # AD-7: no disallowedTools
  if has_field "$fm" "disallowedTools"; then
    CHECK_FAIL[AD-7]=$((${CHECK_FAIL[AD-7]} + 1))
    CHECK_DETAIL[AD-7]+=" $fname"
  else
    CHECK_PASS[AD-7]=$((${CHECK_PASS[AD-7]} + 1))
  fi

  # AD-8: no permissionMode
  if has_field "$fm" "permissionMode"; then
    CHECK_FAIL[AD-8]=$((${CHECK_FAIL[AD-8]} + 1))
    CHECK_DETAIL[AD-8]+=" $fname"
  else
    CHECK_PASS[AD-8]=$((${CHECK_PASS[AD-8]} + 1))
  fi

  # AD-9: description is single line and non-empty
  desc_val=$(get_field "$fm" "description")
  if [ -n "$desc_val" ]; then
    desc_lines=$(echo "$desc_val" | wc -l)
    if [ "$desc_lines" -eq 1 ]; then
      CHECK_PASS[AD-9]=$((${CHECK_PASS[AD-9]} + 1))
    else
      CHECK_FAIL[AD-9]=$((${CHECK_FAIL[AD-9]} + 1))
      CHECK_DETAIL[AD-9]+=" $fname(multiline)"
    fi
  else
    CHECK_FAIL[AD-9]=$((${CHECK_FAIL[AD-9]} + 1))
    CHECK_DETAIL[AD-9]+=" $fname(empty)"
  fi

  # AD-10: if isolation exists, must be "worktree"
  if has_field "$fm" "isolation"; then
    iso_val=$(get_field "$fm" "isolation")
    if [ "$iso_val" = "worktree" ]; then
      CHECK_PASS[AD-10]=$((${CHECK_PASS[AD-10]} + 1))
    else
      CHECK_FAIL[AD-10]=$((${CHECK_FAIL[AD-10]} + 1))
      CHECK_DETAIL[AD-10]+=" $fname($iso_val)"
    fi
  else
    CHECK_PASS[AD-10]=$((${CHECK_PASS[AD-10]} + 1))
  fi

  # AD-11: if background exists, must be "true"
  if has_field "$fm" "background"; then
    bg_val=$(get_field "$fm" "background")
    if [ "$bg_val" = "true" ]; then
      CHECK_PASS[AD-11]=$((${CHECK_PASS[AD-11]} + 1))
    else
      CHECK_FAIL[AD-11]=$((${CHECK_FAIL[AD-11]} + 1))
      CHECK_DETAIL[AD-11]+=" $fname($bg_val)"
    fi
  else
    CHECK_PASS[AD-11]=$((${CHECK_PASS[AD-11]} + 1))
  fi

  # AD-12: if mcpServers exists, must have list items (multi-line format)
  if has_field "$fm" "mcpServers"; then
    if has_list_field_items "$agent_file" "mcpServers"; then
      CHECK_PASS[AD-12]=$((${CHECK_PASS[AD-12]} + 1))
    else
      CHECK_FAIL[AD-12]=$((${CHECK_FAIL[AD-12]} + 1))
      CHECK_DETAIL[AD-12]+=" $fname(empty)"
    fi
  else
    CHECK_PASS[AD-12]=$((${CHECK_PASS[AD-12]} + 1))
  fi

  # AD-13: if skills exists, must have list items (multi-line format)
  if has_field "$fm" "skills"; then
    if has_list_field_items "$agent_file" "skills"; then
      CHECK_PASS[AD-13]=$((${CHECK_PASS[AD-13]} + 1))
    else
      CHECK_FAIL[AD-13]=$((${CHECK_FAIL[AD-13]} + 1))
      CHECK_DETAIL[AD-13]+=" $fname(empty)"
    fi
  else
    CHECK_PASS[AD-13]=$((${CHECK_PASS[AD-13]} + 1))
  fi

done

# Emit results
DESCS=(
  [1]="name matches filename"
  [2]="tools matches role-based set"
  [3]="model is opus"
  [4]="maxTurns in 8-20"
  [5]="memory is project where required"
  [6]="effort not in frontmatter (global)"
  [7]="no disallowedTools"
  [8]="no permissionMode"
  [9]="description single-line non-empty"
  [10]="isolation is worktree if present"
  [11]="background is true if present"
  [12]="mcpServers has items if present"
  [13]="skills has items if present"
)

for i in $(seq 1 13); do
  id="AD-$i"
  p=${CHECK_PASS[$id]}
  f=${CHECK_FAIL[$id]}
  detail=${CHECK_DETAIL[$id]}
  if [ "$f" -eq 0 ]; then
    result "PASS" "$id" "${DESCS[$i]}" "${p}/${AGENT_COUNT} agents"
  else
    result "FAIL" "$id" "${DESCS[$i]}" "failed:${detail}"
  fi
done

TOTAL=$((PASS + FAIL + SKIP))
echo "---"
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
