#!/bin/bash
# lint-check.sh - Run PHP coding standards checks (Drupal, DrupalPractice)
# Part of code-quality-audit skill

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
DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"
# Themes are custom code and phpcs has a Drupal standard for them, so leaving this out
# does not make the gate narrower — it makes it silently wrong. Every theme file
# (.theme, .php, .inc, .js under web/themes/custom) went unreported for as long as this
# variable was unset here, while security-check.sh three files away read both paths and
# scanned both. Measured on one real client project: 493 errors and 27 warnings across 58
# theme files, 37% of the site's total standards findings, invisible on every run.
DRUPAL_THEMES_PATH="${DRUPAL_THEMES_PATH:-web/themes/custom}"

# =====================
# --changed mode (ADDITIVE): if invoked with `--changed <file>`, scope phpcs to
# the listed files and exit BEFORE the standard path below. Everything from the
# `echo "=== PHP Coding Standards Check ==="` line onward is byte-identical to
# the pre-existing script — a non-`--changed` invocation never enters this block.
# =====================
if [ "$1" == "--changed" ]; then
    CHANGED_FILE="$2"
    echo "=== PHP Coding Standards Check (changed mode) ==="
    echo "[changed mode] Scoping phpcs to files listed in: ${CHANGED_FILE}"
    echo ""

    # Lintable extensions for Drupal
    LINTABLE_EXTS="\.php$|\.module$|\.inc$|\.install$|\.profile$|\.theme$|\.engine$|\.js$"

    # Filter: keep lintable extensions, exclude vendor/core/contrib
    RELEVANT_FILES=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if ! echo "$f" | grep -qE "$LINTABLE_EXTS"; then
            continue
        fi
        if echo "$f" | grep -qE '^(vendor/|web/core/|.*/(contrib)/|web/themes/contrib/|web/modules/contrib/)'; then
            continue
        fi
        RELEVANT_FILES+=("$f")
    done < "$CHANGED_FILE"

    if [ "${#RELEVANT_FILES[@]}" -eq 0 ]; then
        echo -e "${GREEN}[SKIP]${NC} No lintable PHP/JS files in the changed set — clean skip."
        mkdir -p "${REPORT_DIR}/lint"
        cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "mode": "changed",
  "standards": ["Drupal", "DrupalPractice"],
  "changed_file": "${CHANGED_FILE}",
  "relevant_files": 0,
  "errors": 0,
  "warnings": 0,
  "status": "skipped",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        exit 0
    fi

    # Have files to scan — now check DDEV + phpcs availability
    if ! ddev describe &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} DDEV is not running"
        exit 2
    fi
    if ! ddev exec vendor/bin/phpcs --version &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} PHP_CodeSniffer is not installed"
        echo "  Run: ddev composer require --dev drupal/coder"
        exit 1
    fi

    mkdir -p "${REPORT_DIR}/lint"

    echo "Relevant files (${#RELEVANT_FILES[@]}):"
    printf '  %s\n' "${RELEVANT_FILES[@]}"
    echo ""

    CHANGED_ERRORS=0
    CHANGED_WARNINGS=0

    # Single invocation with the scoped file args.
    set +e
    # shellcheck disable=SC2046
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=json \
        "${RELEVANT_FILES[@]}" \
        2>/dev/null > "${REPORT_DIR}/lint/phpcs.json"
    set -e

    set +e
    # shellcheck disable=SC2046
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=summary \
        "${RELEVANT_FILES[@]}" \
        2>&1 | tee "${REPORT_DIR}/lint/phpcs-summary.txt"
    set -e

    if [ -f "${REPORT_DIR}/lint/phpcs.json" ] && command -v jq &> /dev/null; then
        CHANGED_ERRORS=$(jq '.totals.errors // 0' "${REPORT_DIR}/lint/phpcs.json" 2>/dev/null || echo "0")
        CHANGED_WARNINGS=$(jq '.totals.warnings // 0' "${REPORT_DIR}/lint/phpcs.json" 2>/dev/null || echo "0")
    fi

    CHANGED_STATUS="pass"
    if [ "$CHANGED_ERRORS" -gt 0 ]; then
        CHANGED_STATUS="fail"
    elif [ "$CHANGED_WARNINGS" -gt 10 ]; then
        CHANGED_STATUS="warning"
    fi

    cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "mode": "changed",
  "standards": ["Drupal", "DrupalPractice"],
  "changed_file": "${CHANGED_FILE}",
  "relevant_files": ${#RELEVANT_FILES[@]},
  "errors": ${CHANGED_ERRORS},
  "warnings": ${CHANGED_WARNINGS},
  "status": "${CHANGED_STATUS}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    echo ""
    echo "=== Summary (changed mode) ==="
    echo "  Files scanned: ${#RELEVANT_FILES[@]}"
    echo "  Errors:        ${CHANGED_ERRORS}"
    echo "  Warnings:      ${CHANGED_WARNINGS}"
    echo ""

    if [ "$CHANGED_STATUS" == "pass" ]; then
        echo -e "${GREEN}[PASS]${NC} Coding standards check passed"
        exit 0
    elif [ "$CHANGED_STATUS" == "warning" ]; then
        echo -e "${YELLOW}[WARN]${NC} Some warnings found"
        exit 1
    else
        echo -e "${RED}[FAIL]${NC} Coding standards violations found"
        exit 2
    fi
fi

echo "=== PHP Coding Standards Check ==="
echo ""

# Check DDEV
if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
    exit 2
fi

# Check if phpcs is available
if ! ddev exec vendor/bin/phpcs --version &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} PHP_CodeSniffer is not installed"
    echo "  Run: ddev composer require --dev drupal/coder"
    exit 1
fi

mkdir -p "${REPORT_DIR}/lint"

# =====================
# Resolve what to scan: modules AND themes, minus whatever is not there.
# =====================
# The existence filter is not tidiness. phpcs aborts the WHOLE run when any argument
# path does not exist — it prints `ERROR: The file "..." does not exist.` on stderr,
# writes nothing to stdout and exits 3. With `--report=json > phpcs.json` that leaves an
# empty file, `jq '.totals.errors // 0'` on an empty file fails, `|| echo "0"` turns the
# failure into a zero, and the gate prints [PASS]. So simply appending a themes path that
# some layouts do not have would not merely skip themes, it would report a CLEAN TREE
# while scanning neither themes nor modules. Adding coverage must not be able to remove
# the coverage that already worked.
#
# `-e`, not `-d`: the documented override (references/scope-targeting.md) points these
# variables at a single module or theme directory, and phpcs accepts a plain file too.
#
# Checked on the HOST while phpcs runs in the CONTAINER. Equivalent in practice — DDEV
# mounts the project root and these are project-relative paths — and the script already
# assumes cwd is the project root (REPORT_DIR is relative). Run from elsewhere, the
# paths resolve nowhere, and the result is the loud "skipped" below rather than a pass.
SCAN_PATHS=()
MISSING_PATHS=()
for candidate in "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}"; do
    [ -n "$candidate" ] || continue
    if [ -e "$candidate" ]; then
        SCAN_PATHS+=("$candidate")
    else
        MISSING_PATHS+=("$candidate")
        echo -e "${YELLOW}[SKIP]${NC} ${candidate} does not exist — not scanned"
    fi
done

# Nothing to hand phpcs. Reported as "skipped", never as a pass: a run that examined no
# files found zero violations by not looking, which is the exact false clean this gate is
# supposed to catch in the code it scans.
if [ "${#SCAN_PATHS[@]}" -eq 0 ]; then
    echo ""
    echo -e "${YELLOW}[SKIP]${NC} No lintable paths exist — coding standards were not checked"
    echo "  Looked for: ${DRUPAL_MODULES_PATH}, ${DRUPAL_THEMES_PATH}"
    echo "  Override with DRUPAL_MODULES_PATH / DRUPAL_THEMES_PATH."
    cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "standards": ["Drupal", "DrupalPractice"],
  "paths": [],
  "paths_missing": $(printf '%s\n' "${MISSING_PATHS[@]}" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]'),
  "errors": 0,
  "warnings": 0,
  "status": "skipped",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    exit 0
fi

SCAN_PATHS_JSON=$(printf '%s\n' "${SCAN_PATHS[@]}" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
MISSING_PATHS_JSON=$(printf '%s\n' "${MISSING_PATHS[@]+"${MISSING_PATHS[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

# Initialize counters
ERRORS=0
WARNINGS=0

# Parse command line arguments
FIX_MODE=false
if [ "$1" == "--fix" ]; then
    FIX_MODE=true
fi

if [ "$FIX_MODE" == true ]; then
    echo "Running phpcbf (auto-fix mode)..."
    echo ""

    set +e
    ddev exec vendor/bin/phpcbf \
        --standard=Drupal,DrupalPractice \
        "${SCAN_PATHS[@]}" \
        2>&1 | tee "${REPORT_DIR}/lint/phpcbf.txt"
    PHPCBF_EXIT=$?
    set -e

    echo ""
    if [ "$PHPCBF_EXIT" -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} All fixable issues corrected"
    elif [ "$PHPCBF_EXIT" -eq 1 ]; then
        echo -e "${GREEN}[OK]${NC} Some issues were fixed, re-run to check remaining"
    else
        echo -e "${YELLOW}[WARN]${NC} Some issues could not be auto-fixed"
    fi
else
    echo "Running phpcs (check mode)..."
    echo "  Standards: Drupal, DrupalPractice"
    echo "  Paths: ${SCAN_PATHS[*]}"
    echo ""

    # Run phpcs with JSON output
    set +e
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=json \
        "${SCAN_PATHS[@]}" \
        2>/dev/null > "${REPORT_DIR}/lint/phpcs.json"
    PHPCS_EXIT=$?
    set -e

    # Also generate human-readable output
    set +e
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=summary \
        "${SCAN_PATHS[@]}" \
        2>&1 | tee "${REPORT_DIR}/lint/phpcs-summary.txt"
    set -e

    # Parse JSON for counts
    if [ -f "${REPORT_DIR}/lint/phpcs.json" ] && command -v jq &> /dev/null; then
        ERRORS=$(jq '.totals.errors // 0' "${REPORT_DIR}/lint/phpcs.json" 2>/dev/null || echo "0")
        WARNINGS=$(jq '.totals.warnings // 0' "${REPORT_DIR}/lint/phpcs.json" 2>/dev/null || echo "0")
    fi

    # A count that is not a number is not a count of zero.
    #
    # `|| echo "0"` never fires on an empty report: jq exits 0 on empty input, it just
    # emits nothing, so ERRORS becomes the EMPTY STRING. `[ "" -gt 0 ]` then aborts with
    # "integer expression expected", `if` swallows that as false, the status falls through
    # to "pass", and the heredoc below writes `"errors": ,` — an unparseable report
    # asserting a clean tree. Observed, not theorised: it is exactly what this script did
    # on any missing scan path before the existence filter above, printing [PASS] and
    # exiting 0 having scanned nothing.
    #
    # The filter removes the common trigger; it cannot remove the rest. phpcs can still
    # produce an empty or truncated report by dying mid-run, and every one of those is a
    # scan that did not happen. So the counts are validated as integers and anything else
    # is reported as "skipped" — no finding was proved, and none was disproved either.
    PHPCS_USABLE=true
    if ! [[ "$ERRORS" =~ ^[0-9]+$ ]] || ! [[ "$WARNINGS" =~ ^[0-9]+$ ]]; then
        PHPCS_USABLE=false
        ERRORS=0
        WARNINGS=0
    fi

    # Determine status
    LINT_STATUS="pass"
    if [ "$PHPCS_USABLE" == false ]; then
        LINT_STATUS="skipped"
    elif [ "$ERRORS" -gt 0 ]; then
        LINT_STATUS="fail"
    elif [ "$WARNINGS" -gt 10 ]; then
        LINT_STATUS="warning"
    fi

    # Generate report
    cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "standards": ["Drupal", "DrupalPractice"],
  "paths": ${SCAN_PATHS_JSON},
  "paths_missing": ${MISSING_PATHS_JSON},
  "errors": ${ERRORS},
  "warnings": ${WARNINGS},
  "status": "${LINT_STATUS}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    echo ""
    echo "=== Summary ==="
    echo "  Errors:   ${ERRORS}"
    echo "  Warnings: ${WARNINGS}"
    echo ""

    if [ "$LINT_STATUS" == "skipped" ]; then
        # Exit 0, like the other no-result paths: the gate has no finding to report and
        # no clean tree to certify either. The consequence is carried by the status, not
        # by a changed exit-code contract.
        echo -e "${YELLOW}[SKIP]${NC} phpcs produced no usable report — coding standards were NOT verified"
        exit 0
    elif [ "$LINT_STATUS" == "pass" ]; then
        echo -e "${GREEN}[PASS]${NC} Coding standards check passed"
        exit 0
    elif [ "$LINT_STATUS" == "warning" ]; then
        echo -e "${YELLOW}[WARN]${NC} Some warnings found"
        echo ""
        echo "To auto-fix, run:"
        echo "  scripts/drupal/lint-check.sh --fix"
        exit 1
    else
        echo -e "${RED}[FAIL]${NC} Coding standards violations found"
        echo ""
        echo "To auto-fix, run:"
        echo "  scripts/drupal/lint-check.sh --fix"
        exit 2
    fi
fi
