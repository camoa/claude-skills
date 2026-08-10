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

# Resolved HERE, before anything else runs, and exported by the resolver. This script is
# the driver: detect-environment.sh, install-tools.sh and every gate below are separate
# processes that source the same rule, so the export is what makes them agree. Without
# it each would re-resolve, the timestamped default would differ per process, and this
# script would then look for an environment.json a child wrote in a different directory.
# shellcheck source=../core/report-dir.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/report-dir.sh"
cqt_report_dir_init

# Thresholds (can be overridden via environment)
COVERAGE_MINIMUM="${COVERAGE_MINIMUM:-70}"
COVERAGE_TARGET="${COVERAGE_TARGET:-80}"
DUPLICATION_MAX="${DUPLICATION_MAX:-5}"
COMPLEXITY_MAX="${COMPLEXITY_MAX:-10}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        Code Quality & Security Audit - Full Analysis         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
cqt_announce_report_dir
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

# Resolve the final verdict. OVERALL_STATUS starts at "pass" and update_status() only
# ever downgrades it, so "pass" is the value the run starts at rather than one it earns:
# a suite that aborted before any gate ran still reported "pass".
#
# Two kinds of non-result are distinguished, because they are not the same claim:
#
#   "unknown"  the gate never ran — it does not apply to this project type, it is not
#              wired up, or its script is missing. Nothing was promised, so nothing is
#              owed. No consequence beyond not counting.
#              The security gate is genuinely Drupal-only. LINT is a different case and
#              this comment used to misdescribe it: lint is only WIRED for Next.js
#              (Step 4b below), so lint_score reads "unknown" on every Drupal run even
#              though scripts/drupal/lint-check.sh exists, /code-quality-tools:lint
#              runs it standalone, and the audit command documents lint as part of the
#              audit. That is an unwired gate, not a gate that does not apply. Tracked
#              as its own defect; deliberately NOT papered over here.
#   "skipped"  the gate RAN and declared that it could not cover its ground. That is a
#              deliberate statement about coverage, not an accident of project type,
#              and it is the one an audit must not paper over.
#
# So: if no gate produced a result the run proved nothing and the verdict is "unknown",
# whatever the accumulator holds. If some gate produced a result but another explicitly
# skipped, the audit is incomplete and cannot certify a pass — a would-be "pass" is
# capped at "warning". Everything else keeps the existing precedence (fail beats
# warning beats pass); an explicit skip never upgrades a fail or a warning.
#
# The cap is what gives a skipped gate a consequence at the aggregate. Without it
# /audit reports "Overall: PASS" on a run whose security gate covered nothing, which
# is the same false clean one level up.
#
# Self-contained on purpose (reads no globals, echoes the verdict) so the spec can
# extract and source it in isolation.
#   resolve_overall_status <current> <status>...
resolve_overall_status() {
    local current="$1"
    shift
    local produced=0
    local incomplete=0
    local gate
    for gate in "$@"; do
        case "$gate" in
            unknown|"")
                ;;
            skipped)
                incomplete=$((incomplete + 1))
                ;;
            *)
                produced=$((produced + 1))
                ;;
        esac
    done
    if [ "$produced" -eq 0 ]; then
        echo "unknown"
    elif [ "$incomplete" -gt 0 ] && [ "$current" = "pass" ]; then
        echo "warning"
    else
        echo "$current"
    fi
}

# Read one string field out of environment.json without taking the run down.
#
# `grep` exits 1 when the field is absent OR empty, and a bare `VAR=$(grep ...)` under
# `set -e` ends the audit right there with no message at all. That is not theoretical:
# drupal_modules_path is legitimately empty on every Next.js project, so `/audit` on a
# Next.js codebase died at this step, and any environment.json written before these
# fields existed does the same. `[^"]*` rather than `[^"]+` so an empty field reads
# back as an empty string instead of as a failed match.
read_env_field() {
    grep -oP "\"$2\":\s*\"\K[^\"]*" "$1" 2>/dev/null | head -1 || true
}

# Step 1: Detect environment
echo -e "${BLUE}[Step 1/6]${NC} Detecting environment..."
if ! "${SCRIPT_DIR}/detect-environment.sh" > /dev/null 2>&1; then
    if ! "${SCRIPT_DIR}/detect-environment.sh"; then
        # detect-environment.sh stops the run outright when the installed tree does not
        # match composer.lock. It writes environment.json before stopping, so the reason
        # is on disk: say it here rather than reporting "Environment detection failed",
        # which sends the reader to DDEV for a problem that is about composer.
        if [ -f "${REPORT_DIR}/environment.json" ] &&
           [ "$(read_env_field "${REPORT_DIR}/environment.json" version_drift)" = "drift" ]; then
            echo -e "${RED}[STOP]${NC} $(read_env_field "${REPORT_DIR}/environment.json" version_drift_reason)"
            echo "  No gate was run: findings from a tree that does not match composer.lock"
            echo "  cannot be trusted. Run 'composer install', or set ALLOW_VERSION_DRIFT=1"
            echo "  to audit anyway (the run will not be able to report a pass)."
            exit 3
        fi
        echo -e "${RED}[ERROR]${NC} Environment detection failed"
        exit 2
    fi
fi

# Load environment
if [ -f "${REPORT_DIR}/environment.json" ]; then
    PROJECT_TYPE=$(read_env_field "${REPORT_DIR}/environment.json" project_type)
    DRUPAL_MODULES_PATH=$(read_env_field "${REPORT_DIR}/environment.json" drupal_modules_path)
    DRUPAL_THEMES_PATH=$(read_env_field "${REPORT_DIR}/environment.json" drupal_themes_path)
    VERSION_DRIFT=$(read_env_field "${REPORT_DIR}/environment.json" version_drift)
else
    echo -e "${RED}[ERROR]${NC} Environment file not found"
    exit 2
fi

# EXPORT, not just assign. Every gate below runs as its own process, so a plain
# assignment reaches none of them: each would fall back to its own
# `${DRUPAL_MODULES_PATH:-web/modules/custom}` default and scan a tree that
# detect-environment.sh already established is not where this project keeps its code.
# On a docroot-layout (Acquia) project that means the whole audit examines nothing
# while reporting normally.
#
# Only exported when non-empty. An empty value carries no information — every consumer
# defaults with `:-`, so exporting an empty string would at best be a no-op and at
# worst blank out a value the caller deliberately set in their own shell.
if [ -n "$DRUPAL_MODULES_PATH" ]; then
    export DRUPAL_MODULES_PATH
fi
if [ -n "$DRUPAL_THEMES_PATH" ]; then
    export DRUPAL_THEMES_PATH
fi

# Reaching this line with drift recorded means detect-environment.sh was told to
# continue anyway (ALLOW_VERSION_DRIFT=1); without the override it exits and the branch
# above already stopped the run. The override buys a run, not a clean bill of health:
# every gate below is about to examine a tree whose core is not the core its
# dependencies were resolved against, which is precisely a scan that cannot cover its
# ground. That is what "skipped" means here, and a skipped result caps a would-be pass
# at "warning" in resolve_overall_status.
#
# An environment.json written before this field existed reads back empty, which is
# neither a match nor drift and carries no consequence.
VERSION_DRIFT="${VERSION_DRIFT:-}"
DRIFT_STATUS="unknown"
if [ "$VERSION_DRIFT" = "drift" ]; then
    DRIFT_STATUS="skipped"
fi

echo -e "${GREEN}[OK]${NC} Project type: ${PROJECT_TYPE}"
echo ""

# Step 2: Check/install tools
echo -e "${BLUE}[Step 2/6]${NC} Verifying tools..."
TOOLS_OK=false
if [ "$PROJECT_TYPE" == "nextjs" ]; then
    # Check for ESLint (Next.js)
    if npx eslint --version &> /dev/null; then
        TOOLS_OK=true
    fi
else
    # Check for PHPStan (Drupal)
    if ddev exec vendor/bin/phpstan --version &> /dev/null; then
        TOOLS_OK=true
    fi
fi

if [ "$TOOLS_OK" != "true" ]; then
    echo -e "${YELLOW}[INFO]${NC} Installing missing tools..."
    "${SCRIPT_DIR}/install-tools.sh" || true
fi
echo -e "${GREEN}[OK]${NC} Tools available"
echo ""

# Initialize aggregated report. overall_score starts at "unknown", not "pass": this
# skeleton is what a consumer reads if the run dies before the summary jq below (every
# per-gate merge jq is a bare command under `set -e`, so a gate emitting malformed JSON
# kills the script and leaves this file exactly as written). It must not read as a pass.
TIMESTAMP=$(date -Iseconds)
cat > "${REPORT_DIR}/audit-report.json" << EOF
{
  "meta": {
    "project_type": "${PROJECT_TYPE}",
    "project_path": "$(pwd)",
    "version_drift": "${VERSION_DRIFT}",
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
    "overall_score": "unknown",
    "coverage_score": "unknown",
    "solid_score": "unknown",
    "lint_score": "unknown",
    "dry_score": "unknown",
    "security_score": "unknown",
    "critical_issues": 0,
    "warnings": 0,
    "suggestions": 0
  },
  "coverage": {},
  "solid": {"violations": [], "metrics": {}},
  "dry": {"clones": []},
  "security": {},
  "tdd": {},
  "recommendations": []
}
EOF

# Determine script directory based on project type
case "$PROJECT_TYPE" in
    drupal|monorepo)
        SCRIPTS_DIR="${SKILL_DIR}/drupal"
        ;;
    nextjs)
        SCRIPTS_DIR="${SKILL_DIR}/nextjs"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Unknown project type: ${PROJECT_TYPE}"
        exit 2
        ;;
esac

echo -e "${GREEN}[OK]${NC} Using scripts from: ${SCRIPTS_DIR}"
echo ""

# Step 3: Run coverage check
echo -e "${BLUE}[Step 3/6]${NC} Running coverage analysis..."
COVERAGE_STATUS="unknown"
if [ -f "${SCRIPTS_DIR}/coverage-report.sh" ]; then
    if "${SCRIPTS_DIR}/coverage-report.sh" 2>/dev/null; then
        COVERAGE_STATUS="pass"
    else
        exit_code=$?
        if [ $exit_code -eq 1 ]; then
            COVERAGE_STATUS="warning"
            WARNING_COUNT=$((WARNING_COUNT + 1))
        else
            COVERAGE_STATUS="fail"
            CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
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

# Step 4: Run SOLID analysis (both Drupal and Next.js have solid-check.sh)
echo -e "${BLUE}[Step 4/6]${NC} Running SOLID analysis..."
SOLID_STATUS="unknown"
if [ -f "${SCRIPTS_DIR}/solid-check.sh" ]; then
    # solid-check.sh exits 0 for BOTH "pass" and "skipped", so its exit code cannot
    # express the difference and reading it alone records a gate that covered no ground
    # as a clean pass. The gate now downgrades itself to "skipped" when an analyzer was
    # present and returned nothing usable (tools_failed[]) — that downgrade is worthless
    # unless the aggregate can see it, because "skipped" is what caps a would-be pass at
    # "warning" in resolve_overall_status below.
    #
    # Same mechanism the security gate already uses: take the verdict from the report
    # the gate writes, fall back to the exit code only when the report yields none.
    #
    # Clearing any previous report first is what makes reading it sound. Without this, a
    # gate that dies before writing is judged by the LAST run's report, so a stale
    # "pass" survives a crash — a false clean built out of the fix for one. `|| true`
    # because an unwritable report directory must not take the audit down under `set -e`.
    rm -f "${REPORT_DIR}/solid-report.json" 2>/dev/null || true
    solid_exit=0
    "${SCRIPTS_DIR}/solid-check.sh" 2>/dev/null || solid_exit=$?
    SOLID_STATUS=""
    if [ -f "${REPORT_DIR}/solid-report.json" ]; then
        SOLID_STATUS=$(jq -r '.status // empty' \
            "${REPORT_DIR}/solid-report.json" 2>/dev/null || true)
    fi
    if [ -z "$SOLID_STATUS" ]; then
        # No usable verdict — no report, or one too malformed to read. Judge by the exit
        # code rather than by "unknown": the gate DID run, and "unknown" is the bucket
        # for gates that never ran, which carries no consequence at the aggregate.
        case "$solid_exit" in
            0) SOLID_STATUS="pass" ;;
            1) SOLID_STATUS="warning" ;;
            *) SOLID_STATUS="fail" ;;
        esac
    fi
    case "$SOLID_STATUS" in
        warning) WARNING_COUNT=$((WARNING_COUNT + 1)) ;;
        fail)    CRITICAL_COUNT=$((CRITICAL_COUNT + 1)) ;;
    esac
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

# Step 4b: Run lint check for Next.js (ESLint + TypeScript)
#
# Next.js only, and not by design as far as anything in this repository states:
# scripts/drupal/lint-check.sh exists and is a full phpcs/phpcbf gate, but no Drupal
# path reaches it, so an /audit of a Drupal project never runs a coding-standards check
# at all. Left as-is here on purpose rather than widened as a side effect of an
# unrelated fix — see the note in resolve_overall_status above.
LINT_STATUS="unknown"
if [ "$PROJECT_TYPE" == "nextjs" ]; then
    echo ""
    echo -e "${BLUE}[Step 4b]${NC} Running lint analysis (ESLint + TypeScript)..."
    if [ -f "${SCRIPTS_DIR}/lint-check.sh" ]; then
        if "${SCRIPTS_DIR}/lint-check.sh" 2>/dev/null; then
            LINT_STATUS="pass"
        else
            exit_code=$?
            if [ $exit_code -eq 1 ]; then
                LINT_STATUS="warning"
                WARNING_COUNT=$((WARNING_COUNT + 1))
            else
                LINT_STATUS="fail"
                CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
            fi
        fi
        update_status "$LINT_STATUS"

        # Merge lint report
        if [ -f "${REPORT_DIR}/lint-report.json" ]; then
            jq -s '.[0] * {lint: .[1]}' \
                "${REPORT_DIR}/audit-report.json" \
                "${REPORT_DIR}/lint-report.json" \
                > "${REPORT_DIR}/audit-report.tmp.json"
            mv "${REPORT_DIR}/audit-report.tmp.json" "${REPORT_DIR}/audit-report.json"
        fi
    else
        echo -e "${YELLOW}[SKIP]${NC} Lint script not found"
    fi
    echo -e "Lint: $([ "$LINT_STATUS" == "pass" ] && echo "${GREEN}PASS${NC}" || echo "${YELLOW}${LINT_STATUS}${NC}")"
fi
echo ""

# Step 5: Run DRY check
echo -e "${BLUE}[Step 5/6]${NC} Running DRY analysis..."
DRY_STATUS="unknown"
if [ -f "${SCRIPTS_DIR}/dry-check.sh" ]; then
    if "${SCRIPTS_DIR}/dry-check.sh" 2>/dev/null; then
        DRY_STATUS="pass"
    else
        exit_code=$?
        if [ $exit_code -eq 1 ]; then
            DRY_STATUS="warning"
            WARNING_COUNT=$((WARNING_COUNT + 1))
        else
            DRY_STATUS="fail"
            CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
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

# Step 6: Run security audit (Drupal only)
SECURITY_STATUS="unknown"
if [ "$PROJECT_TYPE" == "drupal" ] || [ "$PROJECT_TYPE" == "monorepo" ]; then
    echo -e "${BLUE}[Step 6/6]${NC} Running security audit..."
    if [ -f "${SCRIPTS_DIR}/security-check.sh" ]; then
        # security-check.sh does not use the 0/1/2 convention the other gates use:
        # it exits 0 for BOTH pass and warning, and 1 for fail. Reading its exit code
        # like a sibling gate records a failing scan as "warning" and a warning as
        # "pass". Take the verdict from the report it writes, which carries the
        # authoritative value, and fall back to the exit code only if no report exists
        # (the scan aborted before writing one).
        security_exit=0
        "${SCRIPTS_DIR}/security-check.sh" 2>/dev/null || security_exit=$?
        if [ -f "${REPORT_DIR}/security-report.json" ]; then
            SECURITY_STATUS=$(jq -r '.summary.overall_status // "unknown"' \
                "${REPORT_DIR}/security-report.json" 2>/dev/null || echo "unknown")
        elif [ "$security_exit" -eq 0 ]; then
            SECURITY_STATUS="pass"
        else
            SECURITY_STATUS="fail"
        fi
        case "$SECURITY_STATUS" in
            warning) WARNING_COUNT=$((WARNING_COUNT + 1)) ;;
            fail)    CRITICAL_COUNT=$((CRITICAL_COUNT + 1)) ;;
        esac
        update_status "$SECURITY_STATUS"

        # Merge security report
        if [ -f "${REPORT_DIR}/security-report.json" ]; then
            jq -s '.[0] * {security: .[1]}' \
                "${REPORT_DIR}/audit-report.json" \
                "${REPORT_DIR}/security-report.json" \
                > "${REPORT_DIR}/audit-report.tmp.json"
            mv "${REPORT_DIR}/audit-report.tmp.json" "${REPORT_DIR}/audit-report.json"
        fi
    else
        echo -e "${YELLOW}[SKIP]${NC} Security script not found"
    fi
    echo -e "Security: $([ "$SECURITY_STATUS" == "pass" ] && echo "${GREEN}PASS${NC}" || echo "${YELLOW}${SECURITY_STATUS}${NC}")"
    echo ""
fi

# A verdict of "pass" requires that at least one gate produced a result AND that no
# gate reported it could not cover its ground. A gate that explicitly skipped caps the
# audit at "warning": the run is incomplete, and an incomplete run cannot certify a pass.
# DRIFT_STATUS rides along with the five gate verdicts because it is the same kind of
# claim: a run that could not cover its ground. It contributes nothing when there is no
# drift ("unknown"), and caps a would-be pass at "warning" when there is.
OVERALL_STATUS=$(resolve_overall_status "$OVERALL_STATUS" \
    "$COVERAGE_STATUS" "$SOLID_STATUS" "$LINT_STATUS" "$DRY_STATUS" "$SECURITY_STATUS" \
    "$DRIFT_STATUS")

# Update summary in report
jq --arg overall "$OVERALL_STATUS" \
   --arg coverage "$COVERAGE_STATUS" \
   --arg solid "$SOLID_STATUS" \
   --arg lint "$LINT_STATUS" \
   --arg dry "$DRY_STATUS" \
   --arg security "$SECURITY_STATUS" \
   --argjson critical "$CRITICAL_COUNT" \
   --argjson warnings "$WARNING_COUNT" \
   --argjson suggestions "$SUGGESTION_COUNT" \
   '.summary.overall_score = $overall |
    .summary.coverage_score = $coverage |
    .summary.solid_score = $solid |
    .summary.lint_score = $lint |
    .summary.dry_score = $dry |
    .summary.security_score = $security |
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
if [ "$PROJECT_TYPE" == "nextjs" ]; then
    echo "  Lint:      ${LINT_STATUS}"
fi
echo "  DRY:       ${DRY_STATUS}"
if [ "$PROJECT_TYPE" == "drupal" ] || [ "$PROJECT_TYPE" == "monorepo" ]; then
    echo "  Security:  ${SECURITY_STATUS}"
fi
echo ""
echo "  Critical:  ${CRITICAL_COUNT}"
echo "  Warnings:  ${WARNING_COUNT}"
echo ""
echo -e "  Overall:   $([ "$OVERALL_STATUS" == "pass" ] && echo "${GREEN}PASS${NC}" || ([ "$OVERALL_STATUS" == "warning" ] && echo "${YELLOW}WARNING${NC}" || ([ "$OVERALL_STATUS" == "fail" ] && echo "${RED}FAIL${NC}" || echo "${YELLOW}UNKNOWN - no gate produced a result${NC}")))"
# Name the reason when the verdict was capped, so "WARNING" with zero warnings counted
# is not a puzzle. Only gates that ran and declared incomplete coverage cap it.
if [ "$DRIFT_STATUS" = "skipped" ]; then
    echo -e "             ${YELLOW}(the installed code does not match composer.lock - every gate above examined a tree that cannot be trusted, so this run cannot certify a pass)${NC}"
fi
for capped_gate in "coverage:${COVERAGE_STATUS}" "SOLID:${SOLID_STATUS}" \
    "lint:${LINT_STATUS}" "DRY:${DRY_STATUS}" "security:${SECURITY_STATUS}"; do
    if [ "${capped_gate#*:}" = "skipped" ]; then
        echo -e "             ${YELLOW}(the ${capped_gate%%:*} gate covered no ground - this run cannot certify a pass)${NC}"
    fi
done
echo ""
echo "  Reports:"
echo "    JSON: ${REPORT_DIR}/audit-report.json"
echo "    Markdown: ${REPORT_DIR}/audit-report.md"
echo ""

# Exit with appropriate code. "unknown" exits non-zero: nothing ran, so the run
# cannot claim success. It shares the warning code rather than the fail code so a
# caller gating on "not a failure" behaves as it did before.
case "$OVERALL_STATUS" in
    pass) exit 0 ;;
    warning) exit 1 ;;
    fail) exit 2 ;;
    *) exit 1 ;;
esac
