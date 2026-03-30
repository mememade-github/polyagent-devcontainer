#!/bin/bash
# test-sync.sh — Sync consistency check across 5 distribution targets
# Dynamically checks which sync dirs exist in ROOT .claude/ and verifies
# consistency with all targets from PROJECT.md distribution map.

set -euo pipefail

ROOT="${1:-/workspaces}"
ROOT_CLAUDE="$ROOT/.claude"
PASS=0; FAIL=0; SKIP=0

result() {
  local status="$1" id="$2" desc="$3" detail="${4:-}"
  if [ "$status" = "PASS" ]; then PASS=$((PASS + 1)); fi
  if [ "$status" = "FAIL" ]; then FAIL=$((FAIL + 1)); fi
  if [ "$status" = "SKIP" ]; then SKIP=$((SKIP + 1)); fi
  echo "$status: $id $desc ($detail)"
}

# Sync targets (Full copy projects from PROJECT.md)
SYNC_TARGETS=(
  "products/derived/<workspace-root>/claude-devcontainer"
  "products/derived/<workspace-root>/claude-datascience-devcontainer"
  "products/derived/<workspace-leaf>/<internal-rag>"
)

# Syncable directories (what syncs per PROJECT.md):
# rules/ (root-level), skills/, hooks/, agents/, tests/, docs/, settings.json
# What does NOT sync: rules/project/ (except agent-overrides.md), agent-memory/

# Build list of syncable dirs that actually exist in ROOT
SYNC_DIRS=()
for candidate in rules skills hooks agents tests docs; do
  if [ -d "$ROOT_CLAUDE/$candidate" ]; then
    SYNC_DIRS+=("$candidate")
  fi
done

# Also check settings.json
HAS_SETTINGS=false
if [ -f "$ROOT_CLAUDE/settings.json" ]; then
  HAS_SETTINGS=true
fi

target_num=0
for target_rel in "${SYNC_TARGETS[@]}"; do
  target_num=$((target_num + 1))
  target_path="$ROOT/$target_rel"
  target_claude="$target_path/.claude"
  id="SY-$target_num"
  target_name=$(basename "$target_rel")

  if [ ! -d "$target_claude" ]; then
    result "SKIP" "$id" "sync: $target_name" "target .claude/ not found at $target_rel"
    continue
  fi

  diffs=""
  diff_count=0

  # Check each syncable directory
  for sync_dir in "${SYNC_DIRS[@]}"; do
    root_dir="$ROOT_CLAUDE/$sync_dir"
    target_dir="$target_claude/$sync_dir"

    # For rules/, exclude rules/project/ (project-specific, not synced)
    if [ "$sync_dir" = "rules" ]; then
      # Compare root-level rules
      for rf in "$root_dir"/*.md; do
        [ -f "$rf" ] || continue
        fname=$(basename "$rf")
        tf="$target_dir/$fname"
        if [ ! -f "$tf" ]; then
          diffs+=" $sync_dir/$fname(missing)"
          diff_count=$((diff_count + 1))
        elif ! diff -q "$rf" "$tf" > /dev/null 2>&1; then
          diffs+=" $sync_dir/$fname(differs)"
          diff_count=$((diff_count + 1))
        fi
      done
      # Check rules/project/agent-overrides.md (synced per PROJECT.md)
      ao_root="$root_dir/project/agent-overrides.md"
      ao_target="$target_dir/project/agent-overrides.md"
      if [ -f "$ao_root" ]; then
        if [ ! -f "$ao_target" ]; then
          diffs+=" $sync_dir/project/agent-overrides.md(missing)"
          diff_count=$((diff_count + 1))
        elif ! diff -q "$ao_root" "$ao_target" > /dev/null 2>&1; then
          diffs+=" $sync_dir/project/agent-overrides.md(differs)"
          diff_count=$((diff_count + 1))
        fi
      fi
      continue
    fi

    # For other dirs (skills, hooks, agents), compare all files
    if [ ! -d "$target_dir" ]; then
      diffs+=" $sync_dir/(missing dir)"
      diff_count=$((diff_count + 1))
      continue
    fi

    for rf in "$root_dir"/*; do
      [ -e "$rf" ] || continue
      fname=$(basename "$rf")
      tf="$target_dir/$fname"

      if [ -d "$rf" ]; then
        # For subdirectories (e.g., skills/verify/)
        if [ ! -d "$tf" ]; then
          diffs+=" $sync_dir/$fname/(missing)"
          diff_count=$((diff_count + 1))
        else
          for sub_rf in "$rf"/*; do
            [ -f "$sub_rf" ] || continue
            sub_fname=$(basename "$sub_rf")
            sub_tf="$tf/$sub_fname"
            if [ ! -f "$sub_tf" ]; then
              diffs+=" $sync_dir/$fname/$sub_fname(missing)"
              diff_count=$((diff_count + 1))
            elif ! diff -q "$sub_rf" "$sub_tf" > /dev/null 2>&1; then
              diffs+=" $sync_dir/$fname/$sub_fname(differs)"
              diff_count=$((diff_count + 1))
            fi
          done
        fi
      elif [ -f "$rf" ]; then
        if [ ! -f "$tf" ]; then
          diffs+=" $sync_dir/$fname(missing)"
          diff_count=$((diff_count + 1))
        elif ! diff -q "$rf" "$tf" > /dev/null 2>&1; then
          diffs+=" $sync_dir/$fname(differs)"
          diff_count=$((diff_count + 1))
        fi
      fi
    done
  done

  # Check settings.json
  if $HAS_SETTINGS; then
    if [ ! -f "$target_claude/settings.json" ]; then
      diffs+=" settings.json(missing)"
      diff_count=$((diff_count + 1))
    elif ! diff -q "$ROOT_CLAUDE/settings.json" "$target_claude/settings.json" > /dev/null 2>&1; then
      diffs+=" settings.json(differs)"
      diff_count=$((diff_count + 1))
    fi
  fi

  if [ "$diff_count" -eq 0 ]; then
    result "PASS" "$id" "sync: $target_name" "all files match ROOT"
  else
    result "FAIL" "$id" "sync: $target_name" "${diff_count} diffs:${diffs}"
  fi
done

TOTAL=$((PASS + FAIL + SKIP))
echo "---"
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
