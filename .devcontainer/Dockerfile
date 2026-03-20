# =============================================================================
# Claude DevContainer — Universal Base Template
# =============================================================================
# Claude Code CLI + Serena MCP + Shell 도구 + Agent System
# 프로젝트 언어/프레임워크는 사용자가 직접 설치 (Go, Rust, Java, etc.)
#
# Runtime 격리 (Claude Code 인프라 ≠ 프로젝트 코드):
#   Claude Code — 네이티브 바이너리 (~/.local/bin/claude, 자동 업데이트)
#   Node.js     — Context7 MCP 전용 (nvm, MCP_NODE_VERSION=22)
#   Python      — Serena MCP 전용 (시스템 python3, uv)
#   프로젝트용 Node.js는 PROJECT_NODE_VERSION으로 추가 설치 가능
#
# Variants:
#   claude-devcontainer       ← THIS (범용 베이스)
#   claude-devcontainer-data  ← Jupyter + Data Science (이 템플릿 + DS 패키지)
# =============================================================================
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

ARG PROJECT_NODE_VERSION=
ARG USERNAME=vscode
ARG DOCKER_GID=999

# UTF-8 인코딩 및 타임존
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    TZ=UTC \
    DEVCONTAINER=true

# =============================================================================
# Layer 1: 시스템 패키지 (root)
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales tzdata \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && ln -snf /usr/share/zoneinfo/UTC /etc/localtime \
    && echo "UTC" > /etc/timezone \
    && apt-get install -y --no-install-recommends \
    build-essential git git-lfs curl wget less procps sudo ca-certificates gnupg2 openssh-client \
    ripgrep fd-find fzf tree htop vim nano zsh tmux jq unzip zip man-db gh \
    # Python — Serena MCP 인프라용 (프로젝트 코드와 무관)
    python3 python3-pip python3-venv \
    docker.io \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    # Node.js LTS — Context7 MCP 인프라용 (시스템 패키지, Claude 네이티브에서 직접 접근)
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @devcontainers/cli \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && (groupmod -g ${DOCKER_GID} docker 2>/dev/null || groupadd -g ${DOCKER_GID} docker 2>/dev/null || true) \
    && usermod -aG docker ${USERNAME} \
    # Docker Compose v2 plugin (pinned — bump periodically)
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -SL "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Python LSP (Serena 의존성)
RUN pip3 install --no-cache-dir --break-system-packages jedi

# =============================================================================
# Layer 2: 사용자 설정 (root → vscode)
# =============================================================================
RUN echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /commandhistory /workspaces \
    && touch /commandhistory/.bash_history \
    && chown -R ${USERNAME}:${USERNAME} /commandhistory /workspaces

USER ${USERNAME}

# PATH: Claude Code + uv가 항상 해석되도록 정적 경로 포함
ENV HOME=/home/${USERNAME} \
    NVM_DIR=/home/${USERNAME}/.nvm \
    PATH=/home/${USERNAME}/.local/bin:${PATH}

# =============================================================================
# Layer 3: Claude Code CLI — Native Installer
# 네이티브 바이너리 설치. Node.js 불필요. 자동 업데이트.
# OOM 방지: 임시 디렉토리에서 실행 (Docker root / 에서 OOM 이슈)
# =============================================================================
RUN mkdir /tmp/claude-install && cd /tmp/claude-install \
    && curl -fsSL https://claude.ai/install.sh | bash \
    && rm -rf /tmp/claude-install \
    && cd ~ \
    && claude --version

# =============================================================================
# Layer 4: Node.js — Project (optional)
# 시스템 Node.js(Layer 1)와 별도로, 프로젝트 전용 버전이 필요할 때만 nvm 설치.
# 미설정 시 시스템 Node.js(LTS)만 사용.
# =============================================================================
RUN if [ -n "${PROJECT_NODE_VERSION}" ]; then \
        mkdir -p ${NVM_DIR} \
        && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
        && . ${NVM_DIR}/nvm.sh \
        && nvm install ${PROJECT_NODE_VERSION} \
        && nvm alias project-node ${PROJECT_NODE_VERSION} \
        && nvm alias default ${PROJECT_NODE_VERSION}; \
    fi

# =============================================================================
# Layer 5: Serena MCP — 코드 인텔리전스
# Node.js(시스템)가 Context7 MCP 인프라이듯, Python은 Serena MCP용 인프라.
# =============================================================================
# uv (Python 패키지 관리 — pinned version for reproducibility)
RUN curl -LsSf https://astral.sh/uv/0.6.0/install.sh | sh

# Serena 설치
RUN mkdir -p ${HOME}/work \
    && cd ${HOME}/work \
    && git clone https://github.com/oraios/serena.git \
    && cd serena \
    && ${HOME}/.local/bin/uv sync

# Serena 설정
RUN mkdir -p ${HOME}/.serena \
    && if [ -f "${HOME}/work/serena/src/serena/resources/serena_config.template.yml" ]; then \
        cp ${HOME}/work/serena/src/serena/resources/serena_config.template.yml ${HOME}/.serena/serena_config.yml; \
    else \
        echo -e "web_dashboard: false\nweb_dashboard_open_on_launch: false" > ${HOME}/.serena/serena_config.yml; \
    fi \
    && sed -i 's/web_dashboard: [Tt]rue/web_dashboard: false/g' ${HOME}/.serena/serena_config.yml \
    && sed -i 's/web_dashboard_open_on_launch: [Tt]rue/web_dashboard_open_on_launch: false/g' ${HOME}/.serena/serena_config.yml

# =============================================================================
# Layer 6: 사용자 설정 (shell, editor, git)
# =============================================================================
RUN mkdir -p ${HOME}/.claude ${HOME}/.config/nano

# .bashrc
RUN echo 'export LANG=en_US.UTF-8' >> ${HOME}/.bashrc \
    && echo 'export LC_ALL=en_US.UTF-8' >> ${HOME}/.bashrc \
    && echo 'export HISTFILE=/commandhistory/.bash_history' >> ${HOME}/.bashrc \
    && echo 'export HISTSIZE=10000' >> ${HOME}/.bashrc \
    && echo 'export HISTFILESIZE=20000' >> ${HOME}/.bashrc \
    && echo 'export NVM_DIR="${HOME}/.nvm"' >> ${HOME}/.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> ${HOME}/.bashrc \
    && echo '# Activate project Node.js (nvm 존재 시에만, reads .nvmrc if present)' >> ${HOME}/.bashrc \
    && echo 'if command -v nvm &>/dev/null; then if [ -f ".nvmrc" ]; then nvm use 2>/dev/null || true; else nvm use project-node 2>/dev/null || true; fi; fi' >> ${HOME}/.bashrc \
    && echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> ${HOME}/.bashrc \
    && echo 'alias ll="ls -alF"' >> ${HOME}/.bashrc \
    && echo 'alias fd="fdfind"' >> ${HOME}/.bashrc

# Vim
RUN echo 'set encoding=utf-8' >> ${HOME}/.vimrc \
    && echo 'set number' >> ${HOME}/.vimrc \
    && echo 'set tabstop=4' >> ${HOME}/.vimrc \
    && echo 'set shiftwidth=4' >> ${HOME}/.vimrc \
    && echo 'set expandtab' >> ${HOME}/.vimrc

# Nano
RUN echo 'set tabsize 4' >> ${HOME}/.nanorc \
    && echo 'set tabstospaces' >> ${HOME}/.nanorc \
    && echo 'set linenumbers' >> ${HOME}/.nanorc

# Git (UTF-8)
RUN git config --global core.quotepath false \
    && git config --global i18n.commitEncoding utf-8 \
    && git config --global i18n.logOutputEncoding utf-8

# =============================================================================
# Setup scripts + Entrypoint
# =============================================================================
USER root
COPY setup-env.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/setup-env.sh /usr/local/bin/entrypoint.sh

USER ${USERNAME}
WORKDIR /workspaces

# ENTRYPOINT: 컨테이너 시작 시 항상 실행 (docker compose up -d 포함)
# → setup-env.sh 자동 실행 → MCP 항상 설정됨
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
