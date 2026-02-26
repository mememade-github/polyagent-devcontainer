#!/bin/bash
# Utility: Clear pending-review marker after code review is complete.
# Called by the AI after code-reviewer agent finishes its review.
#
# Usage: .claude/hooks/review-complete.sh

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Clear pending review marker
rm -f "$PROJECT_DIR/.claude/.pending-review"

echo "Code review marker cleared. Commits are now unblocked (pending verification)."
