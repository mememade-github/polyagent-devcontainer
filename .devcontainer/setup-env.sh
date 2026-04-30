#!/bin/bash
# =============================================================================
# Polyagent DevContainer — Environment Setup (postCreateCommand)
# =============================================================================
set -e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

STEP_TOTAL=4
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
# 4. Codex CLI — project-local config symlink
# =============================================================================
# Codex auto-loads ~/.codex/config.toml only. If the project ships its own
# .codex/config.toml at the workspace root, link it so the project's sandbox/
# approval policy applies. Auth (auth.json) stays in ~/.codex/ unchanged.
step "Codex project config..."
WORKSPACE_CODEX_CONFIG="/workspaces/.codex/config.toml"
USER_CODEX_CONFIG="${HOME}/.codex/config.toml"
if [ -f "$WORKSPACE_CODEX_CONFIG" ]; then
    mkdir -p "${HOME}/.codex"
    if [ ! -e "$USER_CODEX_CONFIG" ]; then
        ln -sf "$WORKSPACE_CODEX_CONFIG" "$USER_CODEX_CONFIG"
        echo "      Linked: ~/.codex/config.toml -> $WORKSPACE_CODEX_CONFIG"
    elif [ -L "$USER_CODEX_CONFIG" ] && [ "$(readlink "$USER_CODEX_CONFIG")" = "$WORKSPACE_CODEX_CONFIG" ]; then
        echo "      Already linked"
    else
        echo "      User config exists — preserved (not overwritten)"
    fi
else
    echo "      No project-local .codex/config.toml — using user defaults"
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
