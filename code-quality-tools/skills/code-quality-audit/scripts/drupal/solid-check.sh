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

# The absolute path composer installs global binaries into, resolved at most once.
# `composer global config` prints "Changed current directory to ..." on STDERR, so
# stdout alone is the path. Empty when composer is absent or the lookup fails.
COMPOSER_GLOBAL_BIN=""
COMPOSER_GLOBAL_BIN_RESOLVED=0
resolve_composer_global_bin() {
    if [ "$COMPOSER_GLOBAL_BIN_RESOLVED" -eq 1 ]; then
        return 0
    fi
    COMPOSER_GLOBAL_BIN_RESOLVED=1
    if command -v composer &> /dev/null; then
        COMPOSER_GLOBAL_BIN=$(composer global config bin-dir --absolute 2>/dev/null) \
            || COMPOSER_GLOBAL_BIN=""
    fi
    return 0
}

# Resolve an analyzer to a runnable command. A tool counts as available if it exists
# anywhere a developer plausibly installed it, not only in the repo's vendor/bin.
# Adding phpmd and friends to a client's composer.json as dev dependencies is often
# not acceptable when auditing third-party code, so `composer global require` is the
# polite install — and a globally installed analyzer that works must not be recorded
# as "tool absent" and skipped.
#
# The runner is chosen by where the binary ACTUALLY is, mirroring the semgrep dispatch
# in security-check.sh. Probing one location and then dispatching to another is how a
# host-only tool came to be invoked inside the container, where it does not exist.
# Order: the repo's vendor/bin in the container first (a project-pinned version wins
# over whatever the machine happens to have), then the host PATH, then composer's
# global bin dir, which is frequently not on PATH.
#
# Sets ANALYZER_CMD (the argv prefix to invoke) and ANALYZER_RUNNER (container|host).
# Returns 1 when the tool is nowhere at all, which is an EXPECTED absence: the gate
# runs what IS available and records absences in the report.
resolve_analyzer() {
    local tool="$1"
    ANALYZER_CMD=()
    ANALYZER_RUNNER=""

    if ddev exec test -f "vendor/bin/$tool" &> /dev/null; then
        ANALYZER_RUNNER="container"
        ANALYZER_CMD=(ddev exec "vendor/bin/$tool")
        return 0
    fi

    if command -v "$tool" &> /dev/null; then
        ANALYZER_RUNNER="host"
        ANALYZER_CMD=("$tool")
        return 0
    fi

    resolve_composer_global_bin
    if [ -n "$COMPOSER_GLOBAL_BIN" ] && [ -x "${COMPOSER_GLOBAL_BIN}/${tool}" ]; then
        ANALYZER_RUNNER="host"
        ANALYZER_CMD=("${COMPOSER_GLOBAL_BIN}/${tool}")
        return 0
    fi

    return 1
}

# Decide whether an analyzer produced a usable result, and how many findings it holds:
#
#   TOOL_FAILED=0 TOOL_COUNT=0   it ran and found nothing
#   TOOL_FAILED=0 TOOL_COUNT=N   it ran and found N things
#   TOOL_FAILED=1                it did not produce a usable result
#
# Mirrors resolve_tool_result() in security-check.sh, for the same reason: an exit
# status alone cannot decide this. phpstan exits 1 when it FINDS errors and phpmd exits
# 2 when it finds violations, so treating any non-zero as a failure would convert every
# real finding into a fake "tool failed". Only shell-level statuses (126/127, 128+N) are
# read from the exit code; the report decides everything else. A zero that came from a
# tool that never ran is a clean result nobody earned.
#
# Widening discovery makes this matter more, not less: a tool that used to be skipped as
# absent now runs, and a run that produces nothing usable has to be visible as such.
#
# $1 report path, $2 the tool's exit status, $3 the lowest exit status that means "failed
# to run" for this tool, $4 the jq expression that counts findings in the report.
resolve_analyzer_result() {
    local report="$1" exit_status="$2" fail_from="$3" count_expr="$4"
    local count

    TOOL_FAILED=0
    TOOL_COUNT=0

    if [ "$exit_status" -ge "$fail_from" ]; then
        TOOL_FAILED=1
        return 0
    fi

    # Both analyzers emit a JSON document on a run that completed — an empty findings
    # list is still a document — and `> file` creates the file before the tool runs, so
    # a missing or empty report means the run produced no output at all.
    if [ ! -f "$report" ] || [ ! -s "$report" ]; then
        TOOL_FAILED=1
        return 0
    fi

    # The `!` keeps `set -e` from aborting here, so a jq failure is handled rather than
    # fatal. A report that is present but unparseable, or one whose count field is absent
    # so jq yields null instead of a number, is not evidence of a clean tree.
    if ! count=$(jq "$count_expr" "$report" 2>/dev/null); then
        TOOL_FAILED=1
        return 0
    fi
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        TOOL_FAILED=1
        return 0
    fi

    TOOL_COUNT="$count"
    return 0
}

# Serialise a bash array to a JSON string array (empty array → []).
to_json_array() {
    if [ "$#" -eq 0 ]; then
        echo "[]"
    else
        printf '%s\n' "$@" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]"
    fi
}

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

    # Tool-availability tracking: which analyzers actually ran vs were absent.
    # absence ≠ failure; if NO analyzer runs, the gate verdict is "skipped" (exit 0).
    # SKIPPED_TOOLS is the union of both non-producing kinds; ABSENT_TOOLS holds only
    # the expected half, and the failed half is the difference (see the verdict block).
    SKIPPED_TOOLS=()
    ABSENT_TOOLS=()
    RAN_ANALYZERS=0

    echo "Relevant files (${#RELEVANT_FILES[@]}):"
    printf '  %s\n' "${RELEVANT_FILES[@]}"
    echo ""

    # =====================
    # PHPStan Analysis (LSP, DIP) — changed files only
    # =====================
    PHPSTAN_ERRORS=0
    PHPSTAN_VIOLATIONS="[]"
    PHPSTAN_JSON="${REPORT_DIR}/solid/phpstan.json"
    if resolve_analyzer phpstan; then
        echo "Running PHPStan (type safety, LSP, DIP) [${ANALYZER_RUNNER}]..."
        RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
        set +e
        # shellcheck disable=SC2046
        "${ANALYZER_CMD[@]}" analyse \
            "${RELEVANT_FILES[@]}" \
            --error-format=json \
            --no-progress \
            --memory-limit=1500M \
            2>/dev/null > "$PHPSTAN_JSON"
        PHPSTAN_EXIT=$?
        set -e

        # Code findings live in .totals.file_errors. .totals.errors counts global
        # errors, meaning the analysis itself failed to configure or run, and is
        # zero on a run that found hundreds of real defects. Reading it as the
        # finding count reported a confident clean result.
        # No `// 0` default here: a report with no .totals is not a report of zero
        # findings, and resolve_analyzer_result rejects the resulting null.
        resolve_analyzer_result "$PHPSTAN_JSON" "$PHPSTAN_EXIT" 126 '.totals.file_errors'

        if [ "$TOOL_FAILED" -eq 1 ]; then
            echo -e "${YELLOW}[SKIP]${NC} phpstan produced no usable report (exit ${PHPSTAN_EXIT})"
            SKIPPED_TOOLS+=("phpstan")
        else
            PHPSTAN_ERRORS="$TOOL_COUNT"
            PHPSTAN_GLOBAL_ERRORS=$(jq '.totals.errors // 0' "$PHPSTAN_JSON" 2>/dev/null || echo "0")
            echo "  PHPStan errors: ${PHPSTAN_ERRORS}"
            if [ "$PHPSTAN_GLOBAL_ERRORS" -gt 0 ]; then
                echo -e "  ${YELLOW}PHPStan reported ${PHPSTAN_GLOBAL_ERRORS} global error(s) — analysis may be misconfigured, findings may be incomplete${NC}"
            fi

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
        fi
    else
        echo -e "${YELLOW}[SKIP]${NC} phpstan not installed (tool absent)"
        SKIPPED_TOOLS+=("phpstan")
        ABSENT_TOOLS+=("phpstan")
    fi

    # =====================
    # PHPMD Analysis (SRP) — changed files (comma-separated)
    # =====================
    PHPMD_VIOLATIONS_COUNT=0
    PHPMD_VIOLATIONS="[]"
    PHPMD_JSON="${REPORT_DIR}/solid/phpmd.json"
    if resolve_analyzer phpmd; then
        echo "Running PHPMD (complexity, SRP) [${ANALYZER_RUNNER}]..."
        RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
        # PHPMD takes a comma-separated list as the first positional arg
        PHPMD_TARGETS=$(IFS=,; echo "${RELEVANT_FILES[*]}")
        set +e
        "${ANALYZER_CMD[@]}" \
            "$PHPMD_TARGETS" \
            json \
            cleancode,codesize,design,naming \
            --exclude "*/tests/*" \
            2>/dev/null > "$PHPMD_JSON"
        PHPMD_EXIT=$?
        set -e

        # phpmd exits 2 when it finds violations, so only shell-level statuses can be
        # read as a failure here; the report decides the rest.
        resolve_analyzer_result "$PHPMD_JSON" "$PHPMD_EXIT" 126 '[.files[].violations[]] | length'

        if [ "$TOOL_FAILED" -eq 1 ]; then
            echo -e "${YELLOW}[SKIP]${NC} phpmd produced no usable report (exit ${PHPMD_EXIT})"
            SKIPPED_TOOLS+=("phpmd")
        else
        PHPMD_VIOLATIONS_COUNT="$TOOL_COUNT"
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
        fi
    else
        echo -e "${YELLOW}[SKIP]${NC} phpmd not installed (tool absent)"
        SKIPPED_TOOLS+=("phpmd")
        ABSENT_TOOLS+=("phpmd")
    fi

    # =====================
    # Deprecation Detection — PHPStan handles this (already scoped above)
    # =====================
    echo "Deprecation detection: Handled by PHPStan (see phpstan-deprecation-rules)"

    # =====================
    # Check for static \Drupal:: calls (DIP violation) — changed files only
    # grep is always available (not an external analyzer), so this is a real check
    # that runs regardless of phpstan/phpmd presence.
    # =====================
    echo "Checking for static \\Drupal:: calls (DIP)..."

    STATIC_CALLS=0
    STATIC_VIOLATIONS="[]"
    if [ "${#RELEVANT_FILES[@]}" -gt 0 ]; then
        RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
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

    SKIPPED_TOOLS_JSON=$(to_json_array "${SKIPPED_TOOLS[@]+"${SKIPPED_TOOLS[@]}"}")
    ABSENT_TOOLS_JSON=$(to_json_array "${ABSENT_TOOLS[@]+"${ABSENT_TOOLS[@]}"}")
    # tools_absent[] and tools_failed[] are DISJOINT and mean different things.
    # tools_absent = the analyzer is installed nowhere and that is expected; it does not
    # move the verdict, or every machine without phpmd would report incomplete.
    # tools_failed = the analyzer was found and returned nothing usable; a zero from it
    # is not evidence, so it downgrades a would-be pass to "skipped".
    FAILED_TOOLS_JSON=$(jq -n --argjson skipped "$SKIPPED_TOOLS_JSON" \
        --argjson absent "$ABSENT_TOOLS_JSON" '$skipped - $absent')
    FAILED_COUNT=$(echo "$FAILED_TOOLS_JSON" | jq 'length')

    # Determine overall status.
    # If NO analyzer ran at all (every analyzer absent), degrade to "skipped" (exit 0)
    # rather than reporting a hollow PASS. Otherwise the verdict comes from the
    # checks that DID run (absence of a tool never inverts pass↔fail). Real findings
    # outrank an incomplete scan: a critical violation still fails the gate.
    if [ "$RAN_ANALYZERS" -eq 0 ]; then
        SOLID_STATUS="skipped"
        echo -e "${YELLOW}[SKIP]${NC} No SOLID analyzers available (all tools absent) — gate skipped"
    elif [ "$CRITICAL_COUNT" -gt 0 ]; then
        SOLID_STATUS="fail"
        echo -e "${RED}[FAIL]${NC} Found ${CRITICAL_COUNT} critical SOLID violations"
    elif [ "$WARNING_COUNT" -gt 10 ]; then
        SOLID_STATUS="warning"
        echo -e "${YELLOW}[WARN]${NC} Found ${WARNING_COUNT} SOLID warnings"
    elif [ "$FAILED_COUNT" -gt 0 ]; then
        SOLID_STATUS="skipped"
        echo -e "${YELLOW}[SKIP]${NC} No violations, but $(echo "$FAILED_TOOLS_JSON" | jq -r 'join(", ")') returned no usable result — gate skipped"
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
  "analyzers_ran": ${RAN_ANALYZERS},
  "skipped_tools": ${SKIPPED_TOOLS_JSON},
  "tools_absent": ${ABSENT_TOOLS_JSON},
  "tools_failed": ${FAILED_TOOLS_JSON},
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
        skipped) exit 0 ;;
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

# Tool-availability tracking (see --changed path for rationale).
SKIPPED_TOOLS=()
ABSENT_TOOLS=()
RAN_ANALYZERS=0
PHPSTAN_ERRORS=0
PHPMD_VIOLATIONS_COUNT=0

# Create temp directory for individual reports
mkdir -p "${REPORT_DIR}/solid"

# =====================
# PHPStan Analysis (LSP, DIP)
# =====================
PHPSTAN_VIOLATIONS="[]"
PHPSTAN_JSON="${REPORT_DIR}/solid/phpstan.json"
if resolve_analyzer phpstan; then
    echo "Running PHPStan (type safety, LSP, DIP) [${ANALYZER_RUNNER}]..."
    RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
    set +e
    "${ANALYZER_CMD[@]}" analyse \
        "${DRUPAL_MODULES_PATH}" \
        --error-format=json \
        --no-progress \
        --memory-limit=1500M \
        2>/dev/null > "$PHPSTAN_JSON"
    PHPSTAN_EXIT=$?
    set -e

    # See the note at the --changed call site for both the field choice and the
    # threshold: .totals.file_errors holds the code findings, and phpstan exits 1 when
    # it finds them, so only shell-level statuses can be read as a failure.
    resolve_analyzer_result "$PHPSTAN_JSON" "$PHPSTAN_EXIT" 126 '.totals.file_errors'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "${YELLOW}[SKIP]${NC} phpstan produced no usable report (exit ${PHPSTAN_EXIT})"
        SKIPPED_TOOLS+=("phpstan")
        PHPSTAN_VIOLATIONS="[]"
    else
        PHPSTAN_ERRORS="$TOOL_COUNT"
        PHPSTAN_GLOBAL_ERRORS=$(jq '.totals.errors // 0' "$PHPSTAN_JSON" 2>/dev/null || echo "0")
        echo "  PHPStan errors: ${PHPSTAN_ERRORS}"
        if [ "$PHPSTAN_GLOBAL_ERRORS" -gt 0 ]; then
            echo -e "  ${YELLOW}PHPStan reported ${PHPSTAN_GLOBAL_ERRORS} global error(s) — analysis may be misconfigured, findings may be incomplete${NC}"
        fi

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
            WARNING_COUNT=$((WARNING_COUNT + PHPSTAN_ERRORS))
        else
            PHPSTAN_VIOLATIONS="[]"
        fi
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} phpstan not installed (tool absent)"
    SKIPPED_TOOLS+=("phpstan")
    ABSENT_TOOLS+=("phpstan")
fi

# =====================
# PHPMD Analysis (SRP)
# =====================
PHPMD_VIOLATIONS="[]"
PHPMD_JSON="${REPORT_DIR}/solid/phpmd.json"
if resolve_analyzer phpmd; then
    echo "Running PHPMD (complexity, SRP) [${ANALYZER_RUNNER}]..."
    RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
    set +e
    "${ANALYZER_CMD[@]}" \
        "${DRUPAL_MODULES_PATH}" \
        json \
        cleancode,codesize,design,naming \
        --exclude "*/tests/*" \
        2>/dev/null > "$PHPMD_JSON"
    PHPMD_EXIT=$?
    set -e

    # phpmd exits 2 on violations; see the --changed call site.
    resolve_analyzer_result "$PHPMD_JSON" "$PHPMD_EXIT" 126 '[.files[].violations[]] | length'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "${YELLOW}[SKIP]${NC} phpmd produced no usable report (exit ${PHPMD_EXIT})"
        SKIPPED_TOOLS+=("phpmd")
        PHPMD_VIOLATIONS="[]"
    else
        PHPMD_VIOLATIONS_COUNT="$TOOL_COUNT"
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

            CRITICAL_COUNT=$((CRITICAL_COUNT + PHPMD_CRITICAL)) || true
            WARNING_COUNT=$((WARNING_COUNT + PHPMD_WARNINGS)) || true
            SUGGESTION_COUNT=$((SUGGESTION_COUNT + PHPMD_SUGGESTIONS)) || true
        else
            PHPMD_VIOLATIONS="[]"
        fi
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} phpmd not installed (tool absent)"
    SKIPPED_TOOLS+=("phpmd")
    ABSENT_TOOLS+=("phpmd")
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
# grep is always available (not an external analyzer) — this real check runs
# regardless of phpstan/phpmd presence.
# =====================
echo "Checking for static \\Drupal:: calls (DIP)..."
RAN_ANALYZERS=$((RAN_ANALYZERS + 1))

STATIC_CALLS=$(ddev exec grep -r "\\\\Drupal::" "${DRUPAL_MODULES_PATH}" \
    --include="*.php" \
    --exclude-dir="tests" \
    -l 2>/dev/null | wc -l || echo "0")

if [ "$STATIC_CALLS" -gt 0 ]; then
    echo -e "  ${YELLOW}[WARN]${NC} Found ${STATIC_CALLS} files with static \\Drupal:: calls"
    WARNING_COUNT=$((WARNING_COUNT + STATIC_CALLS)) || true

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

SKIPPED_TOOLS_JSON=$(to_json_array "${SKIPPED_TOOLS[@]+"${SKIPPED_TOOLS[@]}"}")
ABSENT_TOOLS_JSON=$(to_json_array "${ABSENT_TOOLS[@]+"${ABSENT_TOOLS[@]}"}")
# tools_absent[] and tools_failed[] are DISJOINT; see the --changed path for what each
# name means and why only the failed half moves the verdict.
FAILED_TOOLS_JSON=$(jq -n --argjson skipped "$SKIPPED_TOOLS_JSON" \
    --argjson absent "$ABSENT_TOOLS_JSON" '$skipped - $absent')
FAILED_COUNT=$(echo "$FAILED_TOOLS_JSON" | jq 'length')

# Determine overall status. All analyzers absent → "skipped" (exit 0), never a
# hollow PASS. Absence of a tool never inverts pass↔fail; a tool that was found and
# returned nothing usable caps a would-be pass, but real findings still outrank it.
if [ "$RAN_ANALYZERS" -eq 0 ]; then
    SOLID_STATUS="skipped"
    echo -e "${YELLOW}[SKIP]${NC} No SOLID analyzers available (all tools absent) — gate skipped"
elif [ "$CRITICAL_COUNT" -gt 0 ]; then
    SOLID_STATUS="fail"
    echo -e "${RED}[FAIL]${NC} Found ${CRITICAL_COUNT} critical SOLID violations"
elif [ "$WARNING_COUNT" -gt 10 ]; then
    SOLID_STATUS="warning"
    echo -e "${YELLOW}[WARN]${NC} Found ${WARNING_COUNT} SOLID warnings"
elif [ "$FAILED_COUNT" -gt 0 ]; then
    SOLID_STATUS="skipped"
    echo -e "${YELLOW}[SKIP]${NC} No violations, but $(echo "$FAILED_TOOLS_JSON" | jq -r 'join(", ")') returned no usable result — gate skipped"
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
  "analyzers_ran": ${RAN_ANALYZERS},
  "skipped_tools": ${SKIPPED_TOOLS_JSON},
  "tools_absent": ${ABSENT_TOOLS_JSON},
  "tools_failed": ${FAILED_TOOLS_JSON},
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
    skipped) exit 0 ;;
    pass) exit 0 ;;
    warning) exit 1 ;;
    fail) exit 2 ;;
esac
