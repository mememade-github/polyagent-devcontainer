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

git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    { echo "ERROR: not a git repository: $PROJECT_ROOT" >&2; exit 2; }
PROJECT_ROOT=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)
[ -f "$PROMPT_FILE" ] || { echo "ERROR: prompt file missing: $PROMPT_FILE" >&2; exit 2; }

OUTPUT_REL=""
if [ -n "$OUTPUT_FILE" ]; then
    OUTPUT_FILE=$(realpath -m -- "$OUTPUT_FILE")
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

IGNORED_FINGERPRINT_EXCLUDES=(
    ':(exclude).codex/state/**'
    ':(exclude).claude/.last-verification.*'
    ':(exclude).claude/.refinement-active'
    ':(exclude).claude/.refine-*'
    ':(exclude).claude/agent-memory/refinement/**'
    ':(exclude)node_modules/**'
    ':(exclude).pnpm-store/**'
    ':(exclude).venv/**'
    ':(exclude)venv/**'
    ':(exclude)dist/**'
    ':(exclude)build/**'
    ':(exclude)target/**'
    ':(exclude)coverage/**'
    ':(exclude)__pycache__/**'
    ':(exclude).pytest_cache/**'
    ':(exclude).ruff_cache/**'
    ':(exclude).mypy_cache/**'
)

tree_fingerprint() {
    local root=$1 excluded=$2
    (
        cd "$root"
        {
            git ls-files -z --cached --others --exclude-standard
            git ls-files -z --others -i --exclude-standard -- "${IGNORED_FINGERPRINT_EXCLUDES[@]}"
        } |
            LC_ALL=C sort -zu |
            while IFS= read -r -d '' rel; do
                [ -n "$rel" ] || continue
                [ -n "$excluded" ] && [ "$rel" = "$excluded" ] && continue
                if [ ! -e "$rel" ] && [ ! -L "$rel" ]; then
                    printf '%s\0MISSING\0' "$rel"
                    continue
                fi
                printf '%s\0%s\0' "$rel" "$(stat -c '%F:%f:%u:%g:%s:%t:%T' -- "$rel")"
                if [ -L "$rel" ]; then
                    readlink -z -- "$rel"
                elif [ -f "$rel" ]; then
                    sha256sum < "$rel" | cut -d ' ' -f 1 | tr '\n' '\0'
                fi
            done
    ) | sha256sum | cut -d ' ' -f 1
}

repository_fingerprint() {
    local head_ref head_oid index_entries index_flags tree
    head_ref=$(git -C "$PROJECT_ROOT" symbolic-ref -q HEAD || printf '%s' DETACHED)
    head_oid=$(git -C "$PROJECT_ROOT" rev-parse --verify HEAD 2>/dev/null || printf '%s' UNBORN)
    index_entries=$(git -C "$PROJECT_ROOT" ls-files --stage -z | sha256sum | cut -d ' ' -f 1)
    index_flags=$(
        {
            git -C "$PROJECT_ROOT" ls-files -v -z
            git -C "$PROJECT_ROOT" ls-files -f -z
        } | sha256sum | cut -d ' ' -f 1
    )
    tree=$(tree_fingerprint "$PROJECT_ROOT" "$OUTPUT_REL")
    printf '%s\n%s\n%s\n%s\n%s\n' "$head_ref" "$head_oid" "$index_entries" "$index_flags" "$tree"
}

if [ -n "$OUTPUT_FILE" ]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    [ "$ROLE" != "evaluate" ] || : > "$OUTPUT_FILE"
fi

BEFORE=$(repository_fingerprint)
RUN_ROOT="$PROJECT_ROOT"
ISOLATED_ROOT=""
FINAL_OUTPUT=""
cleanup() {
    [ -z "$ISOLATED_ROOT" ] || rm -r "$ISOLATED_ROOT"
    [ -z "$FINAL_OUTPUT" ] || rm -f "$FINAL_OUTPUT"
}
trap cleanup EXIT

if [ "$ROLE" = "evaluate" ]; then
    ISOLATED_ROOT=$(mktemp -d)
    RUN_ROOT="$ISOLATED_ROOT"
fi

ARGS=(exec --ephemeral --ignore-user-config --disable hooks -C "$RUN_ROOT")
[ "$ROLE" = "evaluate" ] && ARGS+=(--skip-git-repo-check)

if [ -f /.dockerenv ]; then
    ARGS+=(--dangerously-bypass-approvals-and-sandbox)
elif [ "$ROLE" = "modify" ]; then
    ARGS+=(--sandbox workspace-write)
else
    ARGS+=(--sandbox read-only)
fi

if [ -n "$OUTPUT_FILE" ]; then
    if [ "$ROLE" = "evaluate" ]; then
        FINAL_OUTPUT=$(mktemp)
        ARGS+=(-o "$FINAL_OUTPUT")
    else
        ARGS+=(-o "$OUTPUT_FILE")
    fi
fi

CHILD_STATUS=0
if [ "$ROLE" = "evaluate" ] && [ -n "$OUTPUT_FILE" ]; then
    "$CODEX_BIN" "${ARGS[@]}" - < "$PROMPT_FILE" >/dev/null || CHILD_STATUS=$?
else
    "$CODEX_BIN" "${ARGS[@]}" - < "$PROMPT_FILE" || CHILD_STATUS=$?
fi

if [ "$ROLE" != "modify" ]; then
    AFTER=$(repository_fingerprint)
    if [ "$BEFORE" != "$AFTER" ]; then
        echo "ERROR: read-only role '$ROLE' changed HEAD, the index, or the guarded project tree." >&2
        exit 1
    fi
fi

[ "$CHILD_STATUS" -eq 0 ] || exit "$CHILD_STATUS"

if [ "$ROLE" = "evaluate" ] && [ -n "$OUTPUT_FILE" ]; then
    [ -s "$OUTPUT_FILE" ] || {
        echo "ERROR: evaluator did not write a full report: $OUTPUT_FILE" >&2
        exit 1
    }
    [ -s "$FINAL_OUTPUT" ] || {
        echo "ERROR: evaluator did not return a final score." >&2
        exit 1
    }
    cat "$FINAL_OUTPUT"
fi
