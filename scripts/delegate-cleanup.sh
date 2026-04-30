#!/usr/bin/env bash
# Show or remove stale delegate worktrees and run records.
#
# Usage:
#   delegate-cleanup.sh                # show only (default — conservative)
#   delegate-cleanup.sh --apply        # git worktree remove + delete records
#   delegate-cleanup.sh --archive      # rename to .polyagent/.stale-<date>/ instead
#
# Stale = META.status != "running" AND mtime > 7 days.
# Active runs (status=running) are listed but never auto-cleaned.

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
RUNS="$ROOT/.polyagent/runs"
WTS="$ROOT/.polyagent/worktrees"
[[ -d "$RUNS" ]] || { echo "no delegate runs"; exit 0; }

MODE=${1:-show}
case "$MODE" in show|--apply|--archive) ;;
  *) echo "Usage: $0 [--apply|--archive]" >&2; exit 64 ;;
esac

# active list
echo "=== Active runs (status=running, never auto-cleaned) ==="
ACT=0
for m in "$RUNS"/*.json; do
  [[ -f "$m" ]] || continue
  st=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status',''))" "$m")
  if [[ "$st" == "running" ]]; then
    sl=$(basename "$m" .json)
    echo "  $sl"
    ACT=$((ACT+1))
  fi
done
[[ $ACT -eq 0 ]] && echo "  (none)"

# stale candidates
echo ""
echo "=== Stale candidates (status!=running AND mtime > 7d) ==="
STALE=()
while IFS= read -r m; do
  [[ -f "$m" ]] || continue
  st=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status',''))" "$m")
  [[ "$st" == "running" ]] && continue
  STALE+=("$m")
  echo "  $(basename "$m" .json)  status=$st"
done < <(find "$RUNS" -name "*.json" -type f -mtime +7 2>/dev/null)
[[ ${#STALE[@]} -eq 0 ]] && echo "  (none)" && exit 0

echo ""
case "$MODE" in
  show)
    echo "Re-run with --apply to remove, or --archive to move to .polyagent/.stale-<date>/"
    ;;
  --apply)
    git worktree prune
    for m in "${STALE[@]}"; do
      sl=$(basename "$m" .json)
      git worktree remove --force "$WTS/$sl" 2>/dev/null || rm -rf "$WTS/$sl"
      rm -f "$m" "${m%.json}.out" "${m%.json}.err"
      echo "  removed: $sl"
    done
    ;;
  --archive)
    DATE=$(date +%Y%m%d)
    ARCH="$ROOT/.polyagent/.stale-$DATE"
    mkdir -p "$ARCH/runs" "$ARCH/worktrees"
    for m in "${STALE[@]}"; do
      sl=$(basename "$m" .json)
      mv "$m" "$ARCH/runs/" 2>/dev/null || true
      [[ -f "${m%.json}.out" ]] && mv "${m%.json}.out" "$ARCH/runs/"
      [[ -f "${m%.json}.err" ]] && mv "${m%.json}.err" "$ARCH/runs/"
      [[ -d "$WTS/$sl" ]] && mv "$WTS/$sl" "$ARCH/worktrees/"
      echo "  archived: $sl -> $ARCH"
    done
    git worktree prune
    ;;
esac
