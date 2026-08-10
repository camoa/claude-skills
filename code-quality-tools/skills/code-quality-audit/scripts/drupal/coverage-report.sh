#!/bin/bash
# coverage-report.sh - Run PHPUnit with PCOV coverage
# Part of code-quality-audit skill
#
# SCOPE (no flags): ${DRUPAL_MODULES_PATH} — this project's custom code, the same
#   path lint-check.sh, solid-check.sh and dry-check.sh check. It is passed to
#   PHPUnit as a path argument, so discovery follows the path.
#
#   It used to be `--testsuite unit,kernel` with no path, which is NOT this
#   project's code: under core's phpunit config those suites are built by
#   core/tests/TestSuites/*TestSuite.php, whose addTestsBySuiteNamespace() adds
#   core's own tests AND scans every extension root returned by
#   drupal_phpunit_contrib_extension_directory_roots() — core/modules,
#   core/profiles, core/themes, modules (contrib included), profiles, themes and
#   sites/*/modules. So the run executed core's and every contrib module's unit
#   and kernel tests. On a real client project that ran for minutes at sustained
#   CPU and had to be killed; full-audit.sh calls this at step 3, which is the
#   likely mechanism behind an audit that stopped there.
#
#   `pcov.directory` did already narrow which FILES were instrumented, so the
#   reported percentage was about custom code. What it could not narrow is which
#   TESTS were discovered and executed, which is where the time went.
#
# --full-suite (or COVERAGE_FULL_SUITE=1):
#   Explicit opt-in to the old whole-installation run (--testsuite unit,kernel).
#
#   TIER NOTE: a path argument and --testsuite are mutually exclusive in PHPUnit,
#   so the scoped default cannot also say "unit,kernel". Discovery under the path
#   is by test file, which means a custom module carrying tests/src/Functional
#   now has those tests discovered too — they were previously excluded by the
#   testsuite names. That is bounded by the project's own code, and a functional
#   test with no SIMPLETEST_BASE_URL errors loudly rather than reporting clean.
#   A single path argument is used rather than one per tier because a single path
#   is accepted by every PHPUnit that Drupal 9/10/11 pins, and a multi-path
#   invocation silently ignoring the extra paths on an older PHPUnit would shrink
#   the scope without saying so.
#
# --changed <src.php> [src2.php ...]:
#   Scopes coverage to the changed source files.
#   Runs only the co-located Unit tests mapped from each changed source, and
#   passes --coverage-filter for each changed source file so the coverage report
#   reflects only the changed code.
#   Sources with no co-located test are recorded as coverage gaps — not failures.
#   NOTE: PHPUnit has no --findRelatedTests; that flag is Jest/Next.js only.
#         The mapping is structural (path convention), not semantic.
#   TIER (design §2/§5): Unit only — Kernel needs a running-site bootstrap and
#         cannot run in a detached worktree; it is handled at the task stage.
#   Guard: this mode is active ONLY when the first argument is --changed.
#          All other invocations are byte-identical to pre-change behaviour.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"
DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"
COVERAGE_MINIMUM="${COVERAGE_MINIMUM:-70}"
COVERAGE_TARGET="${COVERAGE_TARGET:-80}"

# ── Drupal phpunit config resolver ────────────────────────────────────────────
# Drupal Unit tests extend Drupal\Tests\UnitTestCase, which only autoloads under
# core's phpunit config. A bare `phpunit <test>` fails with "Class
# Drupal\Tests\UnitTestCase not found", so phpunit MUST be invoked with -c
# <core-config>. Paths are project-root-relative (ddev exec cwd = mounted root).
# Tries: web/core, docroot/core, core, then project-root phpunit.xml[.dist].
# Echoes the first match; returns 1 (empty output) if none found.
resolve_phpunit_config() {
    local cfg
    for cfg in \
        web/core/phpunit.xml.dist \
        docroot/core/phpunit.xml.dist \
        core/phpunit.xml.dist \
        phpunit.xml \
        phpunit.xml.dist; do
        if [ -f "$cfg" ]; then
            echo "$cfg"
            return 0
        fi
    done
    return 1
}

# ── --changed guard ───────────────────────────────────────────────────────────
# Intercept --changed before main script body; no-flag path is byte-identical.
if [[ "${1:-}" == "--changed" ]]; then
  shift
  _CHANGED_FILES=("$@")

  # Source mapping library (co-located with this script)
  _LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-changed-mapping.sh"
  # shellcheck source=lib-changed-mapping.sh
  source "$_LIB"

  echo "=== Coverage Analysis — --changed mode (PHPUnit + PCOV) ==="
  echo ""

  # Check DDEV
  if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
    exit 2
  fi

  # Check for PCOV
  # Probe with grep -q, not `grep -c ... || echo 0`: grep -c prints its count AND
  # exits 1 when the count is zero, so the fallback appends a second line and the
  # value becomes $'0\n0'. Every numeric test on it then dies with "integer
  # expression expected" — a non-zero status, which takes the else branch and
  # reports "PCOV available" precisely when pcov is missing.
  # The pattern tolerates surrounding whitespace rather than anchoring on `pcov`
  # alone: `[[:space:]]` covers CR, so a container emitting CRLF does not read as
  # "absent".
  PCOV_AVAILABLE=0
  if ddev exec php -m 2>/dev/null | grep -qiE '^[[:space:]]*pcov[[:space:]]*$'; then PCOV_AVAILABLE=1; fi
  if [ "$PCOV_AVAILABLE" -eq 0 ]; then
    echo -e "${YELLOW}[WARN]${NC} PCOV not available, coverage will be slower"
    PCOV_FLAGS=""
  else
    echo -e "${GREEN}[OK]${NC} PCOV available"
    PCOV_FLAGS="-d pcov.enabled=1 -d pcov.directory=/var/www/html/${DRUPAL_MODULES_PATH}"
  fi

  # Check for PHPUnit
  if ! ddev exec vendor/bin/phpunit --version &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} PHPUnit not found"
    echo "  Install with: ddev composer require --dev drupal/core-dev"
    exit 2
  fi

  # Map changed sources → test paths; collect gaps
  _test_paths=()
  _gap_files=()
  _coverage_filter_args=()

  for src_file in "${_CHANGED_FILES[@]}"; do
    if [[ "$src_file" != *.php ]] || [[ "$src_file" != *"/src/"* ]]; then
      continue
    fi

    found=$(find_mapped_tests "$src_file")
    if [[ -n "$found" ]]; then
      while IFS= read -r tp; do
        _test_paths+=("$tp")
        echo -e "${GREEN}[MAPPED]${NC} $(basename "$src_file") → $tp"
      done <<< "$found"
    else
      _gap_files+=("$src_file")
      echo -e "${YELLOW}[GAP]${NC} No co-located test for: $src_file"
    fi

    # Collect coverage filter arg for this source regardless of test presence
    _coverage_filter_args+=("--coverage-filter" "$src_file")
  done

  if [[ ${#_gap_files[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}[INFO]${NC} Coverage gaps (no co-located test — not failures):"
    for gap in "${_gap_files[@]}"; do
      echo "       $gap"
    done
    echo ""
    echo "  Mapping limit: PHPUnit has no --findRelatedTests (Jest/Next.js only)."
    echo "  Convention: src/<Dir>/Foo.php → tests/src/Unit/<Dir>/FooTest.php (Unit tier only; Kernel = task stage)"
  fi

  if [[ ${#_test_paths[@]} -eq 0 ]]; then
    echo ""
    echo -e "${YELLOW}[WARN]${NC} No mapped tests found. All changed sources are gaps."
    echo "  No tests run. Exit 0."
    exit 0
  fi

  mkdir -p "${REPORT_DIR}/coverage"

  echo ""
  echo "Running ${#_test_paths[@]} mapped test file(s) with coverage filter..."
  echo ""

  PHPUNIT_CMD="php ${PCOV_FLAGS} vendor/bin/phpunit"
  # Drupal core phpunit config (autoloads Drupal\Tests\UnitTestCase)
  _COV_CFG=$(resolve_phpunit_config || true)
  if [ -n "$_COV_CFG" ]; then
    echo -e "${GREEN}[CONFIG]${NC} Using Drupal phpunit config: $_COV_CFG"
    PHPUNIT_CMD+=" -c $_COV_CFG"
  else
    echo -e "${YELLOW}[WARN]${NC} No Drupal phpunit config found; running without -c (Unit tests may fail to autoload)."
  fi
  # Add mapped test paths (instead of --testsuite)
  for tp in "${_test_paths[@]}"; do
    PHPUNIT_CMD+=" $tp"
  done
  # Scope coverage report to changed source files
  for filter_arg in "${_coverage_filter_args[@]}"; do
    PHPUNIT_CMD+=" $filter_arg"
  done
  PHPUNIT_CMD+=" --coverage-clover /var/www/html/${REPORT_DIR}/coverage/clover.xml"
  PHPUNIT_CMD+=" --coverage-text"

  set +e
  COVERAGE_OUTPUT=$(ddev exec ${PHPUNIT_CMD} 2>&1)
  PHPUNIT_EXIT=$?
  set -e

  echo "$COVERAGE_OUTPUT"

  COVERAGE_PCT=$(echo "$COVERAGE_OUTPUT" | grep -oP 'Lines:\s*\K[\d.]+' | head -1 || echo "0")
  if [ -z "$COVERAGE_PCT" ] || [ "$COVERAGE_PCT" == "0" ]; then
    echo -e "${YELLOW}[WARN]${NC} Could not determine coverage percentage"
    COVERAGE_PCT="0"
  fi

  echo ""
  echo "Line Coverage (changed sources): ${COVERAGE_PCT}%"

  if (( $(echo "$COVERAGE_PCT < $COVERAGE_MINIMUM" | bc -l) )); then
    COVERAGE_STATUS="fail"
    echo -e "${RED}[FAIL]${NC} Coverage ${COVERAGE_PCT}% is below minimum ${COVERAGE_MINIMUM}%"
  elif (( $(echo "$COVERAGE_PCT < $COVERAGE_TARGET" | bc -l) )); then
    COVERAGE_STATUS="warning"
    echo -e "${YELLOW}[WARN]${NC} Coverage ${COVERAGE_PCT}% is below target ${COVERAGE_TARGET}%"
  else
    COVERAGE_STATUS="pass"
    echo -e "${GREEN}[PASS]${NC} Coverage ${COVERAGE_PCT}% meets target ${COVERAGE_TARGET}%"
  fi

  # `cmd | grep -oP ... | head -1 || echo 0` never reaches its fallback: the
  # pipeline's status is head's, which is 0 even when grep matched nothing. So a
  # run with no "Tests:" line leaves these EMPTY, and the heredoc below then emits
  # `"test_count": ,` — invalid JSON. Default after assigning instead.
  TESTS_TOTAL=$(echo "$COVERAGE_OUTPUT" | grep -oP 'Tests:\s*\K\d+' | head -1)
  TESTS_TOTAL="${TESTS_TOTAL:-0}"
  TESTS_PASSED=$(echo "$COVERAGE_OUTPUT" | grep -oP 'OK \(\K\d+' | head -1)
  TESTS_PASSED="${TESTS_PASSED:-$TESTS_TOTAL}"
  TESTS_FAILED=$(echo "$COVERAGE_OUTPUT" | grep -oP 'Failures:\s*\K\d+' | head -1)
  TESTS_FAILED="${TESTS_FAILED:-0}"

  # Serialise gap files for JSON
  GAP_JSON=$(printf '%s\n' "${_gap_files[@]+"${_gap_files[@]}"}" | \
    jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]")

  cat > "${REPORT_DIR}/coverage-report.json" << EOF
{
  "mode": "changed",
  "changed_sources_count": ${#_CHANGED_FILES[@]},
  "gaps": ${GAP_JSON},
  "line_coverage": ${COVERAGE_PCT},
  "branch_coverage": null,
  "test_count": ${TESTS_TOTAL},
  "tests_passed": ${TESTS_PASSED},
  "tests_failed": ${TESTS_FAILED},
  "status": "${COVERAGE_STATUS}",
  "thresholds": {
    "minimum": ${COVERAGE_MINIMUM},
    "target": ${COVERAGE_TARGET}
  },
  "pcov_enabled": $([ "$PCOV_AVAILABLE" -gt 0 ] && echo "true" || echo "false"),
  "generated_at": "$(date -Iseconds)"
}
EOF

  echo ""
  echo "Report saved: ${REPORT_DIR}/coverage-report.json"

  case "$COVERAGE_STATUS" in
    pass)    exit 0 ;;
    warning) exit 1 ;;
    fail)    exit 2 ;;
  esac
fi
# ── end --changed guard ───────────────────────────────────────────────────────

# ── --full-suite opt-in ───────────────────────────────────────────────────────
# The whole-installation run is opt-in, not the default. See the SCOPE note at the
# top of this file for what "the whole installation" actually means here.
COVERAGE_FULL_SUITE="${COVERAGE_FULL_SUITE:-0}"
if [[ "${1:-}" == "--full-suite" ]]; then
    COVERAGE_FULL_SUITE=1
    shift
fi

echo "=== Coverage Analysis (PHPUnit + PCOV) ==="
echo ""

# Check DDEV
if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
    exit 2
fi

# Check for PCOV
# Probe with grep -q, not `grep -c ... || echo 0`: grep -c prints its count AND
# exits 1 when the count is zero, so the fallback appends a second line and the
# value becomes $'0\n0'. Every numeric test on it then dies with "integer
# expression expected" — a non-zero status, which takes the else branch and
# reports "PCOV available" precisely when pcov is missing.
# The pattern tolerates surrounding whitespace rather than anchoring on `pcov` alone:
# `[[:space:]]` covers CR, so a container emitting CRLF does not read as "absent".
PCOV_AVAILABLE=0
if ddev exec php -m 2>/dev/null | grep -qiE '^[[:space:]]*pcov[[:space:]]*$'; then PCOV_AVAILABLE=1; fi
if [ "$PCOV_AVAILABLE" -eq 0 ]; then
    echo -e "${YELLOW}[WARN]${NC} PCOV not available, coverage will be slower"
    echo "  Add to .ddev/config.yaml:"
    echo "    webimage_extra_packages:"
    echo "      - php\${DDEV_PHP_VERSION}-pcov"
    PCOV_FLAGS=""
else
    echo -e "${GREEN}[OK]${NC} PCOV available"
    PCOV_FLAGS="-d pcov.enabled=1 -d pcov.directory=/var/www/html/${DRUPAL_MODULES_PATH}"
fi

# Check for PHPUnit
if ! ddev exec vendor/bin/phpunit --version &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} PHPUnit not found"
    echo "  Install with: ddev composer require --dev drupal/core-dev"
    exit 2
fi

# Create coverage directory
mkdir -p "${REPORT_DIR}/coverage"

# Run PHPUnit with coverage
echo ""
echo "Running PHPUnit with coverage..."
if [ "$COVERAGE_FULL_SUITE" == "1" ]; then
    echo "  Scope: --full-suite (core's unit+kernel testsuites: core, contrib and custom)"
else
    echo "  Scope: ${DRUPAL_MODULES_PATH}"
    # Checked on the HOST while PHPUnit runs in the CONTAINER — the same equivalence
    # the rest of this script already relies on (resolve_phpunit_config stats
    # web/core/phpunit.xml.dist here and passes the same relative path there).
    #
    # A missing path is announced but NOT turned into an early exit 0 the way
    # lint-check.sh reports an unscannable tree. full-audit.sh reads this gate's exit
    # status and maps 0 to "pass", so exiting 0 on a path that was never measured
    # would report clean coverage for code nobody looked at. Falling through instead
    # leaves PHPUnit with nothing to run, no "Lines:" in its output, 0% coverage and
    # exit 2 — wrong in the loud direction.
    if [ ! -d "${DRUPAL_MODULES_PATH}" ]; then
        echo -e "  ${YELLOW}[WARN]${NC} ${DRUPAL_MODULES_PATH} does not exist — PHPUnit will find nothing here."
        echo "         Set DRUPAL_MODULES_PATH to this project's custom code."
    fi
fi
echo ""

# Build PHPUnit command
PHPUNIT_CMD="php ${PCOV_FLAGS} vendor/bin/phpunit"
# Drupal core phpunit config (autoloads Drupal\Tests\UnitTestCase)
_COV_CFG=$(resolve_phpunit_config || true)
if [ -n "$_COV_CFG" ]; then
    echo -e "${GREEN}[CONFIG]${NC} Using Drupal phpunit config: $_COV_CFG"
    PHPUNIT_CMD+=" -c $_COV_CFG"
else
    echo -e "${YELLOW}[WARN]${NC} No Drupal phpunit config found; running without -c (Unit tests may fail to autoload)."
fi
# The scope is recorded in the JSON report: a coverage number is only meaningful
# alongside what was actually run to produce it.
if [ "$COVERAGE_FULL_SUITE" == "1" ]; then
    COVERAGE_SCOPE="full-suite"
    PHPUNIT_CMD+=" --testsuite unit,kernel"
else
    COVERAGE_SCOPE="${DRUPAL_MODULES_PATH}"
    PHPUNIT_CMD+=" ${DRUPAL_MODULES_PATH}"
fi
PHPUNIT_CMD+=" --coverage-clover /var/www/html/${REPORT_DIR}/coverage/clover.xml"
PHPUNIT_CMD+=" --coverage-text"

# Run tests
set +e
COVERAGE_OUTPUT=$(ddev exec ${PHPUNIT_CMD} 2>&1)
PHPUNIT_EXIT=$?
set -e

echo "$COVERAGE_OUTPUT"

# Parse coverage percentage from output
# PHPUnit outputs: "Lines: 72.34% (123/170)"
COVERAGE_PCT=$(echo "$COVERAGE_OUTPUT" | grep -oP 'Lines:\s*\K[\d.]+' | head -1 || echo "0")

if [ -z "$COVERAGE_PCT" ] || [ "$COVERAGE_PCT" == "0" ]; then
    echo -e "${YELLOW}[WARN]${NC} Could not determine coverage percentage"
    COVERAGE_PCT="0"
fi

echo ""
echo "Line Coverage: ${COVERAGE_PCT}%"

# Determine status
if (( $(echo "$COVERAGE_PCT < $COVERAGE_MINIMUM" | bc -l) )); then
    COVERAGE_STATUS="fail"
    echo -e "${RED}[FAIL]${NC} Coverage ${COVERAGE_PCT}% is below minimum ${COVERAGE_MINIMUM}%"
elif (( $(echo "$COVERAGE_PCT < $COVERAGE_TARGET" | bc -l) )); then
    COVERAGE_STATUS="warning"
    echo -e "${YELLOW}[WARN]${NC} Coverage ${COVERAGE_PCT}% is below target ${COVERAGE_TARGET}%"
else
    COVERAGE_STATUS="pass"
    echo -e "${GREEN}[PASS]${NC} Coverage ${COVERAGE_PCT}% meets target ${COVERAGE_TARGET}%"
fi

# Parse test counts from output
#
# `cmd | grep -oP ... | head -1 || echo 0` never reaches its fallback: the
# pipeline's status is head's, which is 0 even when grep matched nothing. So a run
# that prints no "Tests:" line leaves these EMPTY and the heredoc below emits
# `"test_count": ,` — invalid JSON. full-audit.sh then merges this file with
# `jq -s`, which fails, and full-audit.sh runs under `set -e` with that jq's status
# untested, so the whole audit aborts at step 3 of 6 with no summary.
#
# Scoping the run to ${DRUPAL_MODULES_PATH} makes the empty case ORDINARY rather
# than exotic: a project whose custom modules carry no tests gets "No tests
# executed" and no "Tests:" line. Fixing the scope without fixing this would trade
# a run that takes forever for a run that kills the audit.
TESTS_TOTAL=$(echo "$COVERAGE_OUTPUT" | grep -oP 'Tests:\s*\K\d+' | head -1)
TESTS_TOTAL="${TESTS_TOTAL:-0}"
TESTS_PASSED=$(echo "$COVERAGE_OUTPUT" | grep -oP 'OK \(\K\d+' | head -1)
TESTS_PASSED="${TESTS_PASSED:-$TESTS_TOTAL}"
TESTS_FAILED=$(echo "$COVERAGE_OUTPUT" | grep -oP 'Failures:\s*\K\d+' | head -1)
TESTS_FAILED="${TESTS_FAILED:-0}"

# Find uncovered files from clover.xml if available
UNCOVERED_FILES="[]"
if [ -f "${REPORT_DIR}/coverage/clover.xml" ]; then
    # Extract files with low coverage (simplified parsing)
    UNCOVERED_FILES=$(grep -oP 'filename="[^"]+' "${REPORT_DIR}/coverage/clover.xml" 2>/dev/null | \
        sed 's/filename="//' | \
        head -10 | \
        jq -R -s 'split("\n") | map(select(length > 0)) | map({file: ., coverage: 0})' 2>/dev/null || echo "[]")
fi

# Generate JSON report
cat > "${REPORT_DIR}/coverage-report.json" << EOF
{
  "scope": "${COVERAGE_SCOPE}",
  "line_coverage": ${COVERAGE_PCT},
  "branch_coverage": null,
  "files_analyzed": 0,
  "files_covered": 0,
  "uncovered_files": ${UNCOVERED_FILES},
  "test_count": ${TESTS_TOTAL},
  "tests_passed": ${TESTS_PASSED},
  "tests_failed": ${TESTS_FAILED},
  "status": "${COVERAGE_STATUS}",
  "thresholds": {
    "minimum": ${COVERAGE_MINIMUM},
    "target": ${COVERAGE_TARGET}
  },
  "pcov_enabled": $([ "$PCOV_AVAILABLE" -gt 0 ] && echo "true" || echo "false"),
  "generated_at": "$(date -Iseconds)"
}
EOF

echo ""
echo "Report saved: ${REPORT_DIR}/coverage-report.json"

# Exit based on status
case "$COVERAGE_STATUS" in
    pass) exit 0 ;;
    warning) exit 1 ;;
    fail) exit 2 ;;
esac
