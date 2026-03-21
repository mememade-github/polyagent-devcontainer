#!/bin/bash
# =============================================================================
# Claude DevContainer — Environment Setup (postCreateCommand)
# =============================================================================
set -e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

STEP_TOTAL=4
STEP=0
step() { STEP=$((STEP + 1)); echo "[${STEP}/${STEP_TOTAL}] $1"; }

echo "=============================================="
echo "  Claude DevContainer Setup"
echo "=============================================="
echo ""

# =============================================================================
# 1. Docker 소켓 + Workspace 권한
# =============================================================================
step "권한 설정..."

if [ -S /var/run/docker.sock ]; then
    sudo chown root:docker /var/run/docker.sock 2>/dev/null || true
fi

WS="/workspaces"
find "$WS" -maxdepth 3 -name ".git" -type d 2>/dev/null | while read gitdir; do
    repo=$(dirname "$gitdir")
    git -C "$repo" config core.filemode false 2>/dev/null || true
done

# 9p/drvfs: root:root 소유 마운트에서 dubious ownership 방지
git config --global safe.directory '*' 2>/dev/null || true

# 명령 히스토리
if [ -d /commandhistory ]; then
    export HISTFILE=/commandhistory/.bash_history
    touch "$HISTFILE" 2>/dev/null || true
fi
echo "      완료"

# =============================================================================
# 2. SSH (선택사항)
# =============================================================================
step "SSH 설정..."
SSH_DIR="${HOME}/.ssh"
if [ -d "$SSH_DIR" ]; then
    chmod 700 "$SSH_DIR" 2>/dev/null || true
    find "$SSH_DIR" -type f -name "*.pub" -exec chmod 644 {} \; 2>/dev/null || true
    find "$SSH_DIR" -type f -name "known_hosts*" -exec chmod 644 {} \; 2>/dev/null || true
    find "$SSH_DIR" -type f ! -name "*.pub" ! -name "known_hosts*" ! -name "config" -exec chmod 600 {} \; 2>/dev/null || true
    [ -f "$SSH_DIR/config" ] && chmod 644 "$SSH_DIR/config" 2>/dev/null || true
    echo "      SSH 키 발견됨"
else
    echo "      SSH 없음 (선택사항)"
fi

# =============================================================================
# 3. MCP: Context7
# =============================================================================
step "MCP: Context7..."
export HOME=${HOME:-/home/vscode}
export NVM_DIR=${NVM_DIR:-${HOME}/.nvm}
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

CLAUDE_CONFIG="${HOME}/.claude.json"

if ! command -v jq &>/dev/null; then
    echo "      WARN: jq 미설치 — MCP 설정 건너뜀"
else
    if [ ! -f "$CLAUDE_CONFIG" ]; then
        echo '{"mcpServers":{}}' > "$CLAUDE_CONFIG"
    fi

    # Context7 (라이브러리 문서 검색) — npx 필요
    if command -v npx &>/dev/null; then
        _tmp=$(mktemp)
        jq '.mcpServers.context7 = {
          "type": "stdio",
          "command": "npx",
          "args": ["-y", "@upstash/context7-mcp@latest"],
          "env": {}
        }' "$CLAUDE_CONFIG" > "$_tmp" && mv "$_tmp" "$CLAUDE_CONFIG"
        echo "      context7: OK"
    else
        echo "      WARN: npx 미설치 — Context7 건너뜀"
    fi
fi

# =============================================================================
# 4. MCP: Serena (코드 인텔리전스 — Dockerfile에서 사전 설치됨)
# =============================================================================
step "MCP: Serena..."
SERENA_DIR="${HOME}/work/serena"
UV_PATH=$(command -v uv 2>/dev/null || echo "${HOME}/.local/bin/uv")

if ! command -v jq &>/dev/null; then
    echo "      WARN: jq 미설치 — 건너뜀"
elif [ ! -d "$SERENA_DIR" ]; then
    echo "      WARN: Serena 미설치 ($SERENA_DIR 없음)"
elif [ ! -x "$UV_PATH" ]; then
    echo "      WARN: uv 미설치"
else
    _tmp=$(mktemp)
    jq --arg uv "$UV_PATH" --arg dir "$SERENA_DIR" '.mcpServers.serena = {
      "type": "stdio",
      "command": $uv,
      "args": ["run", "--directory", $dir, "serena-mcp-server", "--context", "claude-code", "--project-from-cwd"],  # [SPECIALIZED] context name
      "env": {}
    }' "$CLAUDE_CONFIG" > "$_tmp" && mv "$_tmp" "$CLAUDE_CONFIG"
    echo "      serena: OK"
fi

# =============================================================================
# Project-specific setup (파일 분리)
# 프로젝트별 커스텀 설정은 setup-env.project.sh에 작성.
# =============================================================================
PROJECT_SETUP="/usr/local/bin/setup-env.project.sh"
if [ -f "$PROJECT_SETUP" ]; then
    echo ""
    echo "--- Project Setup ---"
    source "$PROJECT_SETUP"
fi

# =============================================================================
# 완료
# =============================================================================
echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "MCP: $(jq -r '.mcpServers | keys | join(", ")' "$CLAUDE_CONFIG" 2>/dev/null || echo "unknown")"
echo ""
echo "시작:  claude"
echo ""
echo "프로젝트 언어/도구 추가 설치:"
echo "  Go:      sudo apt install -y golang"
echo "  Rust:    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
echo ""
