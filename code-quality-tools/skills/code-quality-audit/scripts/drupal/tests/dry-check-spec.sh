#!/usr/bin/env bash
# dry-check-spec.sh — Hermetic unit spec for the verdict-filter logic in dry-check.sh.
#
# Drives parse_clone_blocks() and clone_touches_changed() directly against fixture
# phpcpd-style clone reports + fixture changed-files lists. No ddev, no phpcpd
# required. Asserts:
#   - A clone touching a changed file → failing (clone_touches_changed returns 0)
#   - A clone entirely among unchanged files → informational (clone_touches_changed returns 1)
#   - No-flag behavior: ALL clones are parsed from the output (no filtering suppresses any)
#   - parse_clone_blocks correctly strips /var/www/html/ ddev prefix
#
# Run: bash dry-check-spec.sh
# Exit 0 on all pass; exit 1 on first failure (prints which assertion failed).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_CHECK="${SCRIPT_DIR}/../dry-check.sh"
FIXTURES="${SCRIPT_DIR}/fixtures"

PHPCPD_DDEV="${FIXTURES}/phpcpd-output.txt"           # paths with /var/www/html/ prefix
PHPCPD_PLAIN="${FIXTURES}/phpcpd-output-no-ddev.txt"  # relative paths (no ddev prefix)
CHANGED="${FIXTURES}/changed-files.txt"               # some files match clones
CHANGED_NO_MATCH="${FIXTURES}/changed-files-no-match.txt"  # no files match any clone

# ---- Minimal test harness ----
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected: $(printf '%q' "$expected")"
        echo "        actual:   $(printf '%q' "$actual")"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_return() {
    local desc="$1" expected_rc="$2"
    local actual_rc="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected_rc" = "$actual_rc" ]; then
        echo "  PASS: $desc (exit $actual_rc)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected exit: $expected_rc"
        echo "        actual exit:   $actual_rc"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Source the dry-check.sh functions WITHOUT executing main body.
# We use a guard: source with DRY_CHECK_SOURCED=1 so the script can skip its
# ddev-dependent body when sourced for testing. However, dry-check.sh has no
# such guard in the original design — we source it by extracting only the
# function definitions via a subshell trick: source up to the first `echo "==="`.
#
# Simplest approach: source the entire file but redirect its execution side-effects.
# The set -e in dry-check.sh would abort on "ddev describe" — we extract the
# functions we need via grep+eval instead.
_extract_fn() {
    local fn_name="$1"
    # Extract function body (from "fn_name()" up to matching closing brace at col 0)
    awk "/^${fn_name}\\(\\)/{p=1} p{print} p && /^}$/{p=0}" "$DRY_CHECK"
}

# Load parse_clone_blocks and clone_touches_changed into this shell
eval "$(_extract_fn parse_clone_blocks)"
eval "$(_extract_fn clone_touches_changed)"

echo "=== dry-check.sh verdict-filter spec ==="
echo ""

# ---------------------------------------------------------------------------
# Suite 1: parse_clone_blocks — correct extraction from ddev-prefixed output
# ---------------------------------------------------------------------------
echo "Suite 1: parse_clone_blocks (ddev prefix)"

BLOCKS=$(parse_clone_blocks "$PHPCPD_DDEV")
BLOCK_COUNT=$(echo "$BLOCKS" | grep -c '|' || true)

assert_eq "extracts 3 clone groups" "3" "$BLOCK_COUNT"

LINE1=$(echo "$BLOCKS" | sed -n '1p')
assert_eq "clone 1: foo|bar (ddev prefix stripped)" \
    "web/modules/custom/foo/src/FooService.php|web/modules/custom/bar/src/BarService.php" \
    "$LINE1"

LINE2=$(echo "$BLOCKS" | sed -n '2p')
assert_eq "clone 2: baz|qux" \
    "web/modules/custom/baz/src/BazService.php|web/modules/custom/qux/src/QuxService.php" \
    "$LINE2"

LINE3=$(echo "$BLOCKS" | sed -n '3p')
assert_eq "clone 3: alpha|beta" \
    "web/modules/custom/alpha/src/AlphaHelper.php|web/modules/custom/beta/src/BetaHelper.php" \
    "$LINE3"

echo ""

# ---------------------------------------------------------------------------
# Suite 2: parse_clone_blocks — no ddev prefix (paths already relative)
# ---------------------------------------------------------------------------
echo "Suite 2: parse_clone_blocks (no ddev prefix)"

BLOCKS_PLAIN=$(parse_clone_blocks "$PHPCPD_PLAIN")
BLOCK_COUNT_PLAIN=$(echo "$BLOCKS_PLAIN" | grep -c '|' || true)

assert_eq "extracts 2 clone groups from plain output" "2" "$BLOCK_COUNT_PLAIN"

PLAIN1=$(echo "$BLOCKS_PLAIN" | sed -n '1p')
assert_eq "clone 1 plain: foo|bar" \
    "web/modules/custom/foo/src/FooService.php|web/modules/custom/bar/src/BarService.php" \
    "$PLAIN1"

echo ""

# ---------------------------------------------------------------------------
# Suite 3: clone_touches_changed — clone where first file is changed → fail
# ---------------------------------------------------------------------------
echo "Suite 3: clone_touches_changed — change-touching clone"

CLONE_TOUCHING="web/modules/custom/foo/src/FooService.php|web/modules/custom/bar/src/BarService.php"
clone_touches_changed "$CLONE_TOUCHING" "$CHANGED"
RC=$?
assert_return "clone with changed file (FooService) returns 0 (touching)" "0" "$RC"

# ---------------------------------------------------------------------------
# Suite 4: clone_touches_changed — clone where second file is changed → fail
# ---------------------------------------------------------------------------
echo "Suite 4: clone_touches_changed — second file in clone is changed"

CLONE_SECOND="web/modules/custom/unchanged/src/UnchangedService.php|web/modules/custom/baz/src/BazService.php"
clone_touches_changed "$CLONE_SECOND" "$CHANGED"
RC=$?
assert_return "clone with changed file (BazService) as second copy returns 0 (touching)" "0" "$RC"

# ---------------------------------------------------------------------------
# Suite 5: clone_touches_changed — clone entirely among unchanged files → info
# ---------------------------------------------------------------------------
echo "Suite 5: clone_touches_changed — unchanged-only clone"

CLONE_UNCHANGED="web/modules/custom/alpha/src/AlphaHelper.php|web/modules/custom/beta/src/BetaHelper.php"
clone_touches_changed "$CLONE_UNCHANGED" "$CHANGED"
RC=$?
assert_return "clone with no changed files returns 1 (informational)" "1" "$RC"

# ---------------------------------------------------------------------------
# Suite 6: clone_touches_changed — no clone file matches changed list
# ---------------------------------------------------------------------------
echo "Suite 6: clone_touches_changed — changed list with no clone overlap"

clone_touches_changed "$CLONE_TOUCHING" "$CHANGED_NO_MATCH"
RC=$?
assert_return "clone against no-match changed list returns 1 (informational)" "1" "$RC"

# ---------------------------------------------------------------------------
# Suite 7: no-flag behavior — parse_clone_blocks sees ALL clones (no filter suppressed)
# ---------------------------------------------------------------------------
echo "Suite 7: no-flag path — all clones extracted from output"

ALL_BLOCKS=$(parse_clone_blocks "$PHPCPD_DDEV")
ALL_COUNT=$(echo "$ALL_BLOCKS" | wc -l | tr -d ' ')

assert_eq "without filtering, all 3 clone groups are returned" "3" "$ALL_COUNT"

# Simulate no-flag behavior: count how many would "fail" when all clones count
SIMULATED_FAIL=0
while IFS= read -r cl; do
    [ -z "$cl" ] && continue
    SIMULATED_FAIL=$((SIMULATED_FAIL + 1))
done <<< "$ALL_BLOCKS"

assert_eq "no-flag: all 3 clones count as failing" "3" "$SIMULATED_FAIL"

# ---------------------------------------------------------------------------
# Suite 8: changed-mode end-to-end verdict using fixture + changed-files
# ---------------------------------------------------------------------------
echo "Suite 8: changed-mode verdict simulation (fixture)"

FAILING=0
INFORMATIONAL=0
while IFS= read -r clone_line; do
    [ -z "$clone_line" ] && continue
    if clone_touches_changed "$clone_line" "$CHANGED"; then
        FAILING=$((FAILING + 1))
    else
        INFORMATIONAL=$((INFORMATIONAL + 1))
    fi
done < <(parse_clone_blocks "$PHPCPD_DDEV")

assert_eq "changed-mode: 2 failing clones (foo+bar, baz+qux touch changed files)" "2" "$FAILING"
assert_eq "changed-mode: 1 informational clone (alpha+beta unchanged)" "1" "$INFORMATIONAL"

# Suite 8b: changed list with no matches → all informational, gate passes
FAILING_NOMATCH=0
INFORMATIONAL_NOMATCH=0
while IFS= read -r clone_line; do
    [ -z "$clone_line" ] && continue
    if clone_touches_changed "$clone_line" "$CHANGED_NO_MATCH"; then
        FAILING_NOMATCH=$((FAILING_NOMATCH + 1))
    else
        INFORMATIONAL_NOMATCH=$((INFORMATIONAL_NOMATCH + 1))
    fi
done < <(parse_clone_blocks "$PHPCPD_DDEV")

assert_eq "no-overlap changed list: 0 failing clones" "0" "$FAILING_NOMATCH"
assert_eq "no-overlap changed list: 3 informational clones" "3" "$INFORMATIONAL_NOMATCH"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: ${TESTS_PASSED}/${TESTS_RUN} passed, ${TESTS_FAILED} failed ==="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
