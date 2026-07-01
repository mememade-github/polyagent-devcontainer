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
#           distribution matrix. The default matrix count is 16 and can be
#           overridden with EXPECTED_KARPATHY_COUNT for intentional reshapes.
#   LEAF   (no products/)           — a standalone receiver clone. Asserts the
#           local repo's pair is self-consistent (count-agnostic).
#
# Enumerator policy: find with path predicates ONLY. grep -r / grep -rl / rg
#   --files are forbidden as enumerators — they can silently miss nested
#   receiver repos and produce false global counts. The wiki raw source
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

# Shared worktree-aware root detection — single source of truth (see lib/).
_LIB="$SCRIPT_DIR/lib/detect-root.sh"
[ -r "$_LIB" ] || { echo "FATAL: missing $_LIB" >&2; exit 3; }
# shellcheck source=scripts/meta/lib/detect-root.sh
. "$_LIB"

ROOT="$(detect_root "${1:-}")"
DEFAULT_EXPECTED_KARPATHY_COUNT=16
EXPECTED_COUNT="${EXPECTED_KARPATHY_COUNT:-$DEFAULT_EXPECTED_KARPATHY_COUNT}"
INVARIANT='Rules 1–4 and the closing self-test stay synchronized; only frontmatter, title, attribution, and source-link text may differ.'
NARROW='Body content (the 4 rules)'
CODA='**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.'

canonical_karpathy_body() { awk '/^## 1\. /{flag=1} flag' "$1"; }

FAIL=0
note_pass() { echo "[PASS] $1"; }
note_fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

# --- Enumerate (find, path-predicate, verbatim) ---
mapfile -t BC_FILES < <(find "$ROOT" -type f -not -path '*/.claude/worktrees/*' \( -path '*/.claude/rules/behavioral-core.md' -o -path '*/.agents/rules/behavioral-core.md' \) | sort)
mapfile -t SK_FILES < <(find "$ROOT" -type f -not -path '*/.claude/worktrees/*' \( -path '*/.claude/skills/karpathy-guidelines/SKILL.md' -o -path '*/.agents/skills/karpathy-guidelines/SKILL.md' \) | sort)

MODE="LEAF"
[ -d "$ROOT/products" ] && MODE="GLOBAL"
echo "=== karpathy-consistency-check  mode=$MODE  root=$ROOT ==="
echo "behavioral-core=${#BC_FILES[@]}  SKILL=${#SK_FILES[@]}"

# --- 1-3. Count assertions (GLOBAL only; LEAF is count-agnostic but >=1) ---
if [ "$MODE" = "GLOBAL" ]; then
    [ "${#BC_FILES[@]}" -eq "$EXPECTED_COUNT" ] && note_pass "behavioral-core count = $EXPECTED_COUNT" || note_fail "behavioral-core count = ${#BC_FILES[@]} (expected $EXPECTED_COUNT)"
    [ "${#SK_FILES[@]}" -eq "$EXPECTED_COUNT" ] && note_pass "SKILL count = $EXPECTED_COUNT"           || note_fail "SKILL count = ${#SK_FILES[@]} (expected $EXPECTED_COUNT)"
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

# --- 6. Narrow phrase global count == 0 (bc + skill) ---
NARROW_HITS=0
for f in "${BC_FILES[@]}" "${SK_FILES[@]}"; do
    grep -qF "$NARROW" "$f" && NARROW_HITS=$((NARROW_HITS + 1))
done
[ "$NARROW_HITS" -eq 0 ] && note_pass "narrow phrase global count = 0" || note_fail "narrow phrase still present in $NARROW_HITS file(s)"

# --- 7. Closing coda present in every bc + skill ---
CODA_OK=1
for f in "${BC_FILES[@]}" "${SK_FILES[@]}"; do
    grep -qF "$CODA" "$f" || { note_fail "coda missing: $f"; CODA_OK=0; }
done
[ "$CODA_OK" -eq 1 ] && note_pass "closing coda present in all bc+skill"

echo "=== RESULT: $([ "$FAIL" -eq 0 ] && echo PASS || echo "FAIL ($FAIL)") ==="
[ "$FAIL" -eq 0 ]
