#!/bin/bash
# coverage-report.sh - Run PHPUnit with PCOV coverage
# Part of code-quality-audit skill

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

echo "=== Coverage Analysis (PHPUnit + PCOV) ==="
echo ""

# Check DDEV
if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
    exit 2
fi

# Check for PCOV
PCOV_AVAILABLE=$(ddev exec php -m 2>/dev/null | grep -c pcov || echo "0")
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
echo ""

# Build PHPUnit command
PHPUNIT_CMD="php ${PCOV_FLAGS} vendor/bin/phpunit"
PHPUNIT_CMD+=" --testsuite unit,kernel"
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
TESTS_TOTAL=$(echo "$COVERAGE_OUTPUT" | grep -oP 'Tests:\s*\K\d+' | head -1 || echo "0")
TESTS_PASSED=$(echo "$COVERAGE_OUTPUT" | grep -oP 'OK \(\K\d+' | head -1 || echo "$TESTS_TOTAL")
TESTS_FAILED=$(echo "$COVERAGE_OUTPUT" | grep -oP 'Failures:\s*\K\d+' | head -1 || echo "0")

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
