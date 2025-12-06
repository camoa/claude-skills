#!/bin/bash
# full-audit.sh - Run complete code quality audit
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
REPORT_DIR="${REPORT_DIR:-./reports/quality}"

# Thresholds (can be overridden via environment)
COVERAGE_MINIMUM="${COVERAGE_MINIMUM:-70}"
COVERAGE_TARGET="${COVERAGE_TARGET:-80}"
DUPLICATION_MAX="${DUPLICATION_MAX:-5}"
COMPLEXITY_MAX="${COMPLEXITY_MAX:-10}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Code Quality Audit - Full Analysis                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Track overall status
OVERALL_STATUS="pass"
CRITICAL_COUNT=0
WARNING_COUNT=0
SUGGESTION_COUNT=0

# Helper to update status
update_status() {
    local check_status="$1"
    case "$check_status" in
        fail)
            OVERALL_STATUS="fail"
            ;;
        warning)
            if [ "$OVERALL_STATUS" != "fail" ]; then
                OVERALL_STATUS="warning"
            fi
            ;;
    esac
}

# Step 1: Detect environment
echo -e "${BLUE}[Step 1/5]${NC} Detecting environment..."
if ! "${SCRIPT_DIR}/detect-environment.sh" > /dev/null 2>&1; then
    if ! "${SCRIPT_DIR}/detect-environment.sh"; then
        echo -e "${RED}[ERROR]${NC} Environment detection failed"
        exit 2
    fi
fi

# Load environment
if [ -f "${REPORT_DIR}/environment.json" ]; then
    PROJECT_TYPE=$(grep -oP '"project_type":\s*"\K[^"]+' "${REPORT_DIR}/environment.json")
    DRUPAL_MODULES_PATH=$(grep -oP '"drupal_modules_path":\s*"\K[^"]+' "${REPORT_DIR}/environment.json")
else
    echo -e "${RED}[ERROR]${NC} Environment file not found"
    exit 2
fi

echo -e "${GREEN}[OK]${NC} Project type: ${PROJECT_TYPE}"
echo ""

# Step 2: Check/install tools
echo -e "${BLUE}[Step 2/5]${NC} Verifying tools..."
if ! ddev exec vendor/bin/phpstan --version &> /dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Installing missing tools..."
    "${SCRIPT_DIR}/install-tools.sh" || true
fi
echo -e "${GREEN}[OK]${NC} Tools available"
echo ""

# Initialize aggregated report
TIMESTAMP=$(date -Iseconds)
cat > "${REPORT_DIR}/audit-report.json" << EOF
{
  "meta": {
    "project_type": "${PROJECT_TYPE}",
    "project_path": "$(pwd)",
    "timestamp": "${TIMESTAMP}",
    "tool_versions": {},
    "thresholds": {
      "coverage_minimum": ${COVERAGE_MINIMUM},
      "coverage_target": ${COVERAGE_TARGET},
      "duplication_max": ${DUPLICATION_MAX},
      "complexity_max": ${COMPLEXITY_MAX}
    }
  },
  "summary": {
    "overall_score": "pass",
    "coverage_score": "unknown",
    "solid_score": "unknown",
    "dry_score": "unknown",
    "critical_issues": 0,
    "warnings": 0,
    "suggestions": 0
  },
  "coverage": {},
  "solid": {"violations": [], "metrics": {}},
  "dry": {"clones": []},
  "tdd": {},
  "recommendations": []
}
EOF

# Step 3: Run coverage check
echo -e "${BLUE}[Step 3/5]${NC} Running coverage analysis..."
COVERAGE_STATUS="unknown"
if [ -f "${SKILL_DIR}/drupal/coverage-report.sh" ]; then
    if "${SKILL_DIR}/drupal/coverage-report.sh" 2>/dev/null; then
        COVERAGE_STATUS="pass"
    else
        exit_code=$?
        if [ $exit_code -eq 1 ]; then
            COVERAGE_STATUS="warning"
            ((WARNING_COUNT++))
        else
            COVERAGE_STATUS="fail"
            ((CRITICAL_COUNT++))
        fi
    fi
    update_status "$COVERAGE_STATUS"

    # Merge coverage report
    if [ -f "${REPORT_DIR}/coverage-report.json" ]; then
        jq -s '.[0] * {coverage: .[1]}' \
            "${REPORT_DIR}/audit-report.json" \
            "${REPORT_DIR}/coverage-report.json" \
            > "${REPORT_DIR}/audit-report.tmp.json"
        mv "${REPORT_DIR}/audit-report.tmp.json" "${REPORT_DIR}/audit-report.json"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} Coverage script not found"
fi
echo -e "Coverage: $([ "$COVERAGE_STATUS" == "pass" ] && echo "${GREEN}PASS${NC}" || echo "${YELLOW}${COVERAGE_STATUS}${NC}")"
echo ""

# Step 4: Run SOLID check
echo -e "${BLUE}[Step 4/5]${NC} Running SOLID analysis..."
SOLID_STATUS="unknown"
if [ -f "${SKILL_DIR}/drupal/solid-check.sh" ]; then
    if "${SKILL_DIR}/drupal/solid-check.sh" 2>/dev/null; then
        SOLID_STATUS="pass"
    else
        exit_code=$?
        if [ $exit_code -eq 1 ]; then
            SOLID_STATUS="warning"
            ((WARNING_COUNT++))
        else
            SOLID_STATUS="fail"
            ((CRITICAL_COUNT++))
        fi
    fi
    update_status "$SOLID_STATUS"

    # Merge SOLID report
    if [ -f "${REPORT_DIR}/solid-report.json" ]; then
        jq -s '.[0] * {solid: .[1]}' \
            "${REPORT_DIR}/audit-report.json" \
            "${REPORT_DIR}/solid-report.json" \
            > "${REPORT_DIR}/audit-report.tmp.json"
        mv "${REPORT_DIR}/audit-report.tmp.json" "${REPORT_DIR}/audit-report.json"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} SOLID script not found"
fi
echo -e "SOLID: $([ "$SOLID_STATUS" == "pass" ] && echo "${GREEN}PASS${NC}" || echo "${YELLOW}${SOLID_STATUS}${NC}")"
echo ""

# Step 5: Run DRY check
echo -e "${BLUE}[Step 5/5]${NC} Running DRY analysis..."
DRY_STATUS="unknown"
if [ -f "${SKILL_DIR}/drupal/dry-check.sh" ]; then
    if "${SKILL_DIR}/drupal/dry-check.sh" 2>/dev/null; then
        DRY_STATUS="pass"
    else
        exit_code=$?
        if [ $exit_code -eq 1 ]; then
            DRY_STATUS="warning"
            ((WARNING_COUNT++))
        else
            DRY_STATUS="fail"
            ((CRITICAL_COUNT++))
        fi
    fi
    update_status "$DRY_STATUS"

    # Merge DRY report
    if [ -f "${REPORT_DIR}/dry-report.json" ]; then
        jq -s '.[0] * {dry: .[1]}' \
            "${REPORT_DIR}/audit-report.json" \
            "${REPORT_DIR}/dry-report.json" \
            > "${REPORT_DIR}/audit-report.tmp.json"
        mv "${REPORT_DIR}/audit-report.tmp.json" "${REPORT_DIR}/audit-report.json"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} DRY script not found"
fi
echo -e "DRY: $([ "$DRY_STATUS" == "pass" ] && echo "${GREEN}PASS${NC}" || echo "${YELLOW}${DRY_STATUS}${NC}")"
echo ""

# Update summary in report
jq --arg overall "$OVERALL_STATUS" \
   --arg coverage "$COVERAGE_STATUS" \
   --arg solid "$SOLID_STATUS" \
   --arg dry "$DRY_STATUS" \
   --argjson critical "$CRITICAL_COUNT" \
   --argjson warnings "$WARNING_COUNT" \
   --argjson suggestions "$SUGGESTION_COUNT" \
   '.summary.overall_score = $overall |
    .summary.coverage_score = $coverage |
    .summary.solid_score = $solid |
    .summary.dry_score = $dry |
    .summary.critical_issues = $critical |
    .summary.warnings = $warnings |
    .summary.suggestions = $suggestions' \
   "${REPORT_DIR}/audit-report.json" > "${REPORT_DIR}/audit-report.tmp.json"
mv "${REPORT_DIR}/audit-report.tmp.json" "${REPORT_DIR}/audit-report.json"

# Generate Markdown report
echo "Generating Markdown report..."
"${SCRIPT_DIR}/report-processor.sh" "${REPORT_DIR}/audit-report.json" "${REPORT_DIR}/audit-report.md"

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                      Audit Summary                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Coverage:  ${COVERAGE_STATUS}"
echo "  SOLID:     ${SOLID_STATUS}"
echo "  DRY:       ${DRY_STATUS}"
echo ""
echo "  Critical:  ${CRITICAL_COUNT}"
echo "  Warnings:  ${WARNING_COUNT}"
echo ""
echo -e "  Overall:   $([ "$OVERALL_STATUS" == "pass" ] && echo "${GREEN}PASS${NC}" || ([ "$OVERALL_STATUS" == "warning" ] && echo "${YELLOW}WARNING${NC}" || echo "${RED}FAIL${NC}"))"
echo ""
echo "  Reports:"
echo "    JSON: ${REPORT_DIR}/audit-report.json"
echo "    Markdown: ${REPORT_DIR}/audit-report.md"
echo ""

# Exit with appropriate code
case "$OVERALL_STATUS" in
    pass) exit 0 ;;
    warning) exit 1 ;;
    fail) exit 2 ;;
esac
