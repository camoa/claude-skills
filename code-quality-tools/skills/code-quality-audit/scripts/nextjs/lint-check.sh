#!/bin/bash
# lint-check.sh - Run ESLint and TypeScript checks for Next.js projects
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"

echo "=== ESLint + TypeScript Check ==="
echo ""

# Check for npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} npm is not installed"
    exit 2
fi

mkdir -p "${REPORT_DIR}/lint"

# Initialize counters
ESLINT_ERRORS=0
ESLINT_WARNINGS=0
TS_ERRORS=0

# Parse command line arguments
FIX_MODE=false
if [ "$1" == "--fix" ]; then
    FIX_MODE=true
fi

# =====================
# ESLint Check
# =====================
echo "Running ESLint..."

if [ "$FIX_MODE" == true ]; then
    set +e
    npx eslint . --fix 2>&1 | tee "${REPORT_DIR}/lint/eslint-fix.txt"
    ESLINT_EXIT=$?
    set -e
    echo ""
else
    # Run ESLint with JSON output
    set +e
    npx eslint . --format json --output-file "${REPORT_DIR}/lint/eslint.json" 2>/dev/null
    ESLINT_EXIT=$?
    set -e

    # Also generate human-readable output
    set +e
    npx eslint . 2>&1 | tee "${REPORT_DIR}/lint/eslint.txt"
    set -e

    # Parse JSON for counts
    if [ -f "${REPORT_DIR}/lint/eslint.json" ] && command -v jq &> /dev/null; then
        ESLINT_ERRORS=$(jq '[.[].errorCount] | add // 0' "${REPORT_DIR}/lint/eslint.json" 2>/dev/null || echo "0")
        ESLINT_WARNINGS=$(jq '[.[].warningCount] | add // 0' "${REPORT_DIR}/lint/eslint.json" 2>/dev/null || echo "0")
    fi
fi

echo ""

# =====================
# TypeScript Check
# =====================
echo "Running TypeScript type check..."

if [ -f "tsconfig.json" ]; then
    set +e
    npx tsc --noEmit 2>&1 | tee "${REPORT_DIR}/lint/typescript.txt"
    TS_EXIT=$?
    set -e

    # Count TypeScript errors
    if [ -f "${REPORT_DIR}/lint/typescript.txt" ]; then
        TS_ERRORS=$(grep -c "error TS" "${REPORT_DIR}/lint/typescript.txt" 2>/dev/null || echo "0")
    fi

    if [ "$TS_EXIT" -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} TypeScript: No type errors"
    else
        echo -e "${RED}[FAIL]${NC} TypeScript: ${TS_ERRORS} type errors"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} No tsconfig.json found"
    TS_ERRORS=0
fi

echo ""

# =====================
# Summary
# =====================
if [ "$FIX_MODE" == false ]; then
    # Determine overall status
    LINT_STATUS="pass"
    if [ "$ESLINT_ERRORS" -gt 0 ] || [ "$TS_ERRORS" -gt 0 ]; then
        LINT_STATUS="fail"
    elif [ "$ESLINT_WARNINGS" -gt 20 ]; then
        LINT_STATUS="warning"
    fi

    # Generate report
    cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "eslint": {
    "errors": ${ESLINT_ERRORS},
    "warnings": ${ESLINT_WARNINGS}
  },
  "typescript": {
    "errors": ${TS_ERRORS}
  },
  "status": "${LINT_STATUS}",
  "generated_at": "$(date -Iseconds)"
}
EOF

    echo "=== Summary ==="
    echo "  ESLint errors:   ${ESLINT_ERRORS}"
    echo "  ESLint warnings: ${ESLINT_WARNINGS}"
    echo "  TypeScript errors: ${TS_ERRORS}"
    echo ""

    if [ "$LINT_STATUS" == "pass" ]; then
        echo -e "${GREEN}[PASS]${NC} Lint check passed"
        exit 0
    elif [ "$LINT_STATUS" == "warning" ]; then
        echo -e "${YELLOW}[WARN]${NC} Some warnings found"
        echo ""
        echo "To auto-fix ESLint issues, run:"
        echo "  scripts/nextjs/lint-check.sh --fix"
        exit 1
    else
        echo -e "${RED}[FAIL]${NC} Lint errors found"
        echo ""
        echo "To auto-fix ESLint issues, run:"
        echo "  scripts/nextjs/lint-check.sh --fix"
        exit 2
    fi
else
    echo -e "${GREEN}[OK]${NC} ESLint auto-fix completed"
    echo "Re-run without --fix to check remaining issues"
fi
