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

codex_healthy() {
    [ -x "$CODEX_REAL_BIN" ] && "$CODEX_REAL_BIN" --version >/dev/null 2>&1
}

# Reinstall @openai/codex cleanly. The real binary ships as a nested platform
# optional dep (@openai/codex-<os>-<arch>); npm's default in-place reinstall
# renames the existing package dir aside, which on 9p/overlay filesystems fails
# with ENOTEMPTY and leaves the platform binary uninstalled -- a half-install
# that only throws at run time. Removing the package dir (and any leftover
# .codex-* move-aside temp) first forces a clean install. Scope is exactly the
# codex package under the codex-only prefix: the same paths npm would replace.
codex_clean_install() {
    rm -rf "$CODEX_NPM_PREFIX/lib/node_modules/@openai/codex" \
           "$CODEX_NPM_PREFIX"/lib/node_modules/@openai/.codex-* 2>/dev/null || true
    npm install -g --prefix "$CODEX_NPM_PREFIX" @openai/codex@latest
}

codex_update_if_needed() {
    [ "${SKIP_CODEX_UPDATE:-}" = "1" ] && return 0
    command -v npm >/dev/null 2>&1 || return 0
    mkdir -p "$CODEX_NPM_PREFIX"

    current="$(codex_real_version)"
    latest="$(codex_latest_version)"
    # Offline guard: registry unreachable but a working binary exists -> do
    # nothing. MUST precede codex_clean_install and MUST test -x (not
    # codex_healthy): if offline AND half-installed, a clean install would
    # delete the old package and then fail (no registry), removing codex
    # entirely. Never delete while offline.
    if [ -z "$latest" ] && [ -x "$CODEX_REAL_BIN" ]; then
        return 0
    fi
    # Version drift OR half-install (unhealthy) -> clean reinstall.
    if [ -z "$latest" ] || [ "$current" != "$latest" ] || ! codex_healthy; then
        codex_clean_install
    fi
    # Functional gate: npm can exit 0 yet leave a half-install on 9p, so judge
    # by actually running the binary. This return propagates through
    # --update-only to setup-env's WARN + npm-log-tail path.
    codex_healthy
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
