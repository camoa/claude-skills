#!/bin/bash
# dry-check.sh - Run PHPCPD duplication analysis
# Part of code-quality-audit skill
#
# --changed <file>  Change-scoped verdict mode.
#   Keeps the whole-tree phpcpd scan but FAILS only on clones where ≥1 file
#   location is in the changed-files list. Clones entirely among unchanged
#   files are recorded informationally (not failing). The no-flag path is
#   unchanged: every clone counts toward the verdict.
#
# <file>: a newline-delimited list of changed file paths (relative to project
# root, same format as `git diff --name-only`). Paths in phpcpd output are
# matched after stripping the /var/www/html/ ddev container prefix.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"
DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"
DUPLICATION_MAX="${DUPLICATION_MAX:-5}"

# PHPCPD settings
MIN_LINES="${PHPCPD_MIN_LINES:-10}"
MIN_TOKENS="${PHPCPD_MIN_TOKENS:-70}"

# --changed <file> argument
CHANGED_FILES_PATH=""

# Parse arguments (only --changed; other positional args not currently used)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --changed)
            shift
            CHANGED_FILES_PATH="${1:-}"
            if [ -z "$CHANGED_FILES_PATH" ]; then
                echo -e "${RED}[ERROR]${NC} --changed requires a file path argument" >&2
                exit 2
            fi
            if [ ! -f "$CHANGED_FILES_PATH" ]; then
                echo -e "${RED}[ERROR]${NC} --changed file not found: $CHANGED_FILES_PATH" >&2
                exit 2
            fi
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# parse_clone_blocks <phpcpd_output_file>
# Reads phpcpd text output and emits one line per clone group:
#   "FILE1|FILE2[|FILE3...]"
# Files are bare relative paths with the /var/www/html/ ddev prefix stripped.
# Handles two-copy and multi-copy clones. Exported/sourceable for tests.
# ---------------------------------------------------------------------------
parse_clone_blocks() {
    awk '
    /^  - / {
        # Flush any pending block before starting a new one
        if (block != "") { print block }
        # Strip leading "  - " (4 chars), then strip ":line-line (N lines)" suffix
        path = substr($0, 5)
        sub(/:.*/, "", path)
        # Normalize ddev container prefix
        sub(/^\/var\/www\/html\//, "", path)
        block = path
        next
    }
    /^    / && block != "" {
        # Continuation line of current clone block (4-space indent, not "  - ")
        path = substr($0, 5)
        sub(/:.*/, "", path)
        sub(/^\/var\/www\/html\//, "", path)
        block = block "|" path
        next
    }
    # A non-indented line (blank line, summary line) ends the current block
    !/^  / && block != "" {
        print block
        block = ""
    }
    END {
        if (block != "") { print block }
    }
    ' "$1"
}

# ---------------------------------------------------------------------------
# clone_touches_changed <clone_line> <changed_files_path>
# Returns 0 (true) if any file in the clone group is in the changed-files list.
# clone_line: "FILE1|FILE2" format from parse_clone_blocks.
# changed_files_path: path to file with one relative path per line.
# ---------------------------------------------------------------------------
clone_touches_changed() {
    local clone_line="$1"
    local changed_path="$2"
    local IFS='|'
    local files
    read -ra files <<< "$clone_line"
    local f
    for f in "${files[@]}"; do
        f="${f# }"   # trim any leading space
        f="${f% }"   # trim any trailing space
        [ -z "$f" ] && continue
        if grep -qxF "$f" "$changed_path" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

echo "=== DRY Analysis (PHPCPD) ==="
if [ -n "$CHANGED_FILES_PATH" ]; then
    echo "[changed mode] verdict filtered to change-touching clones"
    echo "Changed-files list: ${CHANGED_FILES_PATH}"
fi
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

# Run PHPCPD (always whole-tree; scope is not applied here even in --changed mode)
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

# ---------------------------------------------------------------------------
# Verdict: --changed mode vs. no-flag (original) mode
# ---------------------------------------------------------------------------

if [ -n "$CHANGED_FILES_PATH" ] && [ "$CLONE_COUNT" -gt 0 ]; then
    # --changed mode: filter clones by whether they touch a changed file.
    # Scan is whole-tree (kept); verdict is change-scoped.
    FAILING_CLONES=0
    INFO_CLONES=0

    echo "=== Clone verdict (change-scoped) ==="
    while IFS= read -r clone_line; do
        [ -z "$clone_line" ] && continue
        if clone_touches_changed "$clone_line" "$CHANGED_FILES_PATH"; then
            FAILING_CLONES=$((FAILING_CLONES + 1))
            echo -e "${RED}[FAIL]${NC} Clone touches changed file: ${clone_line}"
        else
            INFO_CLONES=$((INFO_CLONES + 1))
            echo -e "${BLUE}[INFO]${NC} Clone among unchanged files (informational): ${clone_line}"
        fi
    done < <(parse_clone_blocks "$PHPCPD_OUTPUT")
    echo ""

    echo "  Failing clones (change-touching): ${FAILING_CLONES}"
    echo "  Informational clones (unchanged only): ${INFO_CLONES}"
    echo ""

    if [ "$FAILING_CLONES" -gt 0 ]; then
        DRY_STATUS="fail"
        DRY_RATING="fail"
        echo -e "${RED}[FAIL]${NC} ${FAILING_CLONES} clone(s) touch changed files — fix before merging"
    else
        DRY_STATUS="pass"
        DRY_RATING="excellent"
        echo -e "${GREEN}[PASS]${NC} No clones touch changed files (${INFO_CLONES} informational clone(s) among unchanged files)"
    fi

    # Generate JSON report (changed mode)
    cat > "${REPORT_DIR}/dry-report.json" << EOF
{
  "changed_mode": true,
  "changed_files": "${CHANGED_FILES_PATH}",
  "duplication_percentage": ${DUPLICATION_PCT},
  "total_lines": ${TOTAL_LINES},
  "duplicated_lines": ${DUPLICATED_LINES},
  "clone_count": ${CLONE_COUNT},
  "failing_clones": ${FAILING_CLONES},
  "informational_clones": ${INFO_CLONES},
  "clones": ${CLONES_JSON},
  "rating": "${DRY_RATING}",
  "status": "${DRY_STATUS}",
  "settings": {
    "min_lines": ${MIN_LINES},
    "min_tokens": ${MIN_TOKENS}
  },
  "generated_at": "$(date -Iseconds)"
}
EOF

else
    # No-flag path: original behavior (all clones count toward verdict)
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

    # Generate JSON report (no-flag original format)
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
fi

echo ""
echo "Report saved: ${REPORT_DIR}/dry-report.json"

# Exit based on status
case "$DRY_STATUS" in
    pass) exit 0 ;;
    warning) exit 1 ;;
    fail) exit 2 ;;
esac
