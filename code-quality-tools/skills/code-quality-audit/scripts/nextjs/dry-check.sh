#!/bin/bash
# dry-check.sh - Check for code duplication in Next.js projects using jscpd
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"
DUPLICATION_MAX="${DUPLICATION_MAX:-5}"
DUPLICATION_WARN="${DUPLICATION_WARN:-10}"

echo "=== Code Duplication Check (jscpd) ==="
echo ""

# Check for npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} npm is not installed"
    exit 2
fi

# Check for jscpd
if ! npx jscpd --version &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} jscpd is not installed"
    echo "  Run: npm install -D jscpd"
    exit 1
fi

mkdir -p "${REPORT_DIR}/dry"

echo "Scanning for duplicate code..."
echo "  Max acceptable: ${DUPLICATION_MAX}%"
echo "  Warning threshold: ${DUPLICATION_WARN}%"
echo ""

# Determine source paths
SOURCE_PATHS=""
if [ -d "src" ]; then
    SOURCE_PATHS="src"
elif [ -d "app" ]; then
    SOURCE_PATHS="app"
elif [ -d "pages" ]; then
    SOURCE_PATHS="pages"
else
    SOURCE_PATHS="."
fi

# Run jscpd
set +e
npx jscpd ${SOURCE_PATHS} \
    --reporters json \
    --output "${REPORT_DIR}/dry" \
    --min-lines 10 \
    --min-tokens 50 \
    --ignore "**/*.test.*,**/*.spec.*,**/node_modules/**,**/.next/**,**/dist/**" \
    2>&1 | tee "${REPORT_DIR}/dry/jscpd-output.txt"
JSCPD_EXIT=$?
set -e

# Parse results
JSCPD_JSON="${REPORT_DIR}/dry/jscpd-report.json"
DUPLICATION_PCT=0
CLONES_COUNT=0
DUPLICATED_LINES=0
TOTAL_LINES=0

if [ -f "$JSCPD_JSON" ] && command -v jq &> /dev/null; then
    DUPLICATION_PCT=$(jq '.statistics.total.percentage // 0' "$JSCPD_JSON" 2>/dev/null || echo "0")
    CLONES_COUNT=$(jq '.statistics.total.clones // 0' "$JSCPD_JSON" 2>/dev/null || echo "0")
    DUPLICATED_LINES=$(jq '.statistics.total.duplicatedLines // 0' "$JSCPD_JSON" 2>/dev/null || echo "0")
    TOTAL_LINES=$(jq '.statistics.total.lines // 0' "$JSCPD_JSON" 2>/dev/null || echo "0")
fi

echo ""

# Determine status
DRY_STATUS="pass"
if (( $(echo "$DUPLICATION_PCT > $DUPLICATION_WARN" | bc -l) )); then
    DRY_STATUS="fail"
elif (( $(echo "$DUPLICATION_PCT > $DUPLICATION_MAX" | bc -l) )); then
    DRY_STATUS="warning"
fi

# Generate report
cat > "${REPORT_DIR}/dry-report.json" << EOF
{
  "duplication_percentage": ${DUPLICATION_PCT},
  "clones_count": ${CLONES_COUNT},
  "duplicated_lines": ${DUPLICATED_LINES},
  "total_lines": ${TOTAL_LINES},
  "thresholds": {
    "max_acceptable": ${DUPLICATION_MAX},
    "warning": ${DUPLICATION_WARN}
  },
  "status": "${DRY_STATUS}",
  "generated_at": "$(date -Iseconds)"
}
EOF

echo "=== Duplication Summary ==="
echo "  Duplication: ${DUPLICATION_PCT}%"
echo "  Clones found: ${CLONES_COUNT}"
echo "  Duplicated lines: ${DUPLICATED_LINES} / ${TOTAL_LINES}"
echo ""

# Apply Rule of Three guidance
if [ "$CLONES_COUNT" -gt 0 ]; then
    echo "=== Rule of Three Guidance ==="
    echo "  Before extracting duplicates, consider:"
    echo "  - Is this the 3rd+ occurrence? (If <3, duplication may be OK)"
    echo "  - Is this knowledge duplication or coincidental similarity?"
    echo "  - Will these change together for the same reason?"
    echo "  - Is the abstraction clear or would it be forced?"
    echo ""
fi

case "$DRY_STATUS" in
    pass)
        echo -e "${GREEN}[PASS]${NC} Duplication is acceptable (<${DUPLICATION_MAX}%)"
        exit 0
        ;;
    warning)
        echo -e "${YELLOW}[WARN]${NC} Duplication above target but below critical (${DUPLICATION_MAX}%-${DUPLICATION_WARN}%)"
        exit 1
        ;;
    fail)
        echo -e "${RED}[FAIL]${NC} Duplication exceeds threshold (>${DUPLICATION_WARN}%)"
        exit 2
        ;;
esac
