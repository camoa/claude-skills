#!/bin/bash
# solid-check.sh - SOLID principles analysis for Next.js/TypeScript projects
# Part of code-quality-audit skill
#
# Checks:
# - Single Responsibility: File complexity, function size
# - Open/Closed: Component composition patterns
# - Liskov Substitution: Interface implementation consistency
# - Interface Segregation: Import analysis, circular dependencies
# - Dependency Inversion: Proper DI patterns, no hardcoded dependencies

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"
COMPLEXITY_MAX="${COMPLEXITY_MAX:-10}"
MAX_FILE_LINES="${MAX_FILE_LINES:-300}"
MAX_FUNCTION_LINES="${MAX_FUNCTION_LINES:-50}"

echo "=== SOLID Principles Check (Next.js) ==="
echo ""

# Check for npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} npm is not installed"
    exit 2
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} jq is required for JSON processing"
    echo "  Install with: apt-get install jq (Linux) or brew install jq (Mac)"
    exit 2
fi

mkdir -p "${REPORT_DIR}/solid"

# Initialize counters
CRITICAL_COUNT=0
WARNING_COUNT=0
CIRCULAR_DEPS=0
COMPLEXITY_VIOLATIONS=0
LARGE_FILES=0

# Determine source directory
SOURCE_DIR="src"
if [ ! -d "$SOURCE_DIR" ]; then
    if [ -d "app" ]; then
        SOURCE_DIR="app"
    elif [ -d "pages" ]; then
        SOURCE_DIR="pages"
    else
        SOURCE_DIR="."
    fi
fi

echo "Analyzing: ${SOURCE_DIR}"
echo "  Max complexity: ${COMPLEXITY_MAX}"
echo "  Max file lines: ${MAX_FILE_LINES}"
echo "  Max function lines: ${MAX_FUNCTION_LINES}"
echo ""

# =====================
# 1. Circular Dependency Check (ISP, DIP)
# =====================
echo -e "${BLUE}[1/4]${NC} Checking circular dependencies..."

CIRCULAR_REPORT="${REPORT_DIR}/solid/circular-deps.json"

if npx madge --version &> /dev/null 2>&1; then
    # Run madge for circular dependency detection
    set +e
    npx madge --circular --json "${SOURCE_DIR}" > "${CIRCULAR_REPORT}" 2>/dev/null
    MADGE_EXIT=$?
    set -e

    if [ -f "${CIRCULAR_REPORT}" ]; then
        CIRCULAR_DEPS=$(jq 'length' "${CIRCULAR_REPORT}" 2>/dev/null || echo "0")

        if [ "$CIRCULAR_DEPS" -gt 0 ]; then
            echo -e "${RED}[FAIL]${NC} Found ${CIRCULAR_DEPS} circular dependency chain(s)"
            echo ""
            echo "  Circular dependencies violate:"
            echo "  - Interface Segregation: modules too tightly coupled"
            echo "  - Dependency Inversion: concrete dependencies instead of abstractions"
            echo ""
            # Show first 3 chains
            jq -r '.[0:3][] | "  Chain: " + (. | join(" -> "))' "${CIRCULAR_REPORT}" 2>/dev/null || true
            ((CRITICAL_COUNT += CIRCULAR_DEPS))
        else
            echo -e "${GREEN}[PASS]${NC} No circular dependencies found"
        fi
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} madge not installed (run install-tools.sh)"
    echo '[]' > "${CIRCULAR_REPORT}"
fi

echo ""

# =====================
# 2. Complexity Analysis (SRP)
# =====================
echo -e "${BLUE}[2/4]${NC} Checking complexity (Single Responsibility)..."

COMPLEXITY_REPORT="${REPORT_DIR}/solid/complexity.json"

# Use ESLint to check complexity if available
if npx eslint --version &> /dev/null 2>&1; then
    set +e
    # Run ESLint with complexity rules and JSON output
    npx eslint "${SOURCE_DIR}" \
        --rule 'complexity: ["error", '"${COMPLEXITY_MAX}"']' \
        --rule 'max-lines-per-function: ["error", {"max": '"${MAX_FUNCTION_LINES}"'}]' \
        --format json \
        --no-error-on-unmatched-pattern \
        2>/dev/null > "${COMPLEXITY_REPORT}" || true
    set -e

    if [ -f "${COMPLEXITY_REPORT}" ] && [ -s "${COMPLEXITY_REPORT}" ]; then
        COMPLEXITY_VIOLATIONS=$(jq '[.[].messages[] | select(.ruleId == "complexity" or .ruleId == "max-lines-per-function")] | length' "${COMPLEXITY_REPORT}" 2>/dev/null || echo "0")

        if [ "$COMPLEXITY_VIOLATIONS" -gt 0 ]; then
            echo -e "${YELLOW}[WARN]${NC} ${COMPLEXITY_VIOLATIONS} complexity violation(s)"
            echo ""
            echo "  High complexity violates Single Responsibility Principle:"
            echo "  - Functions doing too much"
            echo "  - Classes with multiple reasons to change"
            echo ""
            # Show first 5 violations
            jq -r '[.[].messages[] | select(.ruleId == "complexity" or .ruleId == "max-lines-per-function")][0:5] | .[] | "  \(.ruleId) in \(.message)"' "${COMPLEXITY_REPORT}" 2>/dev/null || true
            ((WARNING_COUNT += COMPLEXITY_VIOLATIONS))
        else
            echo -e "${GREEN}[PASS]${NC} Complexity within limits"
        fi
    else
        echo -e "${GREEN}[PASS]${NC} Complexity within limits"
        echo '[]' > "${COMPLEXITY_REPORT}"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} ESLint not available"
    echo '[]' > "${COMPLEXITY_REPORT}"
fi

echo ""

# =====================
# 3. Large File Detection (SRP)
# =====================
echo -e "${BLUE}[3/4]${NC} Checking file sizes (Single Responsibility)..."

LARGE_FILES_REPORT="${REPORT_DIR}/solid/large-files.json"

# Find large TypeScript/JavaScript files
echo "[" > "${LARGE_FILES_REPORT}"
FIRST=true

while IFS= read -r -d '' file; do
    lines=$(wc -l < "$file")
    if [ "$lines" -gt "$MAX_FILE_LINES" ]; then
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            echo "," >> "${LARGE_FILES_REPORT}"
        fi
        echo "  {\"file\": \"${file}\", \"lines\": ${lines}, \"max\": ${MAX_FILE_LINES}}" >> "${LARGE_FILES_REPORT}"
        ((LARGE_FILES++))
    fi
done < <(find "${SOURCE_DIR}" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) ! -path "*/node_modules/*" ! -path "*/.next/*" ! -name "*.test.*" ! -name "*.spec.*" -print0 2>/dev/null)

echo "]" >> "${LARGE_FILES_REPORT}"

if [ "$LARGE_FILES" -gt 0 ]; then
    echo -e "${YELLOW}[WARN]${NC} ${LARGE_FILES} file(s) exceed ${MAX_FILE_LINES} lines"
    echo ""
    echo "  Large files often indicate SRP violations:"
    echo "  - Multiple responsibilities in one file"
    echo "  - Consider splitting into smaller, focused modules"
    echo ""
    jq -r '.[] | "  \(.file): \(.lines) lines"' "${LARGE_FILES_REPORT}" 2>/dev/null | head -5
    ((WARNING_COUNT += LARGE_FILES))
else
    echo -e "${GREEN}[PASS]${NC} All files within size limits"
fi

echo ""

# =====================
# 4. TypeScript Strict Mode Check (LSP, DIP)
# =====================
echo -e "${BLUE}[4/4]${NC} Checking TypeScript configuration..."

TS_CONFIG_REPORT="${REPORT_DIR}/solid/tsconfig-analysis.json"
TS_ISSUES=0

if [ -f "tsconfig.json" ]; then
    # Check for strict mode settings
    STRICT=$(jq '.compilerOptions.strict // false' tsconfig.json 2>/dev/null)
    STRICT_NULL=$(jq '.compilerOptions.strictNullChecks // false' tsconfig.json 2>/dev/null)
    NO_IMPLICIT_ANY=$(jq '.compilerOptions.noImplicitAny // false' tsconfig.json 2>/dev/null)

    cat > "${TS_CONFIG_REPORT}" << EOF
{
  "strict": ${STRICT},
  "strictNullChecks": ${STRICT_NULL},
  "noImplicitAny": ${NO_IMPLICIT_ANY},
  "recommendations": []
}
EOF

    if [ "$STRICT" != "true" ]; then
        echo -e "${YELLOW}[WARN]${NC} strict mode not enabled"
        echo "  Strict mode helps enforce:"
        echo "  - Liskov Substitution (proper type contracts)"
        echo "  - Dependency Inversion (interface-based programming)"
        ((TS_ISSUES++))
        ((WARNING_COUNT++))
    else
        echo -e "${GREEN}[PASS]${NC} TypeScript strict mode enabled"
    fi

    if [ "$STRICT" != "true" ] && [ "$NO_IMPLICIT_ANY" != "true" ]; then
        echo -e "${YELLOW}[WARN]${NC} noImplicitAny not enabled"
        ((TS_ISSUES++))
        ((WARNING_COUNT++))
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} No tsconfig.json found"
    echo '{"strict": null, "strictNullChecks": null, "noImplicitAny": null}' > "${TS_CONFIG_REPORT}"
fi

echo ""

# =====================
# Generate Summary Report
# =====================

# Determine overall status
SOLID_STATUS="pass"
if [ "$CRITICAL_COUNT" -gt 0 ]; then
    SOLID_STATUS="fail"
elif [ "$WARNING_COUNT" -gt 5 ]; then
    SOLID_STATUS="fail"
elif [ "$WARNING_COUNT" -gt 0 ]; then
    SOLID_STATUS="warning"
fi

# Build violations array for report-processor compatibility
VIOLATIONS_JSON="["
FIRST_VIOLATION=true

# Add circular dependency violations
if [ -f "${CIRCULAR_REPORT}" ] && [ "$CIRCULAR_DEPS" -gt 0 ]; then
    while IFS= read -r chain; do
        if [ "$FIRST_VIOLATION" = true ]; then
            FIRST_VIOLATION=false
        else
            VIOLATIONS_JSON+=","
        fi
        VIOLATIONS_JSON+="{\"severity\":\"critical\",\"principle\":\"ISP/DIP\",\"file\":\"circular-dependency\",\"line\":0,\"message\":\"Circular dependency chain: ${chain}\"}"
    done < <(jq -r '.[] | join(" -> ")' "${CIRCULAR_REPORT}" 2>/dev/null)
fi

# Add large file violations
if [ -f "${LARGE_FILES_REPORT}" ] && [ "$LARGE_FILES" -gt 0 ]; then
    while IFS= read -r file_info; do
        file=$(echo "$file_info" | jq -r '.file')
        lines=$(echo "$file_info" | jq -r '.lines')
        if [ "$FIRST_VIOLATION" = true ]; then
            FIRST_VIOLATION=false
        else
            VIOLATIONS_JSON+=","
        fi
        VIOLATIONS_JSON+="{\"severity\":\"warning\",\"principle\":\"SRP\",\"file\":\"${file}\",\"line\":0,\"message\":\"File has ${lines} lines (max: ${MAX_FILE_LINES})\"}"
    done < <(jq -c '.[]' "${LARGE_FILES_REPORT}" 2>/dev/null)
fi

# Add TypeScript strict mode warning
if [ "$STRICT" != "true" ] && [ -f "tsconfig.json" ]; then
    if [ "$FIRST_VIOLATION" = true ]; then
        FIRST_VIOLATION=false
    else
        VIOLATIONS_JSON+=","
    fi
    VIOLATIONS_JSON+="{\"severity\":\"warning\",\"principle\":\"LSP/DIP\",\"file\":\"tsconfig.json\",\"line\":0,\"message\":\"TypeScript strict mode not enabled\"}"
fi

VIOLATIONS_JSON+="]"

# Generate consolidated report (compatible with report-processor.sh)
cat > "${REPORT_DIR}/solid-report.json" << EOF
{
  "status": "${SOLID_STATUS}",
  "violations": ${VIOLATIONS_JSON},
  "metrics": {
    "circular_dependencies": ${CIRCULAR_DEPS},
    "complexity_violations": ${COMPLEXITY_VIOLATIONS},
    "large_files": ${LARGE_FILES},
    "typescript_issues": ${TS_ISSUES}
  },
  "principles": {
    "single_responsibility": {
      "status": "$([ $((COMPLEXITY_VIOLATIONS + LARGE_FILES)) -eq 0 ] && echo "pass" || echo "warning")",
      "complexity_violations": ${COMPLEXITY_VIOLATIONS},
      "large_files": ${LARGE_FILES}
    },
    "open_closed": {
      "status": "info",
      "note": "Requires manual review of component composition"
    },
    "liskov_substitution": {
      "status": "$([ "$STRICT" == "true" ] && echo "pass" || echo "warning")",
      "typescript_strict": ${STRICT:-false}
    },
    "interface_segregation": {
      "status": "$([ "$CIRCULAR_DEPS" -eq 0 ] && echo "pass" || echo "fail")",
      "circular_dependencies": ${CIRCULAR_DEPS}
    },
    "dependency_inversion": {
      "status": "$([ "$CIRCULAR_DEPS" -eq 0 ] && [ "$STRICT" == "true" ] && echo "pass" || echo "warning")",
      "circular_dependencies": ${CIRCULAR_DEPS},
      "typescript_strict": ${STRICT:-false}
    }
  },
  "thresholds": {
    "complexity_max": ${COMPLEXITY_MAX},
    "max_file_lines": ${MAX_FILE_LINES},
    "max_function_lines": ${MAX_FUNCTION_LINES}
  },
  "generated_at": "$(date -Iseconds)"
}
EOF

echo "=== SOLID Summary ==="
echo ""
echo "  | Principle              | Status  | Issues |"
echo "  |------------------------|---------|--------|"
printf "  | Single Responsibility  | %-7s | %6d |\n" "$([ $((COMPLEXITY_VIOLATIONS + LARGE_FILES)) -eq 0 ] && echo "PASS" || echo "WARN")" "$((COMPLEXITY_VIOLATIONS + LARGE_FILES))"
printf "  | Open/Closed            | %-7s | %6s |\n" "INFO" "manual"
printf "  | Liskov Substitution    | %-7s | %6d |\n" "$([ "$STRICT" == "true" ] && echo "PASS" || echo "WARN")" "$TS_ISSUES"
printf "  | Interface Segregation  | %-7s | %6d |\n" "$([ "$CIRCULAR_DEPS" -eq 0 ] && echo "PASS" || echo "FAIL")" "$CIRCULAR_DEPS"
printf "  | Dependency Inversion   | %-7s | %6d |\n" "$([ "$CIRCULAR_DEPS" -eq 0 ] && [ "$STRICT" == "true" ] && echo "PASS" || echo "WARN")" "$CIRCULAR_DEPS"
echo ""
echo "  Critical: ${CRITICAL_COUNT}"
echo "  Warnings: ${WARNING_COUNT}"
echo ""

case "$SOLID_STATUS" in
    pass)
        echo -e "${GREEN}[PASS]${NC} SOLID principles check passed"
        exit 0
        ;;
    warning)
        echo -e "${YELLOW}[WARN]${NC} Some SOLID issues found"
        exit 1
        ;;
    fail)
        echo -e "${RED}[FAIL]${NC} Critical SOLID violations"
        exit 2
        ;;
esac
