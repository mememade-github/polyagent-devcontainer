#!/bin/bash
# =============================================================================
# Claude Code DevContainer — Environment Setup (postCreateCommand)
# =============================================================================
set -e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

STEP_TOTAL=3
STEP=0
step() { STEP=$((STEP + 1)); echo "[${STEP}/${STEP_TOTAL}] $1"; }

echo "=============================================="
echo "  Polyagent DevContainer Setup"
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
# 3. Claude CLI — idempotent 최신 버전 동기화
# =============================================================================
# 이미지 빌드 시점에 고정된 CLI 버전 드리프트를 방지하기 위해 컨테이너 시작
# 시마다 `claude update` 실행. 실패는 소프트 (컨테이너 시작 차단하지 않음).
# 건너뛰기: SKIP_CLAUDE_UPDATE=1 환경변수.
step "Claude CLI 버전..."
if ! command -v claude &>/dev/null; then
    echo "      WARN: claude CLI 미설치 — 업데이트 건너뜀"
elif [ "${SKIP_CLAUDE_UPDATE:-}" = "1" ]; then
    echo "      건너뜀 (SKIP_CLAUDE_UPDATE=1), 현재: $(claude --version 2>/dev/null)"
else
    BEFORE=$(claude --version 2>/dev/null | awk '{print $1}')
    claude update 2>&1 >/dev/null || true
    AFTER=$(claude --version 2>/dev/null | awk '{print $1}')
    if [ "$BEFORE" = "$AFTER" ]; then
        echo "      $AFTER (이미 최신)"
    else
        echo "      $BEFORE → $AFTER"
    fi
fi

# =============================================================================
# MCP: 플러그인 제공 (setup-env.sh에서 직접 등록하지 않음)
# =============================================================================
# Context7, Serena, Playwright MCP 서버는 Claude Code 플러그인이 자동 관리합니다.
# 플러그인: context7, serena, playwright (installed_plugins.json)
# 여기서 ~/.claude.json에 중복 등록하면 도구가 2× 나열되고 서버 프로세스가 이중 실행됩니다.
# 제거일: 2026-03-28, 사유: 플러그인-직접등록 이중 등록 해소

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
echo "MCP: 플러그인 관리 (context7, serena, playwright)"
echo ""
echo "시작:  claude"
echo ""
echo "프로젝트 언어/도구 추가 설치:"
echo "  Go:      sudo apt install -y golang"
echo "  Rust:    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
echo ""
