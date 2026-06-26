#!/bin/bash
set -e

CODEX_NPM_PREFIX="${CODEX_NPM_PREFIX:-${HOME}/.npm-global}"
CODEX_REAL_BIN="${CODEX_REAL_BIN:-${CODEX_NPM_PREFIX}/bin/codex}"
CODEX_LOCK="${CODEX_LOCK:-${CODEX_NPM_PREFIX}/.codex-update.lock}"

codex_real_version() {
    [ -x "$CODEX_REAL_BIN" ] || return 0
    "$CODEX_REAL_BIN" --version 2>/dev/null | awk '{print $2}' || true
}

codex_latest_version() {
    command -v npm >/dev/null 2>&1 || return 0
    npm view @openai/codex version 2>/dev/null || true
}

codex_update_if_needed() {
    [ "${SKIP_CODEX_UPDATE:-}" = "1" ] && return 0
    command -v npm >/dev/null 2>&1 || return 0
    mkdir -p "$CODEX_NPM_PREFIX"

    current="$(codex_real_version)"
    latest="$(codex_latest_version)"
    if [ -z "$latest" ] && [ -x "$CODEX_REAL_BIN" ]; then
        return 0
    fi
    if [ -z "$latest" ] || [ "$current" != "$latest" ]; then
        npm install -g --prefix "$CODEX_NPM_PREFIX" @openai/codex@latest
    fi
}

codex_update_locked() {
    if command -v flock >/dev/null 2>&1; then
        ( flock 9; codex_update_if_needed ) 9>"$CODEX_LOCK"
    else
        codex_update_if_needed
    fi
}

mkdir -p "$CODEX_NPM_PREFIX"
if [ "${1:-}" = "--update-only" ]; then
    codex_update_locked
    exit $?
fi

codex_update_locked >/dev/null 2>&1 || true

if [ ! -x "$CODEX_REAL_BIN" ]; then
    echo "codex launcher: missing executable: $CODEX_REAL_BIN" >&2
    exit 127
fi

exec "$CODEX_REAL_BIN" "$@"
