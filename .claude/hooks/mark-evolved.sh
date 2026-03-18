#!/bin/bash
# Utility: Create evolution timestamp marker.
# Called after agent-evolver completes (or when evolution is skipped).
#
# Usage: .claude/hooks/mark-evolved.sh
# Creates .last-evolution marker that evolution-gate.sh checks.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
MARKER="$PROJECT_DIR/.claude/.last-evolution"

touch "$MARKER"
echo "Evolution marker created at $(date). Agent evolution recorded."
