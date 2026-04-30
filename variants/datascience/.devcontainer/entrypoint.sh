#!/bin/bash
# =============================================================================
# Polyagent DevContainer — Container Entrypoint
# =============================================================================
# 컨테이너 시작 시 항상 실행됨.
# docker compose up -d, VS Code Reopen in Container 모두 이 스크립트를 통과.
# → MCP(Context7, Serena) 및 환경 설정이 항상 보장됨.
#
# VS Code는 추가로 postCreateCommand(setup-env.sh)를 실행하지만
# setup-env.sh는 idempotent이므로 2회 실행해도 안전.
# =============================================================================

# MCP 및 환경 설정 실행 (실패해도 컨테이너 시작 중단하지 않음)
if [ -x "/usr/local/bin/setup-env.sh" ]; then
    /usr/local/bin/setup-env.sh 2>&1 || echo "[entrypoint] WARN: setup-env.sh exited with error (non-fatal)"
fi

# 전달된 명령 실행 (기본값: sleep infinity)
exec "$@"
