#!/bin/bash
# Run one Codex refine role in a fresh process.
set -euo pipefail

ROLE="${1:-}"
PROJECT_ROOT="${2:-}"
PROMPT_FILE="${3:-}"
OUTPUT_FILE="${4:-}"
CODEX_BIN="${CODEX_BIN:-codex}"

case "$ROLE" in
    audit|modify|evaluate) ;;
    *) echo "Usage: $0 <audit|modify|evaluate> <project-root> <prompt-file> [output-file]" >&2; exit 2 ;;
esac

[ -d "$PROJECT_ROOT/.git" ] || { echo "ERROR: not a git repository: $PROJECT_ROOT" >&2; exit 2; }
[ -f "$PROMPT_FILE" ] || { echo "ERROR: prompt file missing: $PROMPT_FILE" >&2; exit 2; }

if [ -n "$OUTPUT_FILE" ]; then
    case "$OUTPUT_FILE" in
        "$PROJECT_ROOT"/*)
            OUTPUT_REL=${OUTPUT_FILE#"$PROJECT_ROOT/"}
            git -C "$PROJECT_ROOT" check-ignore -q "$OUTPUT_REL" || {
                echo "ERROR: in-repo output must be gitignored: $OUTPUT_FILE" >&2
                exit 2
            }
            ;;
    esac
fi

BEFORE=$(git -C "$PROJECT_ROOT" status --porcelain=v1)
RUN_ROOT="$PROJECT_ROOT"
ISOLATED_ROOT=""
if [ "$ROLE" = "evaluate" ]; then
    ISOLATED_ROOT=$(mktemp -d)
    trap 'rm -r "$ISOLATED_ROOT"' EXIT
    RUN_ROOT="$ISOLATED_ROOT"
fi

ARGS=(exec --ephemeral -C "$RUN_ROOT")
[ "$ROLE" = "evaluate" ] && ARGS+=(--skip-git-repo-check)

if [ -f /.dockerenv ]; then
    ARGS+=(--dangerously-bypass-approvals-and-sandbox)
elif [ "$ROLE" = "modify" ]; then
    ARGS+=(--sandbox workspace-write)
else
    ARGS+=(--sandbox read-only)
fi

if [ -n "$OUTPUT_FILE" ]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    ARGS+=(-o "$OUTPUT_FILE")
fi

"$CODEX_BIN" "${ARGS[@]}" - < "$PROMPT_FILE"

if [ "$ROLE" != "modify" ]; then
    AFTER=$(git -C "$PROJECT_ROOT" status --porcelain=v1)
    if [ "$BEFORE" != "$AFTER" ]; then
        echo "ERROR: read-only role '$ROLE' changed the worktree." >&2
        exit 1
    fi
fi
