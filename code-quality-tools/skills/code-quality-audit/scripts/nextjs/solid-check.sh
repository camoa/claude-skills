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

# Where reports go is decided in one place, and it is never inside the audited
# repository unless REPORT_DIR says so or REPORT_DIR_IN_REPO=1 asks for it.
# shellcheck source=../core/report-dir.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/report-dir.sh"
# CQT_STATUS_UNMEASURED / CQT_EXIT_UNMEASURED: the word and the exit code for "this gate
# produced no measurement", so a caller with only an exit status cannot read it as a pass.
# shellcheck source=../core/path-resolve.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/path-resolve.sh"
cqt_report_dir_init
cqt_announce_report_dir
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

# COVERAGE VOCABULARY — the same four lists the Drupal gates emit, and for the same
# reason. Until 3.10.1 this gate printed "[SKIP] madge not installed", set status to
# "pass" and emitted a report with NO tool lists at all, so a Next.js project with every
# analyzer missing was indistinguishable from one where every analyzer ran and found
# nothing. That is the exact defect the Drupal side was rewritten to remove, left in
# place one directory over.
#
#   tools_absent[]     the analyzer IS NOT INSTALLED — a fact about the machine, and the
#                      only one of the four that is a coverage gap.
#   tools_failed[]     it was there and returned nothing usable. A zero from it is not
#                      evidence.
#   tools_unmeasured[] never asked, because the ground it would have read is not there
#                      (a source tree with no TS/JS in it).
#   tools_skipped[]    omitted BY DESIGN — a JavaScript project has no tsconfig.json and
#                      that is not a gap in the audit.
#
# analyzers_ran counts CHECKS THAT PRODUCED A MEASUREMENT, and like the Drupal gate's it
# is NOT the coverage test on its own: the file-size scan needs no binary, so it can be
# 1 with both real analyzers gone. binary_analyzers[] names the ones that DO need a
# binary, so a consumer can ask "did every analyzer that needs installing go missing?"
# without hardcoding this gate's tool names on its own side.
ABSENT_TOOLS=()
FAILED_TOOLS=()
UNMEASURED_TOOLS=()
SKIPPED_BY_DESIGN=()
RAN_ANALYZERS=0
BINARY_ANALYZERS='["madge","eslint"]'

to_json_array() {
    if [ "$#" -eq 0 ]; then printf '[]'; else printf '%s\n' "$@" | jq -R . | jq -s -c .; fi
}

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

    # madge writes a JSON array whenever it can run at all. No file, or a file jq cannot
    # read, means it did not produce a result — and a missing result is not zero cycles.
    if [ -f "${CIRCULAR_REPORT}" ] && jq -e 'type == "array"' "${CIRCULAR_REPORT}" >/dev/null 2>&1; then
        CIRCULAR_DEPS=$(jq 'length' "${CIRCULAR_REPORT}" 2>/dev/null || echo "0")
        RAN_ANALYZERS=$((RAN_ANALYZERS + 1))

        if [ "$CIRCULAR_DEPS" -gt 0 ]; then
            echo -e "${RED}[FAIL]${NC} Found ${CIRCULAR_DEPS} circular dependency chain(s)"
            echo ""
            echo "  Circular dependencies violate:"
            echo "  - Interface Segregation: modules too tightly coupled"
            echo "  - Dependency Inversion: concrete dependencies instead of abstractions"
            echo ""
            # Show first 3 chains
            jq -r '.[0:3][] | "  Chain: " + (. | join(" -> "))' "${CIRCULAR_REPORT}" 2>/dev/null || true
            CRITICAL_COUNT=$((CRITICAL_COUNT + CIRCULAR_DEPS))
        else
            echo -e "${GREEN}[PASS]${NC} No circular dependencies found"
        fi
    else
        echo -e "${YELLOW}[FAIL]${NC} madge produced no usable report (exit ${MADGE_EXIT}) — circular dependencies were NOT checked"
        FAILED_TOOLS+=("madge")
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} madge not installed (run install-tools.sh)"
    echo '[]' > "${CIRCULAR_REPORT}"
    ABSENT_TOOLS+=("madge")
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

    # ESLint with --format json prints a JSON array whenever it runs, even for a clean
    # tree. An empty or unparseable file means it did not run to completion, and reading
    # that as "complexity within limits" is a clean bill of health nobody issued.
    if [ -f "${COMPLEXITY_REPORT}" ] && [ -s "${COMPLEXITY_REPORT}" ] \
       && jq -e 'type == "array"' "${COMPLEXITY_REPORT}" >/dev/null 2>&1; then
        COMPLEXITY_VIOLATIONS=$(jq '[.[].messages[] | select(.ruleId == "complexity" or .ruleId == "max-lines-per-function")] | length' "${COMPLEXITY_REPORT}" 2>/dev/null || echo "0")
        RAN_ANALYZERS=$((RAN_ANALYZERS + 1))

        if [ "$COMPLEXITY_VIOLATIONS" -gt 0 ]; then
            echo -e "${YELLOW}[WARN]${NC} ${COMPLEXITY_VIOLATIONS} complexity violation(s)"
            echo ""
            echo "  High complexity violates Single Responsibility Principle:"
            echo "  - Functions doing too much"
            echo "  - Classes with multiple reasons to change"
            echo ""
            # Show first 5 violations
            jq -r '[.[].messages[] | select(.ruleId == "complexity" or .ruleId == "max-lines-per-function")][0:5] | .[] | "  \(.ruleId) in \(.message)"' "${COMPLEXITY_REPORT}" 2>/dev/null || true
            WARNING_COUNT=$((WARNING_COUNT + COMPLEXITY_VIOLATIONS))
        else
            echo -e "${GREEN}[PASS]${NC} Complexity within limits"
        fi
    else
        echo -e "${YELLOW}[FAIL]${NC} ESLint produced no usable report — complexity was NOT checked"
        echo '[]' > "${COMPLEXITY_REPORT}"
        FAILED_TOOLS+=("eslint")
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} ESLint not available"
    echo '[]' > "${COMPLEXITY_REPORT}"
    ABSENT_TOOLS+=("eslint")
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
# How many files this layer actually read. Zero is not "all files within size limits";
# it means the layer was pointed at ground with no TS/JS in it and measured nothing.
SCANNED_FILES=0

while IFS= read -r -d '' file; do
    SCANNED_FILES=$((SCANNED_FILES + 1))
    lines=$(wc -l < "$file")
    if [ "$lines" -gt "$MAX_FILE_LINES" ]; then
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            echo "," >> "${LARGE_FILES_REPORT}"
        fi
        echo "  {\"file\": \"${file}\", \"lines\": ${lines}, \"max\": ${MAX_FILE_LINES}}" >> "${LARGE_FILES_REPORT}"
        LARGE_FILES=$((LARGE_FILES + 1))
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
    WARNING_COUNT=$((WARNING_COUNT + LARGE_FILES))
elif [ "$SCANNED_FILES" -eq 0 ]; then
    echo -e "${YELLOW}[UNMEASURED]${NC} no TS/JS files under ${SOURCE_DIR} — file sizes were NOT measured"
    UNMEASURED_TOOLS+=("large_files")
else
    echo -e "${GREEN}[PASS]${NC} All ${SCANNED_FILES} files within size limits"
fi
if [ "$SCANNED_FILES" -gt 0 ]; then
    RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
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
        TS_ISSUES=$((TS_ISSUES + 1))
        WARNING_COUNT=$((WARNING_COUNT + 1))
    else
        echo -e "${GREEN}[PASS]${NC} TypeScript strict mode enabled"
    fi

    if [ "$STRICT" != "true" ] && [ "$NO_IMPLICIT_ANY" != "true" ]; then
        echo -e "${YELLOW}[WARN]${NC} noImplicitAny not enabled"
        TS_ISSUES=$((TS_ISSUES + 1))
        WARNING_COUNT=$((WARNING_COUNT + 1))
    fi
    RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
else
    # By design, not a gap: a JavaScript Next.js project has no tsconfig.json, and
    # calling that missing coverage would put every one of them on a permanent red.
    echo -e "${YELLOW}[SKIP]${NC} No tsconfig.json found — not a TypeScript project"
    echo '{"strict": null, "strictNullChecks": null, "noImplicitAny": null}' > "${TS_CONFIG_REPORT}"
    SKIPPED_BY_DESIGN+=("typescript_strict")
fi

echo ""

# =====================
# Generate Summary Report
# =====================

ABSENT_TOOLS_JSON=$(to_json_array "${ABSENT_TOOLS[@]+"${ABSENT_TOOLS[@]}"}")
FAILED_TOOLS_JSON=$(to_json_array "${FAILED_TOOLS[@]+"${FAILED_TOOLS[@]}"}")
UNMEASURED_TOOLS_JSON=$(to_json_array "${UNMEASURED_TOOLS[@]+"${UNMEASURED_TOOLS[@]}"}")
SKIPPED_TOOLS_JSON=$(to_json_array "${SKIPPED_BY_DESIGN[@]+"${SKIPPED_BY_DESIGN[@]}"}")

# Determine overall status. Real findings outrank every coverage state — a critical
# violation one layer DID find is not softened because another layer was absent — and
# "nothing was measured at all" is never a pass.
SOLID_STATUS="pass"
if [ "$RAN_ANALYZERS" -eq 0 ]; then
    SOLID_STATUS="${CQT_STATUS_UNMEASURED}"
elif [ "$CRITICAL_COUNT" -gt 0 ]; then
    SOLID_STATUS="fail"
elif [ "$WARNING_COUNT" -gt 5 ]; then
    SOLID_STATUS="fail"
elif [ "$WARNING_COUNT" -gt 0 ]; then
    SOLID_STATUS="warning"
elif [ "${#FAILED_TOOLS[@]}" -gt 0 ]; then
    # No findings, but an analyzer that WAS here returned nothing usable. Its zero is
    # not evidence, so this is not a pass.
    SOLID_STATUS="skipped"
elif [ "${#UNMEASURED_TOOLS[@]}" -gt 0 ]; then
    SOLID_STATUS="${CQT_STATUS_UNMEASURED}"
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
  "analyzers_ran": ${RAN_ANALYZERS},
  "binary_analyzers": ${BINARY_ANALYZERS},
  "tools_absent": ${ABSENT_TOOLS_JSON},
  "tools_failed": ${FAILED_TOOLS_JSON},
  "tools_unmeasured": ${UNMEASURED_TOOLS_JSON},
  "tools_skipped": ${SKIPPED_TOOLS_JSON},
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
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
echo "  Analyzers that produced a measurement: ${RAN_ANALYZERS}"
echo "  Not installed: $(echo "$ABSENT_TOOLS_JSON" | jq -r 'if length == 0 then "none" else join(", ") end')"
echo "  Returned nothing usable: $(echo "$FAILED_TOOLS_JSON" | jq -r 'if length == 0 then "none" else join(", ") end')"
echo "  Nothing to read: $(echo "$UNMEASURED_TOOLS_JSON" | jq -r 'if length == 0 then "none" else join(", ") end')"
echo "  Skipped by design: $(echo "$SKIPPED_TOOLS_JSON" | jq -r 'if length == 0 then "none" else join(", ") end')"
echo ""

# `unmeasured` exits 4 and never 0. The status is the primary channel, but a caller with
# only the exit code — full-audit.sh, an AIDA /validate-* wrapper — reads a zero as a
# pass, which is how a Next.js project with no analyzers installed went green.
case "$SOLID_STATUS" in
    pass)
        echo -e "${GREEN}[PASS]${NC} SOLID principles check passed"
        exit 0
        ;;
    skipped)
        echo -e "${YELLOW}[SKIP]${NC} No violations, but $(echo "$FAILED_TOOLS_JSON" | jq -r 'join(", ")') returned no usable result"
        exit 0
        ;;
    "${CQT_STATUS_UNMEASURED}")
        echo -e "${YELLOW}[UNMEASURED]${NC} nothing was measured — this is not a clean tree, it is an unchecked one"
        exit "$CQT_EXIT_UNMEASURED"
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
