#!/bin/bash
# solid-check.sh - Run SOLID principle checks (PHPStan, PHPMD, drupal-check)
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"
DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"
COMPLEXITY_MAX="${COMPLEXITY_MAX:-10}"

echo "=== SOLID Principles Analysis ==="
echo ""

# Parse command line arguments (before DDEV check so --changed can early-exit)
CHANGED_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --changed)
            shift
            CHANGED_FILE="$1"
            ;;
        *)
            ;;
    esac
    shift
done

# =====================
# --changed mode: scope phpstan + phpmd + \Drupal:: grep to listed files only
# =====================
if [ -n "$CHANGED_FILE" ]; then
    echo "[changed mode] Scoping SOLID tools to files listed in: ${CHANGED_FILE}"
    echo ""

    # PHP extensions only for SOLID tools
    LINTABLE_EXTS="\.php$|\.module$|\.inc$|\.install$|\.profile$|\.theme$|\.engine$"

    # Filter: keep PHP extensions, exclude vendor/core/contrib
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
        echo -e "${GREEN}[SKIP]${NC} No PHP files in the changed set — clean skip."
        mkdir -p "${REPORT_DIR}/solid"
        cat > "${REPORT_DIR}/solid-report.json" << EOF
{
  "violations": [],
  "metrics": {
    "total_violations": 0,
    "critical_count": 0,
    "warning_count": 0,
    "suggestion_count": 0,
    "static_drupal_calls": 0,
    "phpstan_errors": 0,
    "phpmd_violations": 0
  },
  "mode": "changed",
  "changed_file": "${CHANGED_FILE}",
  "relevant_files": 0,
  "status": "skipped",
  "thresholds": {
    "complexity_max": ${COMPLEXITY_MAX}
  },
  "generated_at": "$(date -Iseconds)"
}
EOF
        exit 0
    fi

    # Have files to analyse — now check DDEV availability
    if ! ddev describe &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} DDEV is not running"
        exit 2
    fi

    mkdir -p "${REPORT_DIR}/solid"

    # Initialize counters
    CRITICAL_COUNT=0
    WARNING_COUNT=0
    SUGGESTION_COUNT=0

    echo "Relevant files (${#RELEVANT_FILES[@]}):"
    printf '  %s\n' "${RELEVANT_FILES[@]}"
    echo ""

    # =====================
    # PHPStan Analysis (LSP, DIP) — changed files only
    # =====================
    echo "Running PHPStan (type safety, LSP, DIP)..."

    PHPSTAN_JSON="${REPORT_DIR}/solid/phpstan.json"
    set +e
    # shellcheck disable=SC2046
    ddev exec vendor/bin/phpstan analyse \
        "${RELEVANT_FILES[@]}" \
        --error-format=json \
        --no-progress \
        --memory-limit=1500M \
        2>/dev/null > "$PHPSTAN_JSON"
    PHPSTAN_EXIT=$?
    set -e

    PHPSTAN_ERRORS=0
    PHPSTAN_VIOLATIONS="[]"
    if [ -f "$PHPSTAN_JSON" ] && [ -s "$PHPSTAN_JSON" ]; then
        PHPSTAN_ERRORS=$(jq '.totals.errors // 0' "$PHPSTAN_JSON" 2>/dev/null || echo "0")
        echo "  PHPStan errors: ${PHPSTAN_ERRORS}"

        if [ "$PHPSTAN_ERRORS" -gt 0 ]; then
            PHPSTAN_VIOLATIONS=$(jq '[.files | to_entries[] | .key as $file | .value.messages[] | {
                principle: "LSP",
                severity: "warning",
                file: $file,
                line: .line,
                message: .message,
                metric: "phpstan",
                value: 1,
                threshold: 0
            }]' "$PHPSTAN_JSON" 2>/dev/null || echo "[]")

            WARNING_COUNT=$((WARNING_COUNT + PHPSTAN_ERRORS))
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} PHPStan output not available"
    fi

    # =====================
    # PHPMD Analysis (SRP) — changed files (comma-separated)
    # =====================
    echo "Running PHPMD (complexity, SRP)..."

    PHPMD_JSON="${REPORT_DIR}/solid/phpmd.json"
    # PHPMD takes a comma-separated list as the first positional arg
    PHPMD_TARGETS=$(IFS=,; echo "${RELEVANT_FILES[*]}")
    set +e
    ddev exec vendor/bin/phpmd \
        "$PHPMD_TARGETS" \
        json \
        cleancode,codesize,design,naming \
        --exclude "*/tests/*" \
        2>/dev/null > "$PHPMD_JSON"
    PHPMD_EXIT=$?
    set -e

    PHPMD_VIOLATIONS_COUNT=0
    PHPMD_VIOLATIONS="[]"
    if [ -f "$PHPMD_JSON" ] && [ -s "$PHPMD_JSON" ]; then
        PHPMD_VIOLATIONS_COUNT=$(jq '[.files[].violations[]] | length' "$PHPMD_JSON" 2>/dev/null || echo "0")
        echo "  PHPMD violations: ${PHPMD_VIOLATIONS_COUNT}"

        if [ "$PHPMD_VIOLATIONS_COUNT" -gt 0 ]; then
            PHPMD_VIOLATIONS=$(jq '[.files[] | .file as $file | .violations[] | {
                principle: (if .rule | test("Complexity|NPath|Methods") then "SRP" else "design" end),
                severity: (if .priority <= 2 then "critical" elif .priority <= 3 then "warning" else "suggestion" end),
                file: $file,
                line: .beginLine,
                message: .description,
                metric: .rule,
                value: (.priority // 3),
                threshold: 3
            }]' "$PHPMD_JSON" 2>/dev/null || echo "[]")

            PHPMD_CRITICAL=$(jq '[.files[].violations[] | select(.priority <= 2)] | length' "$PHPMD_JSON" 2>/dev/null || echo "0")
            PHPMD_WARNINGS=$(jq '[.files[].violations[] | select(.priority == 3)] | length' "$PHPMD_JSON" 2>/dev/null || echo "0")
            PHPMD_SUGGESTIONS=$(jq '[.files[].violations[] | select(.priority > 3)] | length' "$PHPMD_JSON" 2>/dev/null || echo "0")

            CRITICAL_COUNT=$((CRITICAL_COUNT + PHPMD_CRITICAL))
            WARNING_COUNT=$((WARNING_COUNT + PHPMD_WARNINGS))
            SUGGESTION_COUNT=$((SUGGESTION_COUNT + PHPMD_SUGGESTIONS))
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} PHPMD output not available"
    fi

    # =====================
    # Deprecation Detection — PHPStan handles this (already scoped above)
    # =====================
    echo "Deprecation detection: Handled by PHPStan (see phpstan-deprecation-rules)"

    # =====================
    # Check for static \Drupal:: calls (DIP violation) — changed files only
    # =====================
    echo "Checking for static \\Drupal:: calls (DIP)..."

    STATIC_CALLS=0
    STATIC_VIOLATIONS="[]"
    if [ "${#RELEVANT_FILES[@]}" -gt 0 ]; then
        STATIC_CALLS=$(ddev exec grep -l "\\\\Drupal::" "${RELEVANT_FILES[@]}" \
            2>/dev/null | wc -l || echo "0")

        if [ "$STATIC_CALLS" -gt 0 ]; then
            echo -e "  ${YELLOW}[WARN]${NC} Found ${STATIC_CALLS} files with static \\Drupal:: calls"
            WARNING_COUNT=$((WARNING_COUNT + STATIC_CALLS))

            STATIC_VIOLATIONS=$(ddev exec grep -n "\\\\Drupal::" "${RELEVANT_FILES[@]}" \
                2>/dev/null | head -20 | \
                jq -R -s 'split("\n") | map(select(length > 0)) | map(split(":") | {
                    principle: "DIP",
                    severity: "warning",
                    file: .[0],
                    line: (.[1] | tonumber? // 0),
                    message: "Static \\Drupal:: call - use dependency injection instead",
                    metric: "static_call",
                    value: 1,
                    threshold: 0
                })' 2>/dev/null || echo "[]")
        else
            echo -e "  ${GREEN}[OK]${NC} No static \\Drupal:: calls found"
        fi
    fi

    # Merge all violations
    ALL_VIOLATIONS=$(echo "$PHPSTAN_VIOLATIONS $PHPMD_VIOLATIONS $STATIC_VIOLATIONS" | \
        jq -s 'add | if . == null then [] else . end' 2>/dev/null || echo "[]")

    TOTAL_VIOLATIONS=$(echo "$ALL_VIOLATIONS" | jq 'length' 2>/dev/null || echo "0")

    # Determine overall status
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        SOLID_STATUS="fail"
        echo -e "${RED}[FAIL]${NC} Found ${CRITICAL_COUNT} critical SOLID violations"
    elif [ "$WARNING_COUNT" -gt 10 ]; then
        SOLID_STATUS="warning"
        echo -e "${YELLOW}[WARN]${NC} Found ${WARNING_COUNT} SOLID warnings"
    else
        SOLID_STATUS="pass"
        echo -e "${GREEN}[PASS]${NC} SOLID compliance acceptable"
    fi

    cat > "${REPORT_DIR}/solid-report.json" << EOF
{
  "violations": ${ALL_VIOLATIONS},
  "metrics": {
    "total_violations": ${TOTAL_VIOLATIONS},
    "critical_count": ${CRITICAL_COUNT},
    "warning_count": ${WARNING_COUNT},
    "suggestion_count": ${SUGGESTION_COUNT},
    "static_drupal_calls": ${STATIC_CALLS},
    "phpstan_errors": ${PHPSTAN_ERRORS},
    "phpmd_violations": ${PHPMD_VIOLATIONS_COUNT}
  },
  "mode": "changed",
  "changed_file": "${CHANGED_FILE}",
  "relevant_files": ${#RELEVANT_FILES[@]},
  "status": "${SOLID_STATUS}",
  "thresholds": {
    "complexity_max": ${COMPLEXITY_MAX}
  },
  "generated_at": "$(date -Iseconds)"
}
EOF

    echo ""
    echo "Report saved: ${REPORT_DIR}/solid-report.json"

    case "$SOLID_STATUS" in
        pass) exit 0 ;;
        warning) exit 1 ;;
        fail) exit 2 ;;
    esac
fi

# =====================
# Standard (no --changed) path — byte-identical to original logic
# =====================

# Check DDEV
if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
    exit 2
fi

# Initialize counters
CRITICAL_COUNT=0
WARNING_COUNT=0
SUGGESTION_COUNT=0
VIOLATIONS="[]"

# Create temp directory for individual reports
mkdir -p "${REPORT_DIR}/solid"

# =====================
# PHPStan Analysis (LSP, DIP)
# =====================
echo "Running PHPStan (type safety, LSP, DIP)..."

PHPSTAN_JSON="${REPORT_DIR}/solid/phpstan.json"
set +e
ddev exec vendor/bin/phpstan analyse \
    "${DRUPAL_MODULES_PATH}" \
    --error-format=json \
    --no-progress \
    --memory-limit=1500M \
    2>/dev/null > "$PHPSTAN_JSON"
PHPSTAN_EXIT=$?
set -e

if [ -f "$PHPSTAN_JSON" ] && [ -s "$PHPSTAN_JSON" ]; then
    PHPSTAN_ERRORS=$(jq '.totals.errors // 0' "$PHPSTAN_JSON" 2>/dev/null || echo "0")
    echo "  PHPStan errors: ${PHPSTAN_ERRORS}"

    # Convert PHPStan errors to violations
    if [ "$PHPSTAN_ERRORS" -gt 0 ]; then
        PHPSTAN_VIOLATIONS=$(jq '[.files | to_entries[] | .key as $file | .value.messages[] | {
            principle: "LSP",
            severity: "warning",
            file: $file,
            line: .line,
            message: .message,
            metric: "phpstan",
            value: 1,
            threshold: 0
        }]' "$PHPSTAN_JSON" 2>/dev/null || echo "[]")

        # Count by severity
        ((WARNING_COUNT += PHPSTAN_ERRORS))
    else
        PHPSTAN_VIOLATIONS="[]"
    fi
else
    echo -e "${YELLOW}[WARN]${NC} PHPStan output not available"
    PHPSTAN_VIOLATIONS="[]"
fi

# =====================
# PHPMD Analysis (SRP)
# =====================
echo "Running PHPMD (complexity, SRP)..."

PHPMD_JSON="${REPORT_DIR}/solid/phpmd.json"
set +e
ddev exec vendor/bin/phpmd \
    "${DRUPAL_MODULES_PATH}" \
    json \
    cleancode,codesize,design,naming \
    --exclude "*/tests/*" \
    2>/dev/null > "$PHPMD_JSON"
PHPMD_EXIT=$?
set -e

if [ -f "$PHPMD_JSON" ] && [ -s "$PHPMD_JSON" ]; then
    PHPMD_VIOLATIONS_COUNT=$(jq '[.files[].violations[]] | length' "$PHPMD_JSON" 2>/dev/null || echo "0")
    echo "  PHPMD violations: ${PHPMD_VIOLATIONS_COUNT}"

    if [ "$PHPMD_VIOLATIONS_COUNT" -gt 0 ]; then
        # Convert PHPMD violations
        PHPMD_VIOLATIONS=$(jq '[.files[] | .file as $file | .violations[] | {
            principle: (if .rule | test("Complexity|NPath|Methods") then "SRP" else "design" end),
            severity: (if .priority <= 2 then "critical" elif .priority <= 3 then "warning" else "suggestion" end),
            file: $file,
            line: .beginLine,
            message: .description,
            metric: .rule,
            value: (.priority // 3),
            threshold: 3
        }]' "$PHPMD_JSON" 2>/dev/null || echo "[]")

        # Count by severity
        PHPMD_CRITICAL=$(jq '[.files[].violations[] | select(.priority <= 2)] | length' "$PHPMD_JSON" 2>/dev/null || echo "0")
        PHPMD_WARNINGS=$(jq '[.files[].violations[] | select(.priority == 3)] | length' "$PHPMD_JSON" 2>/dev/null || echo "0")
        PHPMD_SUGGESTIONS=$(jq '[.files[].violations[] | select(.priority > 3)] | length' "$PHPMD_JSON" 2>/dev/null || echo "0")

        ((CRITICAL_COUNT += PHPMD_CRITICAL))
        ((WARNING_COUNT += PHPMD_WARNINGS))
        ((SUGGESTION_COUNT += PHPMD_SUGGESTIONS))
    else
        PHPMD_VIOLATIONS="[]"
    fi
else
    echo -e "${YELLOW}[WARN]${NC} PHPMD output not available"
    PHPMD_VIOLATIONS="[]"
fi

# =====================
# Deprecation Detection (via PHPStan)
# =====================
# Note: PHPStan with phpstan-deprecation-rules already handles deprecation detection.
# For auto-fixing deprecations, use rector-fix.sh with drupal-rector.
echo "Deprecation detection: Handled by PHPStan (see phpstan-deprecation-rules)"
echo "  For auto-fixes: Run rector-fix.sh"

# =====================
# Check for static Drupal:: calls (DIP violation)
# =====================
echo "Checking for static \\Drupal:: calls (DIP)..."

STATIC_CALLS=$(ddev exec grep -r "\\\\Drupal::" "${DRUPAL_MODULES_PATH}" \
    --include="*.php" \
    --exclude-dir="tests" \
    -l 2>/dev/null | wc -l || echo "0")

if [ "$STATIC_CALLS" -gt 0 ]; then
    echo -e "  ${YELLOW}[WARN]${NC} Found ${STATIC_CALLS} files with static \\Drupal:: calls"
    ((WARNING_COUNT += STATIC_CALLS))

    # Create DIP violations for static calls
    STATIC_VIOLATIONS=$(ddev exec grep -rn "\\\\Drupal::" "${DRUPAL_MODULES_PATH}" \
        --include="*.php" \
        --exclude-dir="tests" 2>/dev/null | head -20 | \
        jq -R -s 'split("\n") | map(select(length > 0)) | map(split(":") | {
            principle: "DIP",
            severity: "warning",
            file: .[0],
            line: (.[1] | tonumber? // 0),
            message: "Static \\Drupal:: call - use dependency injection instead",
            metric: "static_call",
            value: 1,
            threshold: 0
        })' 2>/dev/null || echo "[]")
else
    echo -e "  ${GREEN}[OK]${NC} No static \\Drupal:: calls found"
    STATIC_VIOLATIONS="[]"
fi

# =====================
# Merge all violations
# =====================
ALL_VIOLATIONS=$(echo "$PHPSTAN_VIOLATIONS $PHPMD_VIOLATIONS $STATIC_VIOLATIONS" | \
    jq -s 'add | if . == null then [] else . end' 2>/dev/null || echo "[]")

# Calculate metrics
TOTAL_VIOLATIONS=$(echo "$ALL_VIOLATIONS" | jq 'length' 2>/dev/null || echo "0")

# Determine overall status
if [ "$CRITICAL_COUNT" -gt 0 ]; then
    SOLID_STATUS="fail"
    echo -e "${RED}[FAIL]${NC} Found ${CRITICAL_COUNT} critical SOLID violations"
elif [ "$WARNING_COUNT" -gt 10 ]; then
    SOLID_STATUS="warning"
    echo -e "${YELLOW}[WARN]${NC} Found ${WARNING_COUNT} SOLID warnings"
else
    SOLID_STATUS="pass"
    echo -e "${GREEN}[PASS]${NC} SOLID compliance acceptable"
fi

# Generate JSON report
cat > "${REPORT_DIR}/solid-report.json" << EOF
{
  "violations": ${ALL_VIOLATIONS},
  "metrics": {
    "total_violations": ${TOTAL_VIOLATIONS},
    "critical_count": ${CRITICAL_COUNT},
    "warning_count": ${WARNING_COUNT},
    "suggestion_count": ${SUGGESTION_COUNT},
    "static_drupal_calls": ${STATIC_CALLS},
    "phpstan_errors": ${PHPSTAN_ERRORS:-0},
    "phpmd_violations": ${PHPMD_VIOLATIONS_COUNT:-0}
  },
  "status": "${SOLID_STATUS}",
  "thresholds": {
    "complexity_max": ${COMPLEXITY_MAX}
  },
  "generated_at": "$(date -Iseconds)"
}
EOF

echo ""
echo "Report saved: ${REPORT_DIR}/solid-report.json"

# Exit based on status
case "$SOLID_STATUS" in
    pass) exit 0 ;;
    warning) exit 1 ;;
    fail) exit 2 ;;
esac
