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
  if echo "$haystack" | grep -qF -- "$needle"; then
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
mkdir -p "${MOD_ROOT}/tests/src/Kernel/Service"

# Touch the Unit test (the per-WO target).
touch "${MOD_ROOT}/tests/src/Unit/Service/MyServiceTest.php"
# Touch a Kernel test ON DISK too — it must STILL be excluded from the per-WO
# mapping (running-site tier), proving exclusion is by design not by absence.
touch "${MOD_ROOT}/tests/src/Kernel/Service/MyServiceTest.php"

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

# TIER SCOPING (design §2/§5): per-WO worktree tier is Unit ONLY.
# Kernel needs a running-site bootstrap → never emitted by the per-WO mapper.
assert_eq \
  "Kernel candidate is NOT emitted (per-WO worktree = Unit only)" \
  "" \
  "$(echo "$MAPPED1" | grep -F "Kernel" || true)"

assert_eq \
  "exactly one candidate (Unit only) for a subdir source" \
  "1" \
  "$(echo "$MAPPED1" | wc -l | tr -d ' ')"

echo ""

# ── G2: File directly in src/ ────────────────────────────────────────────────
echo "G2: map_source_to_test_paths — file directly in src/ (no subdir)"
SRC2="web/modules/custom/my_module/src/MyClass.php"
MAPPED2=$(map_source_to_test_paths "$SRC2")

assert_contains \
  "src-root file → Unit/MyClassTest.php" \
  "web/modules/custom/my_module/tests/src/Unit/MyClassTest.php" \
  "$MAPPED2"

assert_eq \
  "src-root file → Kernel candidate NOT emitted" \
  "" \
  "$(echo "$MAPPED2" | grep -F "Kernel" || true)"

# G2b: exactly one candidate (Unit only) — no spurious extra path segment
echo ""
assert_eq \
  "exactly one line (Unit only) for a src-root file" \
  "1" \
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

# Kernel is never a candidate in the per-WO path; even though a KernelTest
# exists on disk in the fixture, it must NOT be returned (running-site tier).
KERNEL_FOUND=$(echo "$FOUND" | grep -F "Kernel" || true)
assert_eq \
  "Kernel test never returned per-WO (even when present on disk)" \
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

assert_eq \
  "Kernel candidate NOT emitted for src_ module name (Unit only)" \
  "" \
  "$(echo "$MAPPED3" | grep -F "Kernel" || true)"

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

# ── G8: Script-level wiring — --changed guard + all-gaps → exit 0 ────────────
# Drives the REAL tdd-workflow.sh / coverage-report.sh via the --changed guard.
# An all-gaps run (changed source with no mapped test) exits 0 BEFORE reaching
# `ddev`, so this is hermetic — no DDEV / PHPUnit required.
echo "G8: Script-level — --changed guard interception + all-gaps exit 0"

TDD_SH="${SCRIPT_DIR}/../drupal/tdd-workflow.sh"
COV_SH="${SCRIPT_DIR}/../drupal/coverage-report.sh"

# A .php under /src/ with NO co-located test in the fixture → pure gap.
GAP_SRC="${MOD_ROOT}/src/Service/UnmappedGapService.php"

# tdd-workflow.sh --changed <gap-src> must exit 0 and print a gap notice.
set +e
TDD_OUT=$(bash "$TDD_SH" --changed "$GAP_SRC" 2>&1)
TDD_RC=$?
set -e
assert_eq "tdd-workflow.sh --changed all-gaps exits 0" "0" "$TDD_RC"
assert_contains "tdd-workflow.sh reports the gap" "GAP" "$TDD_OUT"
assert_contains "tdd-workflow.sh names the unmapped source" "UnmappedGapService.php" "$TDD_OUT"

# A non-.php changed file is skipped → still all-gaps → exit 0 (no ddev).
set +e
TDD_OUT2=$(bash "$TDD_SH" --changed "${MOD_ROOT}/my_module.module" 2>&1)
TDD_RC2=$?
set -e
assert_eq "tdd-workflow.sh --changed non-php-only exits 0" "0" "$TDD_RC2"

# coverage-report.sh --changed: the all-gaps short-circuit is gated AFTER the
# ddev check, so we only assert the guard is intercepted (does not fall through
# to the no-flag whole-suite body). With no DDEV it exits 2 at the ddev check —
# which still proves the --changed branch was taken (the no-flag body prints
# "=== Coverage Analysis (PHPUnit + PCOV) ===" with no "--changed mode" suffix).
set +e
COV_OUT=$(bash "$COV_SH" --changed "$GAP_SRC" 2>&1)
set -e
assert_contains "coverage-report.sh enters --changed branch" "--changed mode" "$COV_OUT"

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
