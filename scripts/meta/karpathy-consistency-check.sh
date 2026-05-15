#!/bin/bash
# =============================================================================
# karpathy-consistency-check.sh — Behavioral-foundation mirror oracle
# =============================================================================
# Closes AUD-2026-018: automates the behavioral-core.md <-> karpathy SKILL.md
# consistency comparison that the source-of-truth blockquote requires.
#
# Why a dedicated checker (not sync-audit): behavioral-core.md and the karpathy
# SKILL.md are NOT in scripts/meta/portable-manifest.sh (they are auto-imported
# doctrine, not manifest-tracked portable artifacts), so sync-audit.sh never
# compares them. A PASS from sync-audit is therefore not evidence about this
# pair. This script is the primary oracle for the pair.
#
# Usage:
#   bash scripts/meta/karpathy-consistency-check.sh [ROOT]
#
# Mode:
#   GLOBAL (ROOT contains products/) — workspace origin. Asserts the full
#           distribution matrix: 16 behavioral-core + 16 SKILL + 8 .cursor.
#   LEAF   (no products/)           — a standalone receiver clone. Asserts the
#           local repo's pair is self-consistent (count-agnostic).
#
# Enumerator policy: find with path predicates ONLY. grep -r / grep -rl / rg
#   --files are forbidden as enumerators — they silently fail to descend into
#   nested receiver repos (observed: products/derived/DAX_ROOT/* under-scanned
#   by grep -rl, off by 4). The wiki raw source
#   (.claude/agent-memory/wiki/raw/sources/behavioral-core.md) is a different
#   doctrine lineage (6-rule) and is structurally excluded by the path
#   predicate (it is not under .claude/rules/), by design.
#
# Canonical body policy: the synchronized region is "## 1." -> EOF (Rules 1-4
#   plus the closing self-test coda). Everything before "## 1." (frontmatter,
#   title, source-of-truth / skill-handle blockquote, attribution, source link)
#   may legitimately differ. A skill-only footer after the coda is NOT allowed
#   (it would make the extractor outputs diverge).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_root() {
    if [ -n "${1:-}" ] && [ -d "${1:-}" ]; then echo "$1"; return; fi
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then echo "$CLAUDE_PROJECT_DIR"; return; fi
    if command -v git >/dev/null 2>&1; then
        local gc tl
        gc=$(git -C "$SCRIPT_DIR" rev-parse --git-common-dir 2>/dev/null || true)
        if [ -n "$gc" ] && [ "$gc" != ".git" ]; then (cd "$SCRIPT_DIR" && cd "$(dirname "$gc")" && pwd); return; fi
        tl=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
        if [ -n "$tl" ]; then echo "$tl"; return; fi
    fi
    (cd "$SCRIPT_DIR/../.." && pwd)
}

ROOT="$(detect_root "${1:-}")"
INVARIANT='Rules 1–4 and the closing self-test stay synchronized; only frontmatter, title, attribution, and source-link text may differ.'
NARROW='Body content (the 4 rules)'
CODA='**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.'

canonical_karpathy_body() { awk '/^## 1\. /{flag=1} flag' "$1"; }

FAIL=0
note_pass() { echo "[PASS] $1"; }
note_fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

# --- Enumerate (find, path-predicate, verbatim) ---
mapfile -t BC_FILES < <(find "$ROOT" -type f \( -path '*/.claude/rules/behavioral-core.md' -o -path '*/.agents/rules/behavioral-core.md' \) | sort)
mapfile -t SK_FILES < <(find "$ROOT" -type f \( -path '*/.claude/skills/karpathy-guidelines/SKILL.md' -o -path '*/.agents/skills/karpathy-guidelines/SKILL.md' \) | sort)
mapfile -t CU_FILES < <(find "$ROOT" -type f -path '*/.cursor/rules/karpathy-guidelines.mdc' | sort)

MODE="LEAF"
[ -d "$ROOT/products" ] && MODE="GLOBAL"
echo "=== karpathy-consistency-check  mode=$MODE  root=$ROOT ==="
echo "behavioral-core=${#BC_FILES[@]}  SKILL=${#SK_FILES[@]}  cursor=${#CU_FILES[@]}"

# --- 1-3. Count assertions (GLOBAL only; LEAF is count-agnostic but >=1) ---
if [ "$MODE" = "GLOBAL" ]; then
    [ "${#BC_FILES[@]}" -eq 16 ] && note_pass "behavioral-core count = 16" || note_fail "behavioral-core count = ${#BC_FILES[@]} (expected 16)"
    [ "${#SK_FILES[@]}" -eq 16 ] && note_pass "SKILL count = 16"           || note_fail "SKILL count = ${#SK_FILES[@]} (expected 16)"
    [ "${#CU_FILES[@]}" -eq 8 ]  && note_pass "cursor mdc count = 8"        || note_fail "cursor mdc count = ${#CU_FILES[@]} (expected 8)"
else
    [ "${#BC_FILES[@]}" -ge 1 ] && [ "${#SK_FILES[@]}" -ge 1 ] && note_pass "leaf: pair present (bc=${#BC_FILES[@]} skill=${#SK_FILES[@]})" || note_fail "leaf: behavioral-core/SKILL pair missing"
fi

if [ "${#BC_FILES[@]}" -eq 0 ] || [ "${#SK_FILES[@]}" -eq 0 ]; then
    echo "=== RESULT: FAIL (no files enumerated) ==="; exit 1
fi

# --- 4. All canonical bodies identical to the reference (first behavioral-core) ---
# Compare extractor-output to extractor-output (awk vs awk): identical newline
# semantics. A $(...)-stored reference would strip trailing newlines and
# mis-report every file as differing — compare files, not captured strings.
REF_FILE="${BC_FILES[0]}"
BODY_OK=1
for f in "${BC_FILES[@]}" "${SK_FILES[@]}"; do
    if ! diff -q <(canonical_karpathy_body "$REF_FILE") <(canonical_karpathy_body "$f") >/dev/null 2>&1; then
        note_fail "canonical body differs: $f"; BODY_OK=0
    fi
done
[ "$BODY_OK" -eq 1 ] && note_pass "all ${#BC_FILES[@]}+${#SK_FILES[@]} canonical bodies identical"

# --- 5. New invariant sentence present in every bc + skill header ---
INV_OK=1
for f in "${BC_FILES[@]}" "${SK_FILES[@]}"; do
    grep -qF "$INVARIANT" "$f" || { note_fail "invariant sentence missing: $f"; INV_OK=0; }
done
[ "$INV_OK" -eq 1 ] && note_pass "invariant sentence present in all bc+skill"

# --- 6. Narrow phrase global count == 0 (bc + skill + cursor) ---
NARROW_HITS=0
for f in "${BC_FILES[@]}" "${SK_FILES[@]}" "${CU_FILES[@]}"; do
    grep -qF "$NARROW" "$f" && NARROW_HITS=$((NARROW_HITS + 1))
done
[ "$NARROW_HITS" -eq 0 ] && note_pass "narrow phrase global count = 0" || note_fail "narrow phrase still present in $NARROW_HITS file(s)"

# --- 7. Closing coda present in every bc + skill ---
CODA_OK=1
for f in "${BC_FILES[@]}" "${SK_FILES[@]}"; do
    grep -qF "$CODA" "$f" || { note_fail "coda missing: $f"; CODA_OK=0; }
done
[ "$CODA_OK" -eq 1 ] && note_pass "closing coda present in all bc+skill"

# --- 8. Every .cursor mdc retains the coda (content scope-out; presence check) ---
if [ "${#CU_FILES[@]}" -gt 0 ]; then
    CU_OK=1
    for f in "${CU_FILES[@]}"; do
        grep -qF "$CODA" "$f" || { note_fail "cursor coda missing: $f"; CU_OK=0; }
    done
    [ "$CU_OK" -eq 1 ] && note_pass "all ${#CU_FILES[@]} cursor mdc retain coda"
fi

echo "=== RESULT: $([ "$FAIL" -eq 0 ] && echo PASS || echo "FAIL ($FAIL)") ==="
[ "$FAIL" -eq 0 ]
