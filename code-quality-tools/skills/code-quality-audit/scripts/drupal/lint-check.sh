#!/bin/bash
# lint-check.sh - Run PHP coding standards checks (Drupal, DrupalPractice)
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"
DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"

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
  "generated_at": "$(date -Iseconds)"
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
  "generated_at": "$(date -Iseconds)"
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
        "${DRUPAL_MODULES_PATH}" \
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
    echo "  Path: ${DRUPAL_MODULES_PATH}"
    echo ""

    # Run phpcs with JSON output
    set +e
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=json \
        "${DRUPAL_MODULES_PATH}" \
        2>/dev/null > "${REPORT_DIR}/lint/phpcs.json"
    PHPCS_EXIT=$?
    set -e

    # Also generate human-readable output
    set +e
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=summary \
        "${DRUPAL_MODULES_PATH}" \
        2>&1 | tee "${REPORT_DIR}/lint/phpcs-summary.txt"
    set -e

    # Parse JSON for counts
    if [ -f "${REPORT_DIR}/lint/phpcs.json" ] && command -v jq &> /dev/null; then
        ERRORS=$(jq '.totals.errors // 0' "${REPORT_DIR}/lint/phpcs.json" 2>/dev/null || echo "0")
        WARNINGS=$(jq '.totals.warnings // 0' "${REPORT_DIR}/lint/phpcs.json" 2>/dev/null || echo "0")
    fi

    # Determine status
    LINT_STATUS="pass"
    if [ "$ERRORS" -gt 0 ]; then
        LINT_STATUS="fail"
    elif [ "$WARNINGS" -gt 10 ]; then
        LINT_STATUS="warning"
    fi

    # Generate report
    cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "standards": ["Drupal", "DrupalPractice"],
  "path": "${DRUPAL_MODULES_PATH}",
  "errors": ${ERRORS},
  "warnings": ${WARNINGS},
  "status": "${LINT_STATUS}",
  "generated_at": "$(date -Iseconds)"
}
EOF

    echo ""
    echo "=== Summary ==="
    echo "  Errors:   ${ERRORS}"
    echo "  Warnings: ${WARNINGS}"
    echo ""

    if [ "$LINT_STATUS" == "pass" ]; then
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
