#!/bin/bash
# git-status.sh — Polyagent template single-repo status reporter.
#
# Minimal single-repo version. Reports current branch, dirty count, and
# unpushed commits. Multi-repo workspace versions extend this in their
# own scripts/git/git-status.sh.
#
# Usage:
#   bash scripts/git/git-status.sh         # full status
#   bash scripts/git/git-status.sh --brief # one-line per repo
set -e

BRIEF=0
[ "${1:-}" = "--brief" ] && BRIEF=1

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "ERROR: not a git repository (cwd: $(pwd))" >&2
    exit 1
}

cd "$REPO"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "(no commits)")
# Distinguish "no upstream" from "0 unpushed" (status SKILL §2: report no-upstream
# explicitly rather than treating it as zero).
if UPSTREAM=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null); then
    UNPUSHED=$(git log --oneline @{u}..HEAD 2>/dev/null | wc -l)
else
    UPSTREAM=""; UNPUSHED=0
fi

if [ "$BRIEF" -eq 1 ]; then
    UNPUSHED_DISP=$([ -n "$UPSTREAM" ] && echo "$UNPUSHED" || echo "no-upstream")
    printf "%-40s %s  %s  dirty=%s unpushed=%s\n" \
        "$(basename "$REPO")" "$BRANCH" "${LAST_COMMIT:0:50}" "$DIRTY" "$UNPUSHED_DISP"
else
    echo "Repository: $REPO"
    echo "Branch:     $BRANCH"
    echo "Last:       $LAST_COMMIT"
    echo "Dirty:      $DIRTY uncommitted file(s)"
    if [ -n "$UPSTREAM" ]; then
        echo "Unpushed:   $UNPUSHED commit(s) ahead of $UPSTREAM"
    else
        echo "Unpushed:   no upstream configured"
    fi
fi
