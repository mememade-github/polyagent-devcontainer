#!/bin/bash
# Template verification script — run inside container
echo "=============================================="
echo "  Template Full Verification"
echo "=============================================="
echo ""

PASS=0
FAIL=0
record() { [ "$1" = "PASS" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1)); echo "$1: $2"; }

# --- PHASE 1: Runtime ---
echo "=== Phase 1: Runtime ==="
claude --version > /dev/null 2>&1 && record PASS "claude CLI" || record FAIL "claude CLI"
(command -v codex >/dev/null 2>&1 || [ -x /home/vscode/.npm-global/bin/codex ]) \
    && (codex --version > /dev/null 2>&1 || /home/vscode/.npm-global/bin/codex --version > /dev/null 2>&1) \
    && record PASS "codex CLI" || record FAIL "codex CLI"
node --version > /dev/null 2>&1 && record PASS "node ($(node --version))" || record FAIL "node"
/home/vscode/.local/bin/uv --version > /dev/null 2>&1 && record PASS "uv" || record FAIL "uv"
python3 --version > /dev/null 2>&1 && record PASS "python3 ($(python3 --version 2>&1))" || record FAIL "python3"

# --- PHASE 1b: MCP ---
# MCP 플러그인(context7, serena)은 setup-env.sh 실행 + Claude Code 플러그인 동기화 후 등록됨.
# Image-only test에서는 미등록 상태가 정상 — 이때는 SKIP. 등록 여부는 ~/.claude.json 내용으로 판정.
echo ""
echo "=== Phase 1b: MCP ==="
[ -x "/home/vscode/.local/bin/uv" ] && record PASS "Serena uv path (/home/vscode/.local/bin/uv)" || record FAIL "Serena uv path"
[ -d "/home/vscode/work/serena" ] && record PASS "Serena dir (/home/vscode/work/serena)" || record FAIL "Serena dir"
if [ -f /home/vscode/.claude.json ] && grep -qE '"context7"|"serena"' /home/vscode/.claude.json 2>/dev/null; then
    ctx=$(grep -c '"context7"' /home/vscode/.claude.json 2>/dev/null | tr -d '[:space:]')
    ser=$(grep -c '"serena"' /home/vscode/.claude.json 2>/dev/null | tr -d '[:space:]')
    [ "${ctx:-0}" -gt 0 ] && record PASS "MCP context7" || record FAIL "MCP context7"
    [ "${ser:-0}" -gt 0 ] && record PASS "MCP serena" || record FAIL "MCP serena"
else
    echo "SKIP: MCP context7/serena (plugins not yet registered — run setup-env.sh + claude first)"
fi

# --- PHASE 2: Config files ---
echo ""
echo "=== Phase 2: Config Files ==="
[ -f /workspaces/.claude/settings.json ] && record PASS "settings.json exists" || record FAIL "settings.json"
grep -q '"SessionStart"' /workspaces/.claude/settings.json 2>/dev/null && record PASS "SessionStart hook registered" || record FAIL "SessionStart hook"
grep -q '"Stop"' /workspaces/.claude/settings.json 2>/dev/null && record PASS "Stop hook registered" || record FAIL "Stop hook"
[ -f /workspaces/.codex/config.toml ] && record PASS ".codex/config.toml exists" || record FAIL ".codex/config.toml"
[ -f /workspaces/.codex/hooks.json ] && record PASS ".codex/hooks.json exists" || record FAIL ".codex/hooks.json"
[ -f /workspaces/AGENTS.md ] && record PASS "AGENTS.md exists" || record FAIL "AGENTS.md"

# --- PHASE 2a: Karpathy alignment (load-bearing import 체인) ---
echo ""
echo "=== Phase 2a: Karpathy Alignment ==="
grep -q "behavioral-core" /workspaces/CLAUDE.md 2>/dev/null && record PASS "CLAUDE.md → behavioral-core import" || record FAIL "CLAUDE.md → behavioral-core import"
grep -q "behavioral-core" /workspaces/AGENTS.md 2>/dev/null && record PASS "AGENTS.md → behavioral-core import" || record FAIL "AGENTS.md → behavioral-core import"
[ -f /workspaces/.claude/rules/behavioral-core.md ] && record PASS ".claude/rules/behavioral-core.md exists" || record FAIL ".claude/rules/behavioral-core.md"
[ -f /workspaces/.agents/rules/behavioral-core.md ] && record PASS ".agents/rules/behavioral-core.md (mirror) exists" || record FAIL ".agents/rules/behavioral-core.md (mirror)"

# --- PHASE 3: Hooks ---
echo ""
echo "=== Phase 3A: Hook Syntax (6) ==="
for f in /workspaces/.claude/hooks/*.sh; do
    bash -n "$f" 2>/dev/null && record PASS "$(basename $f)" || record FAIL "$(basename $f)"
done

# --- PHASE 2b: Agents ---
echo ""
echo "=== Phase 2b: Agents ==="
count=0
total=0
for f in /workspaces/.claude/agents/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [ "$name" = "_schema.md" ] && continue
    [[ "$name" == _* ]] && continue
    total=$((total+1))
    head -1 "$f" 2>/dev/null | grep -q "^---" && count=$((count+1)) || record FAIL "frontmatter: $name"
done
[ "$total" -eq 2 ] && record PASS "Agent count: $total (evaluator, wip-manager)" || record FAIL "Agent count: $total (expected 2)"
record PASS "Agent frontmatter ($count/$total)"

# --- PHASE 2c: Skills (Tier 1: 4) ---
echo ""
echo "=== Phase 2c: Skills ==="
skills=$(ls /workspaces/.claude/skills/*/SKILL.md 2>/dev/null | wc -l)
[ "$skills" -eq 4 ] && record PASS "Skills: $skills/4 (refine, status, verify, wiki)" || record FAIL "Skills: $skills (expected 4)"

# --- PHASE 2d: Rules (Tier 1: 2 portable) ---
echo ""
echo "=== Phase 2d: Rules ==="
rules=$(ls /workspaces/.claude/rules/*.md 2>/dev/null | wc -l)
[ "$rules" -eq 2 ] && record PASS "Rules: $rules/2 (behavioral-core, devcontainer-patterns)" || record FAIL "Rules: $rules (expected 2)"

# --- PHASE 2e: Codex hooks (4) ---
echo ""
echo "=== Phase 2e: Codex Hooks ==="
codex_hooks=$(ls /workspaces/.codex/hooks/*.sh 2>/dev/null | wc -l)
[ "$codex_hooks" -eq 4 ] && record PASS "Codex hooks: $codex_hooks/4 (session-start, pre-commit-gate, pre-push-gate, refinement-gate)" || record FAIL "Codex hooks: $codex_hooks (expected 4)"
for f in /workspaces/.codex/hooks/*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" 2>/dev/null && record PASS "$(basename $f)" || record FAIL "$(basename $f)"
done

# --- PHASE 2f: Mirror integrity (.claude/ → .agents/) ---
echo ""
echo "=== Phase 2f: Mirror Integrity ==="
[ -d /workspaces/.agents/skills/evaluator ] && record PASS ".agents/skills/evaluator (agent→skill mirror)" || record FAIL ".agents/skills/evaluator missing"
[ -d /workspaces/.agents/skills/wip-manager ] && record PASS ".agents/skills/wip-manager (agent→skill mirror)" || record FAIL ".agents/skills/wip-manager missing"
[ -x /workspaces/scripts/sync-agents-mirror.sh ] && record PASS "sync-agents-mirror.sh executable" || record FAIL "sync-agents-mirror.sh"

# --- Summary ---
echo ""
echo "=============================================="
echo "  RESULT: $PASS PASS / $FAIL FAIL"
echo "=============================================="
[ "$FAIL" -eq 0 ] && echo "  ALL PASS" || echo "  FAILURES DETECTED"
