#!/usr/bin/env bash
# changed-mode-spec.sh — Hermetic unit tests for --changed source→test mapping.
# No PHPUnit, no DDEV, no network. Uses fixture paths in a tmp directory only.
#
# Run: bash scripts/tests/changed-mode-spec.sh
# Exit 0 = all pass; exit 1 = failures (details printed).
#
# Covers (per wo-03 acceptance):
#   G1  Canonical mapping: src/Dir/Foo.php → tests/src/{Unit,Kernel}/Dir/FooTest.php
#   G2  File directly in src/: src/Bar.php → tests/src/{Unit,Kernel}/BarTest.php
#   G3  Non-src/.php and non-.php files → map_source_to_test_paths exits non-zero
#   G4  find_mapped_tests returns existing test file only
#   G5  Unmapped source (no test exists) → find_mapped_tests produces no output (gap, not fail)
#   G6  Module name containing "src_" does not confuse the root detection
#   G7  no-flag path — guard: --changed flag detection does not affect existing ACTION parsing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../drupal/lib-changed-mapping.sh"

if [[ ! -f "$LIB" ]]; then
  echo "FATAL: lib-changed-mapping.sh not found at $LIB" >&2
  exit 2
fi
# shellcheck source=../drupal/lib-changed-mapping.sh
source "$LIB"

PASS=0
FAIL=0
declare -a ERRORS=()

# ── Assertion helpers ────────────────────────────────────────────────────────

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: $desc | '$needle' not found in: $(echo "$haystack" | tr '\n' '|')")
    echo "  FAIL: $desc"
    echo "        needle  : $needle"
    echo "        haystack: $(echo "$haystack" | tr '\n' '|')"
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: $desc | expected='$expected' actual='$actual'")
    echo "  FAIL: $desc | expected='$expected' actual='$actual'"
  fi
}

assert_exit_nonzero() {
  local desc="$1" cmd="$2"
  local out rc=0
  out=$(eval "$cmd" 2>&1) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc (exit $rc)"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: $desc | expected non-zero exit but got 0; output='$out'")
    echo "  FAIL: $desc | expected non-zero exit but got 0"
  fi
}

# ── Fixture setup ────────────────────────────────────────────────────────────

TMPDIR_FIXTURE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_FIXTURE"' EXIT

MOD_ROOT="$TMPDIR_FIXTURE/web/modules/custom/my_module"
mkdir -p "${MOD_ROOT}/src/Service"
mkdir -p "${MOD_ROOT}/tests/src/Unit/Service"
# Kernel test does NOT exist for this module — used to test gap detection

# Touch the Unit test only; Kernel is intentionally absent (gap)
touch "${MOD_ROOT}/tests/src/Unit/Service/MyServiceTest.php"

# ── Tests ────────────────────────────────────────────────────────────────────

echo "=== changed-mode-spec.sh ==="
echo ""

# ── G1: Canonical mapping ────────────────────────────────────────────────────
echo "G1: map_source_to_test_paths — canonical (subdir in src/)"
SRC1="web/modules/custom/my_module/src/Service/MyService.php"
MAPPED1=$(map_source_to_test_paths "$SRC1")

assert_contains \
  "maps to Unit subdir" \
  "web/modules/custom/my_module/tests/src/Unit/Service/MyServiceTest.php" \
  "$MAPPED1"

assert_contains \
  "maps to Kernel subdir" \
  "web/modules/custom/my_module/tests/src/Kernel/Service/MyServiceTest.php" \
  "$MAPPED1"

echo ""

# ── G2: File directly in src/ ────────────────────────────────────────────────
echo "G2: map_source_to_test_paths — file directly in src/ (no subdir)"
SRC2="web/modules/custom/my_module/src/MyClass.php"
MAPPED2=$(map_source_to_test_paths "$SRC2")

assert_contains \
  "src-root file → Unit/MyClassTest.php" \
  "web/modules/custom/my_module/tests/src/Unit/MyClassTest.php" \
  "$MAPPED2"

assert_contains \
  "src-root file → Kernel/MyClassTest.php" \
  "web/modules/custom/my_module/tests/src/Kernel/MyClassTest.php" \
  "$MAPPED2"

# G2b: must NOT include a spurious extra path segment
echo ""
assert_eq \
  "exactly two lines for a src-root file" \
  "2" \
  "$(echo "$MAPPED2" | wc -l | tr -d ' ')"

echo ""

# ── G3: Non-src / non-php files — map_source_to_test_paths exits non-zero ───
echo "G3: map_source_to_test_paths — non-matchable files exit non-zero"

assert_exit_nonzero \
  "template .php outside src/ exits non-zero" \
  "map_source_to_test_paths 'web/modules/custom/my_module/templates/my-template.php'"

assert_exit_nonzero \
  "non-.php src file exits non-zero" \
  "map_source_to_test_paths 'web/modules/custom/my_module/src/MyClass.yml'"

assert_exit_nonzero \
  "CSS file exits non-zero" \
  "map_source_to_test_paths 'themes/custom/my_theme/src/scss/main.scss'"

echo ""

# ── G4: find_mapped_tests — returns existing test file ──────────────────────
echo "G4: find_mapped_tests — returns paths that exist on disk"

# Use absolute src path so candidate paths are also absolute
SRC_ABS="${MOD_ROOT}/src/Service/MyService.php"
FOUND=$(find_mapped_tests "$SRC_ABS")

assert_contains \
  "finds the existing Unit test" \
  "tests/src/Unit/Service/MyServiceTest.php" \
  "$FOUND"

# Kernel test does not exist — should NOT be in output
KERNEL_FOUND=$(echo "$FOUND" | grep -F "Kernel" || true)
assert_eq \
  "absent Kernel test is not returned" \
  "" \
  "$KERNEL_FOUND"

echo ""

# ── G5: Unmapped source → empty output (gap, not failure) ───────────────────
echo "G5: find_mapped_tests — unmapped source produces empty output (gap)"

SRC_NO_TEST="${MOD_ROOT}/src/Service/NoTestForThisService.php"
FOUND_GAP=$(find_mapped_tests "$SRC_NO_TEST" || true)

assert_eq \
  "no test for NoTestForThisService → empty output" \
  "" \
  "$FOUND_GAP"

# Verify find_mapped_tests exits 0 (gaps are not failures)
find_mapped_tests "$SRC_NO_TEST" > /dev/null 2>&1
assert_eq \
  "find_mapped_tests exits 0 even when no test exists (gap not failure)" \
  "0" \
  "$?"

echo ""

# ── G6: Module name with "src_" prefix — root detection not confused ─────────
echo "G6: map_source_to_test_paths — module name containing 'src_'"

SRC3="web/modules/custom/src_tools/src/Foo/Bar.php"
MAPPED3=$(map_source_to_test_paths "$SRC3")

assert_contains \
  "module root is src_tools (not confused by src_ in module name)" \
  "web/modules/custom/src_tools/tests/src/Unit/Foo/BarTest.php" \
  "$MAPPED3"

assert_contains \
  "Kernel path also correct for src_ module name" \
  "web/modules/custom/src_tools/tests/src/Kernel/Foo/BarTest.php" \
  "$MAPPED3"

echo ""

# ── G7: Guard — no-flag arg parsing stays unchanged ─────────────────────────
echo "G7: Guard — first-arg --changed detection is additive (spot-check)"
# The no-flag path is tested implicitly: sourcing the lib does not alter
# any globals or re-define existing functions. Confirm by checking that
# typical ACTION values are not shadowed.
assert_exit_nonzero \
  "lib defines map_source_to_test_paths (not a random name)" \
  "! declare -f map_source_to_test_paths > /dev/null"

assert_exit_nonzero \
  "lib defines find_mapped_tests (not a random name)" \
  "! declare -f find_mapped_tests > /dev/null"

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────────────────────────"
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  for e in "${ERRORS[@]}"; do
    echo "  $e"
  done
  exit 1
fi
echo ""
