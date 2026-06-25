#!/bin/bash
# =============================================================================
# Polyagent DevContainer — Environment Setup (postCreateCommand)
# =============================================================================
set -e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

STEP_TOTAL=5
STEP=0
step() { STEP=$((STEP + 1)); echo "[${STEP}/${STEP_TOTAL}] $1"; }

echo "=============================================="
echo "  Polyagent DevContainer Setup"
echo "=============================================="
echo ""

# =============================================================================
# 1. Docker socket + workspace permissions
# =============================================================================
step "Setting permissions..."

if [ -S /var/run/docker.sock ]; then
    sudo chown root:docker /var/run/docker.sock 2>/dev/null || true
fi

WS="/workspaces"
find "$WS" -maxdepth 3 -name ".git" -type d 2>/dev/null | while read gitdir; do
    repo=$(dirname "$gitdir")
    git -C "$repo" config core.filemode false 2>/dev/null || true
done

# 9p/drvfs: prevent dubious-ownership warnings on root:root mounts
git config --global safe.directory '*' 2>/dev/null || true

# Command history
if [ -d /commandhistory ]; then
    export HISTFILE=/commandhistory/.bash_history
    touch "$HISTFILE" 2>/dev/null || true
fi
echo "      Done"

# =============================================================================
# 2. SSH (optional)
# =============================================================================
step "SSH setup..."
SSH_DIR="${HOME}/.ssh"
if [ -d "$SSH_DIR" ]; then
    chmod 700 "$SSH_DIR" 2>/dev/null || true
    find "$SSH_DIR" -type f -name "*.pub" -exec chmod 644 {} \; 2>/dev/null || true
    find "$SSH_DIR" -type f -name "known_hosts*" -exec chmod 644 {} \; 2>/dev/null || true
    find "$SSH_DIR" -type f ! -name "*.pub" ! -name "known_hosts*" ! -name "config" -exec chmod 600 {} \; 2>/dev/null || true
    [ -f "$SSH_DIR/config" ] && chmod 644 "$SSH_DIR/config" 2>/dev/null || true
    echo "      SSH keys found"
else
    echo "      No SSH (optional)"
fi

# =============================================================================
# 3. Claude CLI — idempotent latest-version sync
# =============================================================================
# Run `claude update` on every container start to prevent CLI version drift
# from the image-build snapshot. Failure is soft (does not block startup).
# Skip with SKIP_CLAUDE_UPDATE=1.
step "Claude CLI version..."
if ! command -v claude &>/dev/null; then
    echo "      WARN: claude CLI not installed — skipping update"
elif [ "${SKIP_CLAUDE_UPDATE:-}" = "1" ]; then
    echo "      Skipped (SKIP_CLAUDE_UPDATE=1), current: $(claude --version 2>/dev/null)"
else
    BEFORE=$(claude --version 2>/dev/null | awk '{print $1}')
    claude update 2>&1 >/dev/null || true
    AFTER=$(claude --version 2>/dev/null | awk '{print $1}')
    if [ "$BEFORE" = "$AFTER" ]; then
        echo "      $AFTER (already latest)"
    else
        echo "      $BEFORE -> $AFTER"
    fi
fi

# =============================================================================
# 4. Codex CLI — idempotent latest-version sync
# =============================================================================
# Parity with Claude (step 3): keep the Codex CLI current on each container
# start instead of frozen at the image-build snapshot. Failure is soft (does
# not block startup). Skip with SKIP_CODEX_UPDATE=1.
#
# Do NOT use `codex update`: its built-in updater runs `npm install -g
# @openai/codex` against the default global prefix, which the unprivileged
# vscode user cannot write. The Dockerfile installs Codex to ~/.npm-global, so
# mirror that install command here.
step "Codex CLI version..."
CODEX_NPM_PREFIX="${HOME}/.npm-global"
CODEX_REAL_BIN="${CODEX_NPM_PREFIX}/bin/codex"
CODEX_LAUNCHER="/usr/local/bin/codex-launcher"
CODEX_LOCK="${CODEX_NPM_PREFIX}/.codex-update.lock"

install_codex_launcher() {
    if [ ! -x "$CODEX_LAUNCHER" ]; then
        echo "      WARN: Codex launcher preflight missing; rebuild container to close startup race"
        return 0
    fi
    mkdir -p "${HOME}/.local/bin"
    ln -sf "$CODEX_LAUNCHER" "${HOME}/.local/bin/codex" 2>/dev/null || true
    if command -v sudo >/dev/null 2>&1; then
        sudo ln -sf "$CODEX_LAUNCHER" /usr/local/bin/codex 2>/dev/null || true
    else
        ln -sf "$CODEX_LAUNCHER" /usr/local/bin/codex 2>/dev/null || true
    fi
}

codex_version() {
    [ -x "$CODEX_REAL_BIN" ] || return 0
    "$CODEX_REAL_BIN" --version 2>/dev/null | awk '{print $2}' || true
}

codex_latest_version() {
    command -v npm >/dev/null 2>&1 || return 0
    npm view @openai/codex version 2>/dev/null || true
}

codex_update_if_needed() {
    command -v npm >/dev/null 2>&1 || return 0
    mkdir -p "$CODEX_NPM_PREFIX"

    current="$(codex_version)"
    latest="$(codex_latest_version)"
    if [ -z "$latest" ] && [ -x "$CODEX_REAL_BIN" ]; then
        return 0
    fi
    if [ -z "$latest" ] || [ "$current" != "$latest" ]; then
        npm install -g --prefix "$CODEX_NPM_PREFIX" @openai/codex@latest
    fi
}

codex_update_locked() {
    mkdir -p "$CODEX_NPM_PREFIX"
    if command -v flock >/dev/null 2>&1; then
        ( flock 9; codex_update_if_needed ) 9>"$CODEX_LOCK"
    else
        codex_update_if_needed
    fi
}

install_codex_launcher

if [ ! -x "$CODEX_REAL_BIN" ] && ! command -v npm >/dev/null 2>&1; then
    echo "      WARN: codex CLI not installed — skipping update"
elif [ "${SKIP_CODEX_UPDATE:-}" = "1" ]; then
    echo "      Skipped (SKIP_CODEX_UPDATE=1), current: $(codex_version)"
else
    BEFORE=$(codex_version)
    CODEX_UPDATE_LOG=$(mktemp)
    if codex_update_locked >"$CODEX_UPDATE_LOG" 2>&1; then
        AFTER=$(codex_version)
        if [ "$BEFORE" = "$AFTER" ]; then
            echo "      $AFTER (already latest)"
        else
            echo "      $BEFORE → $AFTER"
        fi
    else
        echo "      WARN: Codex update failed; continuing with ${BEFORE:-unknown}"
        tail -20 "$CODEX_UPDATE_LOG" | sed 's/^/      npm: /'
    fi
    rm -f "$CODEX_UPDATE_LOG"
fi

# =============================================================================
# 5. Codex CLI — project-local config validation
# =============================================================================
# Current Codex loads a trusted project's .codex/config.toml directly. Never
# copy project policy into ~/.codex/config.toml: that user file is persistent,
# higher-scope state and would become stale when the project template changes.
# Authentication and explicit personal overrides remain in ~/.codex/.
step "Codex project config..."
WORKSPACE_CODEX_CONFIG="/workspaces/.codex/config.toml"
USER_CODEX_CONFIG="${HOME}/.codex/config.toml"
if [ -f "$WORKSPACE_CODEX_CONFIG" ]; then
    if grep -q '^ask_for_approval[[:space:]]*=' "$WORKSPACE_CODEX_CONFIG"; then
        echo "      WARN: project config uses obsolete ask_for_approval; use approval_policy"
    else
        echo "      Project config detected — Codex loads it after project trust"
    fi
else
    echo "      WARN: no project-local .codex/config.toml"
fi

if [ -L "$USER_CODEX_CONFIG" ]; then
    if [ "$(readlink "$USER_CODEX_CONFIG")" = "$WORKSPACE_CODEX_CONFIG" ]; then
        rm -f "$USER_CODEX_CONFIG"
        echo "      Removed legacy ~/.codex/config.toml symlink to project config"
    else
        echo "      WARN: ~/.codex/config.toml is a symlink; replace it with explicit user config"
    fi
elif [ -f "$USER_CODEX_CONFIG" ] && grep -q '^ask_for_approval[[:space:]]*=' "$USER_CODEX_CONFIG"; then
    echo "      WARN: existing user config uses obsolete ask_for_approval; use approval_policy"
fi

# =============================================================================
# Project-specific setup (separate file)
# Custom per-project setup goes in setup-env.project.sh.
# =============================================================================
PROJECT_SETUP="/usr/local/bin/setup-env.project.sh"
if [ -f "$PROJECT_SETUP" ]; then
    echo ""
    echo "--- Project Setup ---"
    source "$PROJECT_SETUP"
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Start:  claude"
echo ""
echo "Install additional project tools:"
echo "  Go:      sudo apt install -y golang"
echo "  Rust:    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
echo ""
