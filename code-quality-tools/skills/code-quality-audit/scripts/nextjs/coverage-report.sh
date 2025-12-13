#!/bin/bash
# coverage-report.sh - Run Jest with coverage for Next.js projects
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"
COVERAGE_MINIMUM="${COVERAGE_MINIMUM:-70}"
COVERAGE_TARGET="${COVERAGE_TARGET:-80}"

echo "=== Jest Coverage Report ==="
echo ""

# Check for npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} npm is not installed"
    exit 2
fi

# Check for Jest
if ! npx jest --version &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Jest is not installed"
    echo "  Run: npm install -D jest @jest/globals"
    exit 1
fi

mkdir -p "${REPORT_DIR}/coverage"

echo "Running Jest with coverage..."
echo "  Minimum: ${COVERAGE_MINIMUM}%"
echo "  Target: ${COVERAGE_TARGET}%"
echo ""

# Run Jest with coverage
set +e
npx jest --coverage \
    --coverageReporters=json-summary \
    --coverageReporters=text \
    --coverageDirectory="${REPORT_DIR}/coverage" \
    2>&1 | tee "${REPORT_DIR}/coverage/jest-output.txt"
JEST_EXIT=$?
set -e

# Parse coverage from json-summary
COVERAGE_FILE="${REPORT_DIR}/coverage/coverage-summary.json"
LINE_COVERAGE=0
BRANCH_COVERAGE=0
FUNCTION_COVERAGE=0

if [ -f "$COVERAGE_FILE" ] && command -v jq &> /dev/null; then
    LINE_COVERAGE=$(jq '.total.lines.pct // 0' "$COVERAGE_FILE" 2>/dev/null || echo "0")
    BRANCH_COVERAGE=$(jq '.total.branches.pct // 0' "$COVERAGE_FILE" 2>/dev/null || echo "0")
    FUNCTION_COVERAGE=$(jq '.total.functions.pct // 0' "$COVERAGE_FILE" 2>/dev/null || echo "0")
fi

echo ""

# Determine status based on line coverage
COVERAGE_STATUS="pass"
if (( $(echo "$LINE_COVERAGE < $COVERAGE_MINIMUM" | bc -l) )); then
    COVERAGE_STATUS="fail"
elif (( $(echo "$LINE_COVERAGE < $COVERAGE_TARGET" | bc -l) )); then
    COVERAGE_STATUS="warning"
fi

# Generate report
cat > "${REPORT_DIR}/coverage-report.json" << EOF
{
  "line_coverage": ${LINE_COVERAGE},
  "branch_coverage": ${BRANCH_COVERAGE},
  "function_coverage": ${FUNCTION_COVERAGE},
  "thresholds": {
    "minimum": ${COVERAGE_MINIMUM},
    "target": ${COVERAGE_TARGET}
  },
  "status": "${COVERAGE_STATUS}",
  "tests_passed": $([ "$JEST_EXIT" -eq 0 ] && echo "true" || echo "false"),
  "generated_at": "$(date -Iseconds)"
}
EOF

echo "=== Coverage Summary ==="
echo "  Lines:     ${LINE_COVERAGE}%"
echo "  Branches:  ${BRANCH_COVERAGE}%"
echo "  Functions: ${FUNCTION_COVERAGE}%"
echo ""

if [ "$JEST_EXIT" -ne 0 ]; then
    echo -e "${RED}[FAIL]${NC} Some tests failed"
    exit 2
fi

case "$COVERAGE_STATUS" in
    pass)
        echo -e "${GREEN}[PASS]${NC} Coverage meets target (>${COVERAGE_TARGET}%)"
        exit 0
        ;;
    warning)
        echo -e "${YELLOW}[WARN]${NC} Coverage below target (${COVERAGE_TARGET}%) but above minimum (${COVERAGE_MINIMUM}%)"
        exit 1
        ;;
    fail)
        echo -e "${RED}[FAIL]${NC} Coverage below minimum (${COVERAGE_MINIMUM}%)"
        exit 2
        ;;
esac
