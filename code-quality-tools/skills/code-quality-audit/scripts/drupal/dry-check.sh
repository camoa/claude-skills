#!/bin/bash
# dry-check.sh - Run PHPCPD duplication analysis
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-./reports/quality}"
DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"
DUPLICATION_MAX="${DUPLICATION_MAX:-5}"

# PHPCPD settings
MIN_LINES="${PHPCPD_MIN_LINES:-10}"
MIN_TOKENS="${PHPCPD_MIN_TOKENS:-70}"

echo "=== DRY Analysis (PHPCPD) ==="
echo ""

# Check DDEV
if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
    exit 2
fi

# Check for PHPCPD
if ! ddev exec vendor/bin/phpcpd --version &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} PHPCPD not found"
    echo "  Install with: ddev composer require --dev systemsdk/phpcpd"
    exit 2
fi

# Get PHPCPD version
PHPCPD_VERSION=$(ddev exec vendor/bin/phpcpd --version 2>/dev/null | head -1 || echo "unknown")
echo "PHPCPD version: ${PHPCPD_VERSION}"
echo "Min lines: ${MIN_LINES}, Min tokens: ${MIN_TOKENS}"
echo ""

# Create temp file for output
PHPCPD_OUTPUT="${REPORT_DIR}/dry/phpcpd-output.txt"
mkdir -p "${REPORT_DIR}/dry"

# Run PHPCPD
echo "Scanning for code duplication..."
set +e
ddev exec vendor/bin/phpcpd \
    --min-lines="${MIN_LINES}" \
    --min-tokens="${MIN_TOKENS}" \
    --exclude=tests \
    --exclude=Test \
    "${DRUPAL_MODULES_PATH}" \
    2>&1 > "$PHPCPD_OUTPUT"
PHPCPD_EXIT=$?
set -e

# Parse output
cat "$PHPCPD_OUTPUT"
echo ""

# Extract metrics from output
# PHPCPD output format:
# "Found X clones with Y duplicated lines in Z files"
# "A.B% duplicated lines out of C total lines of code"

CLONE_COUNT=$(grep -oP 'Found \K\d+' "$PHPCPD_OUTPUT" 2>/dev/null || echo "0")
DUPLICATED_LINES=$(grep -oP '\K\d+(?= duplicated lines)' "$PHPCPD_OUTPUT" 2>/dev/null || echo "0")
TOTAL_LINES=$(grep -oP '\K\d+(?= total lines)' "$PHPCPD_OUTPUT" 2>/dev/null || echo "0")
DUPLICATION_PCT=$(grep -oP '\K[\d.]+(?=% duplicated)' "$PHPCPD_OUTPUT" 2>/dev/null || echo "0")

# If percentage not found, calculate it
if [ "$DUPLICATION_PCT" == "0" ] && [ "$TOTAL_LINES" -gt 0 ]; then
    DUPLICATION_PCT=$(echo "scale=2; $DUPLICATED_LINES * 100 / $TOTAL_LINES" | bc 2>/dev/null || echo "0")
fi

echo "Summary:"
echo "  Clones found: ${CLONE_COUNT}"
echo "  Duplicated lines: ${DUPLICATED_LINES}"
echo "  Total lines: ${TOTAL_LINES}"
echo "  Duplication: ${DUPLICATION_PCT}%"
echo ""

# Parse individual clones
# PHPCPD clone format:
#   - /path/to/FileA.php:10-25 (15 lines)
#   - /path/to/FileB.php:30-45
CLONES_JSON="[]"
if [ "$CLONE_COUNT" -gt 0 ]; then
    # Simple extraction - get pairs of files
    CLONES_JSON=$(grep -A2 "^  -" "$PHPCPD_OUTPUT" 2>/dev/null | \
        grep -oP '/var/www/html/\K[^:]+:\d+-\d+' | \
        paste - - 2>/dev/null | \
        head -20 | \
        jq -R -s 'split("\n") | map(select(length > 0)) | map(split("\t") | {
            lines: 0,
            tokens: 0,
            files: [
                (.[0] | split(":") | {file: .[0], start_line: (.[1] | split("-")[0] | tonumber? // 0), end_line: (.[1] | split("-")[1] | tonumber? // 0)}),
                (.[1] | split(":") | {file: .[0], start_line: (.[1] | split("-")[0] | tonumber? // 0), end_line: (.[1] | split("-")[1] | tonumber? // 0)})
            ]
        })' 2>/dev/null || echo "[]")
fi

# Determine status based on thresholds
# <5% Excellent, 5-10% Acceptable, 10-15% Warning, >15% Critical
if (( $(echo "$DUPLICATION_PCT > 15" | bc -l 2>/dev/null || echo "0") )); then
    DRY_STATUS="fail"
    DRY_RATING="critical"
    echo -e "${RED}[FAIL]${NC} Duplication ${DUPLICATION_PCT}% is critical (>15%)"
elif (( $(echo "$DUPLICATION_PCT > 10" | bc -l 2>/dev/null || echo "0") )); then
    DRY_STATUS="warning"
    DRY_RATING="warning"
    echo -e "${YELLOW}[WARN]${NC} Duplication ${DUPLICATION_PCT}% needs attention (>10%)"
elif (( $(echo "$DUPLICATION_PCT > $DUPLICATION_MAX" | bc -l 2>/dev/null || echo "0") )); then
    DRY_STATUS="warning"
    DRY_RATING="acceptable"
    echo -e "${YELLOW}[WARN]${NC} Duplication ${DUPLICATION_PCT}% exceeds target ${DUPLICATION_MAX}%"
else
    DRY_STATUS="pass"
    DRY_RATING="excellent"
    echo -e "${GREEN}[PASS]${NC} Duplication ${DUPLICATION_PCT}% is excellent (<${DUPLICATION_MAX}%)"
fi

# Generate JSON report
cat > "${REPORT_DIR}/dry-report.json" << EOF
{
  "duplication_percentage": ${DUPLICATION_PCT},
  "total_lines": ${TOTAL_LINES},
  "duplicated_lines": ${DUPLICATED_LINES},
  "clone_count": ${CLONE_COUNT},
  "clones": ${CLONES_JSON},
  "rating": "${DRY_RATING}",
  "status": "${DRY_STATUS}",
  "settings": {
    "min_lines": ${MIN_LINES},
    "min_tokens": ${MIN_TOKENS}
  },
  "thresholds": {
    "excellent": 5,
    "acceptable": 10,
    "warning": 15,
    "target": ${DUPLICATION_MAX}
  },
  "generated_at": "$(date -Iseconds)"
}
EOF

echo ""
echo "Report saved: ${REPORT_DIR}/dry-report.json"

# Exit based on status
case "$DRY_STATUS" in
    pass) exit 0 ;;
    warning) exit 1 ;;
    fail) exit 2 ;;
esac
