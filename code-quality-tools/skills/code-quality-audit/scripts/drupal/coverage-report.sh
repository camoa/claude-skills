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

# Where reports go is decided in one place, and it is never inside the audited
# repository unless REPORT_DIR says so or REPORT_DIR_IN_REPO=1 asks for it.
# shellcheck source=../core/report-dir.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/report-dir.sh"
cqt_report_dir_init
cqt_announce_report_dir

# Where this project's custom code lives is answered in ONE place, for every gate. The
# absent-path branch further down is deliberately left as it is: this gate is the
# in-repo precedent for the rule the rest of this task is adopting, and it already
# refuses an early exit 0 with the reason written into the file. Only the layout literal
# moves.
# shellcheck source=../core/path-resolve.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/path-resolve.sh"
cqt_resolve_drupal_paths
COVERAGE_MINIMUM="${COVERAGE_MINIMUM:-70}"
COVERAGE_TARGET="${COVERAGE_TARGET:-80}"

# ── host filesystem vs container filesystem ───────────────────────────────────
#
# PHPUnit runs in the DDEV web container. Every path on its command line is read by the
# container, and the container shares exactly one directory with the host: the bind mount
# at /var/www/html, which IS the audited repository. There is therefore no single string
# that names a writable location for both sides.
#
# --coverage-clover used to be given /var/www/html/${REPORT_DIR}. That worked only while
# REPORT_DIR was the relative `.reports`, i.e. only while this tool wrote its reports into
# the tree it was auditing. With the out-of-repo default the same expression becomes
# /var/www/html/<host-absolute-path>, and it fails twice over: the file lands INSIDE the
# audited repository, which is the invariant the report directory exists to hold, and it
# lands nowhere near where the host then looks for it — so clover.xml is silently never
# read and coverage produces nothing.
#
# Three ways out were weighed.
#
#   Bind a second volume. Means editing .ddev/config.yaml in a repository we do not own
#   and restarting somebody's environment, to run an audit. Rejected.
#
#   Write into the bind mount and move the file to the host afterwards. Puts a report
#   inside the audited repository for the duration of the run, and leaves it there for
#   good whenever the run is interrupted. Rejected: "briefly" is not "never".
#
#   Have the container write somewhere container-local and carry the bytes across on
#   ddev exec's stdout. Chosen. It is what every other in-container tool in this suite
#   already does — security-check.sh gets `composer audit` and `drush pm:security` across
#   with a plain host-side `>` — and clover only needs the extra step because PHPUnit will
#   not write a coverage report to stdout. /tmp is writable in the web container, is not
#   part of the bind mount, and needs no configuration on anybody's project.
#
# $$ is the host PID, which keeps two audits of one project from colliding in there.
CQT_CONTAINER_STAGE="/tmp/cqt-coverage-$$"

# Translate a project path into the path the CONTAINER sees. A project-relative path names
# the same code on both sides, which is why every other `ddev exec` in this suite passes
# one. An absolute DRUPAL_MODULES_PATH is a HOST path: gluing the container prefix onto it
# yields /var/www/html/home/... , a directory that does not exist, so pcov instruments no
# files and the run reports a percentage measured over nothing. Rewritten when it is
# inside this repository, refused when it is not.
#
# CONTRACT: prints a container path and returns 0, or prints NOTHING on stdout, says why
# on stderr, and returns 1. The caller must test the status.
#
# It used to warn and then return the HOST path unchanged, which is the failure the
# comment above describes, wearing the warning that describes it: the unusable path went
# on to `-d pcov.directory=`, the container was handed a directory it does not have, and
# the percentage was still measured over nothing. A warning printed at the top of a gate
# is not a substitute for the number being refused at the bottom of it, so the
# untranslatable case is now a status a caller cannot consume by accident.
cqt_container_path() {
    local p="${1#./}"
    case "${p}" in
        /*)
            local top=""
            top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
            if [ -n "${top}" ] && [ "${p#"${top}/"}" != "${p}" ]; then
                p="${p#"${top}/"}"
            else
                echo -e "${YELLOW}[WARN]${NC} ${1} is an absolute host path outside this repository;" >&2
                echo "         the container cannot see it. Use a project-relative path." >&2
                return 1
            fi
            ;;
    esac
    printf '/var/www/html/%s' "${p%/}"
    return 0
}

# Bring a file the container wrote across to the host. Never fatal — the caller decides
# what a missing coverage report means, and this must not abort the gate under `set -e`.
#
# What arrives is checked, not what ddev reported. A transport that exits 0 having
# delivered an empty file is the same false-clean shape the rest of this suite is built
# against, so the destination is removed unless it holds something that is at least
# shaped like the XML document that was asked for.
cqt_fetch_from_container() {
    local src="$1" dest="$2"
    ddev exec test -s "${src}" >/dev/null 2>&1 || return 1
    ddev exec cat "${src}" > "${dest}" 2>/dev/null || { rm -f "${dest}" 2>/dev/null; return 1; }
    if [ ! -s "${dest}" ] || ! head -c 16 "${dest}" 2>/dev/null | grep -q '<'; then
        rm -f "${dest}" 2>/dev/null
        return 1
    fi
    return 0
}

# Resolved once, here, rather than inside each PCOV probe: both probes are identical
# copies of one another and both are extracted and executed standalone by the spec, so a
# function call inside them would make the block unrunnable on its own.
#
# The status is kept beside the value. Resolving here and consuming it two hundred lines
# later is what let the old warn-and-return-the-host-path version go unnoticed, so the
# failure travels WITH the value: CQT_CONTAINER_PATH_OK=0 means there is no container path
# for this project's code, and both PCOV blocks stop rather than instrument nothing.
# Tested in an `if`, which is also what keeps a non-zero status from killing the script
# here under `set -e` before it has said why.
CQT_CONTAINER_PATH_OK=1
if ! DRUPAL_MODULES_PATH_CONTAINER="$(cqt_container_path "${DRUPAL_MODULES_PATH}")"; then
    CQT_CONTAINER_PATH_OK=0
    DRUPAL_MODULES_PATH_CONTAINER=""
fi

# A coverage percentage measured over the wrong files is worse than no percentage: this
# gate's exit status is read by full-audit.sh, 0 means pass, and pcov pointed at a
# directory the container does not have instruments nothing at all. So the run stops with
# the same status it uses for "the tools are not here" — loud, and not a number.
#
# `if`, not `[ ... ] && return 0`: this script runs under `set -e`, where a leading
# `&&` list that evaluates false is a non-zero status in statement position and kills the
# script — silently, before the message below is ever printed.
cqt_require_container_path() {
    if [ "${CQT_CONTAINER_PATH_OK}" -eq 1 ]; then
        return 0
    fi
    echo -e "${RED}[ERROR]${NC} Coverage cannot be scoped to ${DRUPAL_MODULES_PATH}"
    echo "  It is an absolute host path outside this repository, so the container has no"
    echo "  name for it and PCOV would instrument no files — reporting a percentage"
    echo "  measured over nothing. Set DRUPAL_MODULES_PATH to a project-relative path"
    echo "  (for example web/modules/custom) and run again."
    exit 2
}

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

  # DDEV is up; now, can the container see the code this run was told to measure? Asked
  # here rather than inside the PCOV branch below, because that branch is extracted and
  # executed standalone by the spec and a function call inside it would make the block
  # unrunnable on its own — the same reason the container path is resolved above them.
  cqt_require_container_path

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
    PCOV_FLAGS="-d pcov.enabled=1 -d pcov.directory=${DRUPAL_MODULES_PATH_CONTAINER}"
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
  # Container-local, then copied out. See the host/container note near the top.
  CLOVER_CONTAINER="${CQT_CONTAINER_STAGE}/clover.xml"
  CLOVER_HOST="${REPORT_DIR}/coverage/clover.xml"
  rm -f "${CLOVER_HOST}" 2>/dev/null || true
  ddev exec mkdir -p "${CQT_CONTAINER_STAGE}" >/dev/null 2>&1 || true
  PHPUNIT_CMD+=" --coverage-clover ${CLOVER_CONTAINER}"
  PHPUNIT_CMD+=" --coverage-text"

  set +e
  COVERAGE_OUTPUT=$(ddev exec ${PHPUNIT_CMD} 2>&1)
  PHPUNIT_EXIT=$?
  set -e

  if cqt_fetch_from_container "${CLOVER_CONTAINER}" "${CLOVER_HOST}"; then
    echo -e "${GREEN}[OK]${NC} Coverage data copied out of the container: ${CLOVER_HOST}"
  else
    echo -e "${YELLOW}[WARN]${NC} No clover report came back from ${CLOVER_CONTAINER}"
  fi
  ddev exec rm -rf "${CQT_CONTAINER_STAGE}" >/dev/null 2>&1 || true

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
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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

# Same question as in --changed mode, and it applies to --full-suite too: pcov.directory
# is built from this path whichever scope the run uses.
cqt_require_container_path

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
    PCOV_FLAGS="-d pcov.enabled=1 -d pcov.directory=${DRUPAL_MODULES_PATH_CONTAINER}"
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
# Container-local, then copied out. See the host/container note near the top.
CLOVER_CONTAINER="${CQT_CONTAINER_STAGE}/clover.xml"
CLOVER_HOST="${REPORT_DIR}/coverage/clover.xml"
# A clover file from an earlier run must not be read back as this run's result if this
# run produces none — the uncovered-files block below reads whatever is at that path.
rm -f "${CLOVER_HOST}" 2>/dev/null || true
ddev exec mkdir -p "${CQT_CONTAINER_STAGE}" >/dev/null 2>&1 || true
PHPUNIT_CMD+=" --coverage-clover ${CLOVER_CONTAINER}"
PHPUNIT_CMD+=" --coverage-text"

# Run tests
set +e
COVERAGE_OUTPUT=$(ddev exec ${PHPUNIT_CMD} 2>&1)
PHPUNIT_EXIT=$?
set -e

if cqt_fetch_from_container "${CLOVER_CONTAINER}" "${CLOVER_HOST}"; then
    echo -e "${GREEN}[OK]${NC} Coverage data copied out of the container: ${CLOVER_HOST}"
else
    echo -e "${YELLOW}[WARN]${NC} No clover report came back from ${CLOVER_CONTAINER}"
fi
ddev exec rm -rf "${CQT_CONTAINER_STAGE}" >/dev/null 2>&1 || true

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
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
