#!/bin/bash
# security-check.sh - Run comprehensive security audit (OWASP, Drupal-specific)
# Part of code-quality-audit skill

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
cqt_report_dir_init
cqt_announce_report_dir
# Phase 2 of secret scanning: for a secret phase 1 already found, when did it enter
# history and by whom. Shared with nextjs/security-check.sh so both stacks answer the
# question the same way. See the file header for why the matched value never reaches
# a file, a log line or any process's argv.
# shellcheck source=../core/secret-history.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/secret-history.sh"
DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"
DRUPAL_THEMES_PATH="${DRUPAL_THEMES_PATH:-web/themes/custom}"

# ── host filesystem vs container filesystem ───────────────────────────────────
#
# Nearly every in-container tool here writes to STDOUT and is captured by a host-side
# redirection. The `> "$FILE"` in those lines runs in THIS shell, on the host, so $FILE is
# a host path and the call works whatever REPORT_DIR is.
#
# Psalm is the exception. It writes its findings out of band, to the path given to
# --report=, and that path is read by the CONTAINER. The container shares one directory
# with the host — the bind mount at /var/www/html, which is the audited repository — so a
# host-absolute REPORT_DIR names nothing the container can write and nothing the host can
# read back. It worked only while REPORT_DIR was the relative `.reports`, i.e. only while
# this tool wrote into the repository it was auditing; with the out-of-repo default the
# taint gate quietly stops producing a report at all and is recorded as a skipped tool on
# every run. Same defect, same fix, same reasoning as drupal/coverage-report.sh: the
# container writes somewhere container-local and the bytes cross on ddev exec's stdout.
#
# $$ is the host PID, so two audits of one project do not collide in there.
CQT_CONTAINER_STAGE="/tmp/cqt-security-$$"

# Bring a file the container wrote across to the host. Never fatal, and never left behind
# empty: a transport that exits 0 having delivered nothing would be read downstream as an
# analyzer that ran and found nothing, which is the false-clean shape this gate exists to
# refuse. Returns non-zero when nothing usable arrived, and the caller's existing
# missing-report handling takes it from there.
cqt_fetch_from_container() {
    local src="$1" dest="$2"
    ddev exec test -s "${src}" >/dev/null 2>&1 || return 1
    ddev exec cat "${src}" > "${dest}" 2>/dev/null || { rm -f "${dest}" 2>/dev/null; return 1; }
    [ -s "${dest}" ] || { rm -f "${dest}" 2>/dev/null; return 1; }
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

# Resolve the gate verdict from the severity counts AND the coverage of the scan.
#
# A verdict of "pass" is a claim that the tree is clean, and that claim is only
# supportable when the scan covered its ground. A suite where most analyzers were absent
# reports zero findings because it did not look, not because there is nothing to find.
# Any tool recorded as absent therefore downgrades a would-be "pass" to "skipped" — the
# value the --changed envelope already uses for "this gate produced no result to trust".
#
# Only a would-be pass is downgraded. "warning" and "fail" already say the tree is not
# clean, and they carry findings the partial scan did produce; rewriting them as
# "skipped" would discard real evidence. A finding is a finding whatever else failed
# to run.
#
# The narrower rule — downgrade only when a whole CATEGORY (secrets, dependencies,
# taint) is left uncovered — was considered and rejected: it needs a category map that
# must be kept in sync with every tool added, and it blesses "one of the two secret
# scanners ran" as full coverage. Stating absence plainly costs nothing operationally,
# because "skipped" keeps the exit 0 that a pass would have had.
#
# Self-contained on purpose (reads no globals, echoes the verdict) so the spec can
# extract and source it in isolation.
#   resolve_security_status <critical> <high> <medium> <skipped_tool_count>
resolve_security_status() {
    local critical="$1" high="$2" medium="$3" skipped="$4"
    if [ "$critical" -gt 0 ]; then
        echo "fail"
    elif [ "$high" -gt 3 ]; then
        echo "fail"
    elif [ "$high" -gt 0 ] || [ "$medium" -gt 10 ]; then
        echo "warning"
    elif [ "$skipped" -gt 0 ]; then
        echo "skipped"
    else
        echo "pass"
    fi
}

# Drop any report left by an earlier run, before the tool gets a chance to write a new
# one. A failed run writes no report, and a report from an earlier successful run would
# then be parsed as if it were this run's result. Sets TOOL_STALE=1 when the old report
# could not be removed, which leaves this run's result unprovable.
#
# Only needed for analyzers that write out of band (psalm --report, trivy --output).
# The others are shell redirections, which truncate the file before the tool runs.
#
# Call this from inside a `set +e` bracket: `rm` fails on an unwritable report directory,
# and under `set -e` that would abort the entire security audit mid-scan.
clear_stale_report() {
    TOOL_STALE=0
    rm -f "$1" 2>/dev/null
    if [ -e "$1" ]; then
        TOOL_STALE=1
    fi
    return 0
}

# Decide which of three outcomes an analyzer produced, and how many findings it reported:
#
#   TOOL_FAILED=0 TOOL_COUNT=0   it ran and found nothing
#   TOOL_FAILED=0 TOOL_COUNT=N   it ran and found N things
#   TOOL_FAILED=1                it did not produce a usable result
#
# Byte-identical to the helper in nextjs/security-check.sh, deliberately: the two gates
# claim to reach the same verdict from the same evidence, and that claim is only true if
# they classify a tool's outcome the same way.
#
# An exit status alone cannot decide this. For some tools a non-zero exit means "found
# things" and for others it means "failed to run", and several write a well-formed report
# even when they failed — so the count has to be read out of the report and checked, not
# swallowed into a zero. A zero that came from a tool that never ran is a clean result
# nobody earned. Each caller states its own threshold because the tools disagree; see the
# comment at each call site for what was verified about that tool.
#
# DO NOT "tidy" the thresholds into a single consistent value. They differ because the
# evidence differs, and flattening them re-introduces a defect this branch has now hit
# four separate times (gitleaks fatalling through os.Exit(1), npm ENOLOCK writing a
# well-formed error document, eslint exiting 1 on ordinary lint errors, semgrep exiting
# 0 with its real problem in .errors):
#   fail_from 1    semgrep, trivy — those exact binaries' exit tables were verified
#                  (semgrep 1.172.0, trivy 0.73.0), and neither changes its status on
#                  findings, so ANY non-zero really does mean the run failed.
#   fail_from 126  php-security-linter, psalm, security_review — exit tables NOT verified
#                  here, and psalm and drush both exit non-zero when they FIND something.
#                  A low threshold there would convert every real finding into a fake
#                  "tool failed". Only shell-level failures (126/127, 128+N) are read
#                  from the status; the report decides everything else.
#
# $1 report path, $2 the tool's exit status, $3 the lowest exit status that means "failed
# to run" for this tool, $4 the jq expression that counts findings in the report.
resolve_tool_result() {
    local report="$1" exit_status="$2" fail_from="$3" count_expr="$4"
    local count

    TOOL_FAILED=0
    TOOL_COUNT=0

    if [ "${TOOL_STALE:-0}" -eq 1 ]; then
        TOOL_FAILED=1
        return 0
    fi

    if [ "$exit_status" -ge "$fail_from" ]; then
        TOOL_FAILED=1
        return 0
    fi

    # Every one of these tools emits a JSON document on a run that completed — an empty
    # findings list is still a document — so a missing or empty report means the run did
    # not complete, whatever it exited. For the redirection-based callers this is true by
    # construction: `> file` creates the file before the tool runs, so an empty file means
    # the tool produced no output at all.
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

# Turn `grep -Hn` output into one issue object per hit, carrying the real file and
# line. Callers derive their severity count from the length of this array so the
# counters and issues[] cannot disagree.
# Usage: pattern_issues "<grep output>" <category> <severity> <message> <owasp> <remediation>
pattern_issues() {
    printf '%s\n' "$1" | jq -R -s \
        --arg category "$2" \
        --arg severity "$3" \
        --arg message "$4" \
        --arg owasp "$5" \
        --arg remediation "$6" '
        split("\n")
        | map(select(length > 0))
        | map(select(test("^[^:]+:[0-9]+:")))
        | map(capture("^(?<file>[^:]+):(?<line>[0-9]+):"))
        | map({
            category: $category,
            severity: $severity,
            file: .file,
            line: (.line | tonumber),
            message: $message,
            owasp: $owasp,
            remediation: $remediation
          })' 2>/dev/null || echo "[]"
}

echo "=== Security Audit (OWASP + Drupal) ==="
echo ""

# Check jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} jq is required but not installed"
    exit 2
fi

# Initialize counters
CRITICAL_COUNT=0
HIGH_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0
ISSUES="[]"

# Create temp directory for individual reports
mkdir -p "${REPORT_DIR}/security"

# Parse command line arguments
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
# --changed mode: SAST-only (semgrep + php-security-linter + grep patterns)
# Advisory layers (drush pm:security, Psalm taint, Trivy, Security Review,
# Gitleaks, Roave) are whole-project — skipped under --changed with a note.
# composer audit runs ONLY when composer.json|composer.lock is in the list.
# =====================
if [ -n "$CHANGED_FILE" ]; then
    echo "[changed mode] SAST-only scan scoped to files listed in: ${CHANGED_FILE}"
    echo ""

    # PHP/Twig extensions for SAST
    LINTABLE_EXTS="\.php$|\.module$|\.inc$|\.install$|\.profile$|\.theme$|\.engine$|\.twig$|\.js$"

    # Filter: keep relevant extensions, exclude vendor/core/contrib
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

    # Composer files in changed set — triggers composer audit
    HAS_COMPOSER=false
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if echo "$f" | grep -qE '(^|/)composer\.(json|lock)$'; then
            HAS_COMPOSER=true
            break
        fi
    done < "$CHANGED_FILE"

    # Advisory-layer skip note (recorded in messages[])
    ADVISORY_SKIP_NOTE="Advisory layers (drush pm:security, Psalm taint, Trivy, Security Review, Gitleaks, Roave) are whole-project scans — skipped under --changed mode. Run the full security-check.sh without --changed for a complete audit."

    if [ "${#RELEVANT_FILES[@]}" -eq 0 ] && [ "$HAS_COMPOSER" = false ]; then
        echo -e "${GREEN}[SKIP]${NC} No relevant files in the changed set — clean skip."
        jq -n \
            --arg note "$ADVISORY_SKIP_NOTE" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
                meta: {
                    timestamp: $ts,
                    scan_type: "security_audit_changed",
                    mode: "changed",
                    tools_run: [],
                    tools_skipped: ["drush_pm_security","composer_audit","phpcs_security_linter","psalm_taint","security_review","semgrep","trivy","gitleaks","roave"]
                },
                summary: {
                    overall_status: "skipped",
                    total_issues: 0,
                    by_severity: {critical:0,high:0,medium:0,low:0}
                },
                messages: [$note],
                issues: []
            }' > "${REPORT_DIR}/security-report.json"
        exit 0
    fi

    # Changed set has real SAST work to do — DDEV is required from here
    if ! ddev describe &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} DDEV is not running"
        exit 2
    fi

    echo "Relevant SAST files (${#RELEVANT_FILES[@]}):"
    printf '  %s\n' "${RELEVANT_FILES[@]}"
    echo ""

    SEMGREP_ISSUES="[]"
    PHPCS_ISSUES="[]"
    CUSTOM_ISSUES="[]"
    COMPOSER_VIOLATIONS="[]"

    # Tool-availability tracking: which SAST analyzers ran vs were absent.
    # absence ≠ failure; if NO analyzer runs the gate verdict is "skipped" (exit 0).
    SKIPPED_TOOLS=()
    # The tools that were never installed. Most analyzers here are optional by design and
    # missing on a normal machine, so their absence is expected and must NOT bear on the
    # verdict: treating "never installed" as failed coverage would put every real run at
    # "skipped", and a verdict that fires on every run carries no information.
    #
    # The tools that DID fail are derived as SKIPPED_TOOLS minus ABSENT_TOOLS rather than
    # listed a second time by hand. Two consequences, both wanted: the failed list cannot
    # drift out of sync with the recorded skips, and the default is fail-CLOSED — a tool
    # that records a skip counts against the verdict unless a branch explicitly declares its
    # absence expected. drush pm:security and composer audit have no absent branch at all
    # (DDEV is a hard prerequisite here), so a failure in either is correctly a failure.
    ABSENT_TOOLS=()
    RAN_ANALYZERS=0

    # =====================
    # [1] Semgrep SAST — changed files only
    # =====================
    echo -e "${BLUE}[SAST 1/3]${NC} Running Semgrep SAST (changed files)..."
    SEMGREP_JSON="${REPORT_DIR}/security/semgrep.json"

    if [ "${#RELEVANT_FILES[@]}" -gt 0 ]; then
        # Pick the runner by where semgrep ACTUALLY is, not by whether DDEV is up.
        # The old guard was `in-container OR on-host` and then dispatched on `ddev
        # describe`, so semgrep installed on the host but not in the container passed the
        # guard and was then invoked inside the container, where it does not exist. That
        # used to fail quietly; now that a non-zero semgrep exit is a recorded failure it
        # would fail CI on a perfectly reasonable setup.
        SEMGREP_RUNNER=""
        if ddev exec semgrep --version &> /dev/null; then
            SEMGREP_RUNNER="container"
        elif command -v semgrep &> /dev/null; then
            SEMGREP_RUNNER="host"
        fi

        if [ -n "$SEMGREP_RUNNER" ]; then
            RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
            set +e
            if [ "$SEMGREP_RUNNER" = "container" ]; then
                # shellcheck disable=SC2046
                ddev exec semgrep scan --config=auto --json \
                    "${RELEVANT_FILES[@]}" > "$SEMGREP_JSON" 2>/dev/null
            else
                # shellcheck disable=SC2046
                semgrep scan --config=auto --json \
                    "${RELEVANT_FILES[@]}" > "$SEMGREP_JSON" 2>/dev/null
            fi
            SEMGREP_EXIT=$?
            set -e

            # Verified against semgrep 1.172.0: findings do NOT change the exit status
            # unless --error is passed, so exit 0 means it ran and ANY non-zero means it
            # failed. It still writes a report in those cases, with results empty and the
            # real problem in .errors, so the report alone reads as a clean tree. This is
            # the CI/pre-merge path, so an unread exit here is a false clean on every
            # merge.
            resolve_tool_result "$SEMGREP_JSON" "$SEMGREP_EXIT" 1 \
                '[.results[] | select(.extra.severity == "ERROR" or .extra.severity == "WARNING")] | length'

            if [ "$TOOL_FAILED" -eq 1 ]; then
                echo -e "  ${YELLOW}[SKIP]${NC} semgrep produced no usable report (exit ${SEMGREP_EXIT})"
                SKIPPED_TOOLS+=("semgrep")
            else
                VULN_COUNT="$TOOL_COUNT"
                if [ "$VULN_COUNT" -gt 0 ]; then
                    echo -e "  ${YELLOW}Found ${VULN_COUNT} Semgrep findings${NC}"
                    SEMGREP_ISSUES=$(jq '[.results[] | {
                        category: "Semgrep SAST",
                        severity: (if .extra.severity == "ERROR" then "high" elif .extra.severity == "WARNING" then "medium" else "low" end),
                        file: .path,
                        line: .start.line,
                        message: .extra.message,
                        owasp: (.extra.metadata.owasp // "N/A" | if type == "array" then join(", ") else . end),
                        remediation: (.extra.fix // "Review and fix the security issue")
                    }]' "$SEMGREP_JSON" 2>/dev/null || echo "[]")

                    SEMGREP_HIGH=$(echo "$SEMGREP_ISSUES" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
                    SEMGREP_MEDIUM=$(echo "$SEMGREP_ISSUES" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
                    SEMGREP_LOW=$(echo "$SEMGREP_ISSUES" | jq '[.[] | select(.severity == "low")] | length' 2>/dev/null || echo "0")
                    HIGH_COUNT=$((HIGH_COUNT + SEMGREP_HIGH))
                    MEDIUM_COUNT=$((MEDIUM_COUNT + SEMGREP_MEDIUM))
                    LOW_COUNT=$((LOW_COUNT + SEMGREP_LOW))
                else
                    echo -e "  ${GREEN}No Semgrep issues${NC}"
                fi
            fi
        else
            echo -e "  ${YELLOW}[SKIP]${NC} semgrep not installed (tool absent)"
            SKIPPED_TOOLS+=("semgrep")
            ABSENT_TOOLS+=("semgrep")
        fi
    else
        # No eligible files is a real non-result and has to land in a bucket like any
        # other, or a scan that examined nothing reports the same "pass" as one that
        # examined everything. Expected, so it does not move the verdict.
        echo -e "  ${YELLOW}No SAST-eligible files — skipping Semgrep${NC}"
        SKIPPED_TOOLS+=("semgrep")
        ABSENT_TOOLS+=("semgrep")
    fi

    # =====================
    # [2] php-security-linter — changed files only
    # =====================
    echo ""
    echo -e "${BLUE}[SAST 2/3]${NC} Running PHPCS security linter (changed files)..."
    PHPCS_SECURITY_JSON="${REPORT_DIR}/security/phpcs-security.json"

    if [ "${#RELEVANT_FILES[@]}" -gt 0 ]; then
        if ddev exec test -f vendor/bin/php-security-linter &> /dev/null; then
            RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
            set +e
            # shellcheck disable=SC2046
            ddev exec vendor/bin/php-security-linter scan \
                "${RELEVANT_FILES[@]}" \
                --format=json \
                2>/dev/null > "$PHPCS_SECURITY_JSON"
            PHPCS_SEC_EXIT=$?
            set -e

            # Exit table for yousha/php-security-linter not verified here, so only a
            # shell-level failure is read from the status; the report decides the rest.
            # The redirection creates the file before the tool runs, so an empty file
            # means it emitted nothing at all.
            resolve_tool_result "$PHPCS_SECURITY_JSON" "$PHPCS_SEC_EXIT" 126 \
                '[.files // {} | to_entries[] | .value.messages[]] | length'

            if [ "$TOOL_FAILED" -eq 1 ]; then
                echo -e "  ${YELLOW}[SKIP]${NC} php-security-linter produced no usable report (exit ${PHPCS_SEC_EXIT})"
                SKIPPED_TOOLS+=("php-security-linter")
                PHPCS_ISSUES="[]"
            else
                PHPCS_ISSUES=$(jq '[.files // {} | to_entries[] | .key as $file | .value.messages[] | {
                    category: ("PHPCS Security - " + (.source // "Unknown")),
                    severity: (if .type == "ERROR" then "high" else "medium" end),
                    file: $file,
                    line: .line,
                    message: .message,
                    owasp: "Various",
                    remediation: "Fix security issue in code"
                }]' "$PHPCS_SECURITY_JSON" 2>/dev/null || echo "[]")

                PHPCS_COUNT=$(echo "$PHPCS_ISSUES" | jq 'length' 2>/dev/null || echo "0")
                if [ "$PHPCS_COUNT" -gt 0 ]; then
                    echo -e "  ${YELLOW}Found ${PHPCS_COUNT} PHPCS security issues${NC}"
                    PHPCS_HIGH=$(echo "$PHPCS_ISSUES" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
                    PHPCS_MED=$(echo "$PHPCS_ISSUES" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
                    HIGH_COUNT=$((HIGH_COUNT + PHPCS_HIGH))
                    MEDIUM_COUNT=$((MEDIUM_COUNT + PHPCS_MED))
                else
                    echo -e "  ${GREEN}No PHPCS security issues${NC}"
                fi
            fi
        else
            echo -e "  ${YELLOW}[SKIP]${NC} php-security-linter not installed (tool absent)"
            SKIPPED_TOOLS+=("php-security-linter")
            ABSENT_TOOLS+=("php-security-linter")
        fi
    else
        echo -e "  ${YELLOW}No SAST-eligible files — skipping php-security-linter${NC}"
        SKIPPED_TOOLS+=("php-security-linter")
        ABSENT_TOOLS+=("php-security-linter")
    fi

    # =====================
    # [3] Custom grep patterns — scoped to changed files only
    # =====================
    echo ""
    echo -e "${BLUE}[SAST 3/3]${NC} Checking custom Drupal security patterns (changed files)..."

    if [ "${#RELEVANT_FILES[@]}" -gt 0 ]; then
        # grep-based pattern scan is always available — a real check that runs.
        RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
        # -H is required: with a single changed file, grep -n omits the filename and
        # the parsed "file" would be the line number.
        DB_QUERY_UNSAFE=$(grep -EHn 'db_query([^"]*"[^"]*\$|.*\.[[:space:]]*\$)' "${RELEVANT_FILES[@]}" 2>/dev/null || true)
        if [ -n "$DB_QUERY_UNSAFE" ]; then
            DB_ISSUES=$(pattern_issues "$DB_QUERY_UNSAFE" \
                "SQL Injection Risk" "high" \
                "Potentially unsafe db_query() with variable concatenation" \
                "A03:2021" "Use placeholders or query builder")
            DB_COUNT=$(echo "$DB_ISSUES" | jq 'length')
            if [ "$DB_COUNT" -gt 0 ]; then
                echo -e "  ${YELLOW}Found ${DB_COUNT} potentially unsafe db_query() calls${NC}"
                HIGH_COUNT=$((HIGH_COUNT + DB_COUNT))
                CUSTOM_ISSUES=$(echo "$CUSTOM_ISSUES" | jq --argjson add "$DB_ISSUES" '. + $add')
            fi
        fi

        # Twig |raw filter. Basic regex on purpose: under -E the '|' would be alternation.
        RAW_FILTER=$(grep -Hn "|raw" "${RELEVANT_FILES[@]}" 2>/dev/null || true)
        if [ -n "$RAW_FILTER" ]; then
            RAW_ISSUES=$(pattern_issues "$RAW_FILTER" \
                "XSS Risk" "medium" \
                "Use of |raw filter may expose XSS vulnerabilities" \
                "A03:2021" "Remove |raw or ensure input is sanitized")
            RAW_COUNT=$(echo "$RAW_ISSUES" | jq 'length')
            if [ "$RAW_COUNT" -gt 0 ]; then
                echo -e "  ${YELLOW}Found ${RAW_COUNT} uses of |raw filter${NC}"
                MEDIUM_COUNT=$((MEDIUM_COUNT + RAW_COUNT))
                CUSTOM_ISSUES=$(echo "$CUSTOM_ISSUES" | jq --argjson add "$RAW_ISSUES" '. + $add')
            fi
        fi

        # unserialize() on user input
        UNSERIALIZE=$(grep -Hn "unserialize.*\$_" "${RELEVANT_FILES[@]}" 2>/dev/null || true)
        if [ -n "$UNSERIALIZE" ]; then
            UNSER_ISSUES=$(pattern_issues "$UNSERIALIZE" \
                "Insecure Deserialization" "high" \
                "unserialize() on user input can lead to RCE" \
                "A08:2021" "Use JSON or validate serialized data")
            UNSER_COUNT=$(echo "$UNSER_ISSUES" | jq 'length')
            if [ "$UNSER_COUNT" -gt 0 ]; then
                echo -e "  ${YELLOW}Found ${UNSER_COUNT} potentially unsafe unserialize() calls${NC}"
                HIGH_COUNT=$((HIGH_COUNT + UNSER_COUNT))
                CUSTOM_ISSUES=$(echo "$CUSTOM_ISSUES" | jq --argjson add "$UNSER_ISSUES" '. + $add')
            fi
        fi

        if [ "$CUSTOM_ISSUES" = "[]" ]; then
            echo -e "  ${GREEN}No custom pattern violations${NC}"
        fi
    else
        echo -e "  ${YELLOW}No SAST-eligible files — skipping custom patterns${NC}"
        SKIPPED_TOOLS+=("custom_patterns")
        ABSENT_TOOLS+=("custom_patterns")
    fi

    # =====================
    # composer audit — runs ONLY when composer.json|lock is in the changed set
    # =====================
    echo ""
    if [ "$HAS_COMPOSER" = true ]; then
        echo -e "${BLUE}[ADVISORY]${NC} composer.json|lock changed — running composer audit..."
        RAN_ANALYZERS=$((RAN_ANALYZERS + 1))
        COMPOSER_AUDIT_JSON="${REPORT_DIR}/security/composer-audit.json"
        set +e
        # `ddev exec composer`, not `ddev composer`: composer audit exits 1 whenever it
        # finds advisories, and `ddev composer` treats any non-zero exit as a failed
        # command — it prints its own error and emits nothing on stdout. The file would
        # be empty and this block would report "unavailable" exactly when there IS
        # something to report. `ddev exec` passes stdout through unchanged.
        # No --locked: that audits composer.lock instead of the installed tree, so on a
        # drifted checkout it audits a declaration rather than the code that runs.
        ddev exec composer audit --format=json > "$COMPOSER_AUDIT_JSON" 2>/dev/null
        COMPOSER_EXIT=$?
        set -e

        # Exit status cannot discriminate here: composer audit exits 1 both when it
        # finds advisories and when it fails outright. Only a PARSEABLE report can, so
        # the status is carried for diagnostics and parseability decides the verdict.
        COMPOSER_FAILED=0
        if [ -f "$COMPOSER_AUDIT_JSON" ] && [ -s "$COMPOSER_AUDIT_JSON" ]; then
            set +e
            VULN_COUNT=$(jq '[.advisories // {} | to_entries[]] | length' "$COMPOSER_AUDIT_JSON" 2>/dev/null)
            JQ_EXIT=$?
            set -e
            # A present-but-unparseable report is not evidence of a clean tree.
            if [ "$JQ_EXIT" -ne 0 ] || ! [[ "$VULN_COUNT" =~ ^[0-9]+$ ]]; then
                COMPOSER_FAILED=1
                VULN_COUNT=0
            fi
        else
            # composer audit writes a JSON document whenever it can run at all,
            # whatever its exit status, so no output means it did not run.
            COMPOSER_FAILED=1
            VULN_COUNT=0
        fi

        if [ "$COMPOSER_FAILED" -eq 1 ]; then
            echo -e "  ${YELLOW}[SKIP]${NC} composer audit produced no usable report (exit ${COMPOSER_EXIT})"
            SKIPPED_TOOLS+=("composer_audit")
        elif [ "$VULN_COUNT" -gt 0 ]; then
            echo -e "  ${RED}Found ${VULN_COUNT} package vulnerabilities${NC}"
            COMPOSER_VIOLATIONS=$(jq '[.advisories // {} | to_entries[] | .value[] | {
                category: "Composer Vulnerability",
                severity: (if .severity == "high" or .severity == "critical" then "high" else "medium" end),
                file: .packageName,
                line: 0,
                message: (.title + " (" + .cve + ")"),
                owasp: "A06:2021",
                remediation: .link
            }]' "$COMPOSER_AUDIT_JSON" 2>/dev/null || echo "[]")

            HIGH_VULNS=$(echo "$COMPOSER_VIOLATIONS" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
            MED_VULNS=$(echo "$COMPOSER_VIOLATIONS" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
            HIGH_COUNT=$((HIGH_COUNT + HIGH_VULNS))
            MEDIUM_COUNT=$((MEDIUM_COUNT + MED_VULNS))
        else
            echo -e "  ${GREEN}No package vulnerabilities${NC}"
        fi
    else
        # Scoped out by design in this mode, but still a layer that produced nothing.
        echo -e "${YELLOW}[SKIP]${NC} composer audit — composer.json/lock not in changed set"
        SKIPPED_TOOLS+=("composer_audit")
        ABSENT_TOOLS+=("composer_audit")
    fi

    # =====================
    # Combine SAST issues
    # =====================
    ISSUES=$(jq -n \
        --argjson composer "$COMPOSER_VIOLATIONS" \
        --argjson phpcs "$PHPCS_ISSUES" \
        --argjson semgrep "$SEMGREP_ISSUES" \
        --argjson custom "$CUSTOM_ISSUES" \
        '$composer + $phpcs + $semgrep + $custom')

    # Status. If NO SAST analyzer ran (every analyzer absent + no eligible files),
    # degrade to "skipped" (exit 0) rather than a hollow PASS. Otherwise the verdict
    # comes from the checks that DID run, and from whether a tool that WAS there failed
    # to report. Tool absence never inverts pass↔fail and never downgrades on its own:
    # SKIPPED_TOOLS holds both kinds here, and ABSENT_TOOLS names the ones whose absence
    # was expected, so the difference is what bears on the verdict. The whole-project
    # layers this mode omits by design are declared separately again, in tools_skipped
    # and the advisory note.
    # tools_absent[] and tools_failed[] are DISJOINT, and each name means exactly what it
    # says. tools_absent = the layer never ran and that was expected (tool not installed,
    # nothing eligible to scan, target path absent) — it does not move the verdict.
    # tools_failed = the layer was there and returned nothing usable (crashed, unparseable
    # report, stale report) — a zero from it is not evidence, so it downgrades a would-be
    # pass to "skipped". Every non-produced result lands in exactly one of the two; the
    # union is "everything this scan did not cover".
    SKIPPED_TOOLS_JSON=$(to_json_array "${SKIPPED_TOOLS[@]+"${SKIPPED_TOOLS[@]}"}")
    ABSENT_TOOLS_JSON=$(to_json_array "${ABSENT_TOOLS[@]+"${ABSENT_TOOLS[@]}"}")
    FAILED_TOOLS_JSON=$(jq -n --argjson skipped "$SKIPPED_TOOLS_JSON" \
        --argjson absent "$ABSENT_TOOLS_JSON" '$skipped - $absent')
    FAILED_COUNT=$(echo "$FAILED_TOOLS_JSON" | jq 'length')

    if [ "$RAN_ANALYZERS" -eq 0 ]; then
        OVERALL_STATUS="skipped"
    else
        OVERALL_STATUS=$(resolve_security_status \
            "$CRITICAL_COUNT" "$HIGH_COUNT" "$MEDIUM_COUNT" "$FAILED_COUNT")
    fi

    REPORT_FILE="${REPORT_DIR}/security-report.json"
    jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg status "$OVERALL_STATUS" \
        --argjson critical "$CRITICAL_COUNT" \
        --argjson high "$HIGH_COUNT" \
        --argjson medium "$MEDIUM_COUNT" \
        --argjson low "$LOW_COUNT" \
        --argjson issues "$ISSUES" \
        --argjson analyzers_ran "$RAN_ANALYZERS" \
        --argjson tools_absent "$ABSENT_TOOLS_JSON" \
        --argjson tools_failed "$FAILED_TOOLS_JSON" \
        --arg advisory_note "$ADVISORY_SKIP_NOTE" \
        '{
            meta: {
                timestamp: $timestamp,
                scan_type: "security_audit_changed",
                mode: "changed",
                analyzers_ran: $analyzers_ran,
                tools_run: ["semgrep","phpcs_security_linter","custom_patterns","composer_audit_on_lock_change"],
                tools_absent: $tools_absent,
                tools_failed: $tools_failed,
                tools_skipped: ["drush_pm_security","psalm_taint","security_review","trivy","gitleaks","roave"]
            },
            summary: {
                overall_status: $status,
                total_issues: ($critical + $high + $medium + $low),
                by_severity: {
                    critical: $critical,
                    high: $high,
                    medium: $medium,
                    low: $low
                }
            },
            messages: [$advisory_note],
            thresholds: {
                critical: {pass: 0, warning: 0, fail: ">0"},
                high: {pass: 0, warning: "1-3", fail: ">3"},
                medium: {pass: 0, warning: "1-10", fail: ">10"},
                low: {pass: 0, warning: "any", fail: ">20"}
            },
            issues: $issues
        }' > "$REPORT_FILE"

    echo ""
    echo "=== Security Audit Summary (changed mode) ==="
    echo ""
    echo -e "SAST layers: semgrep, php-security-linter, custom patterns$([ "$HAS_COMPOSER" = true ] && echo ", composer audit")"
    echo -e "Skipped:     drush pm:security, Psalm taint, Trivy, Security Review, Gitleaks, Roave"
    echo ""
    echo -e "Critical: ${CRITICAL_COUNT}"
    echo -e "High:     ${HIGH_COUNT}"
    echo -e "Medium:   ${MEDIUM_COUNT}"
    echo -e "Low:      ${LOW_COUNT}"
    echo ""

    if [ "$OVERALL_STATUS" = "skipped" ]; then
        if [ "$RAN_ANALYZERS" -eq 0 ]; then
            echo -e "${YELLOW}[SKIP]${NC} No security SAST analyzers available (all tools absent) — gate skipped"
        else
            # Zero findings from an incomplete scan. Reported as a skip rather than a
            # pass because the analyzers that were absent found nothing by not looking.
            echo -e "${YELLOW}[SKIP]${NC} No findings, but ${FAILED_COUNT} installed tool(s) returned no usable result — coverage incomplete, not a clean verdict"
            echo -e "Tools that failed: $(echo "$FAILED_TOOLS_JSON" | jq -r 'join(", ")')"
        fi
        echo -e "Report: ${REPORT_FILE}"
        exit 0
    elif [ "$OVERALL_STATUS" = "pass" ]; then
        echo -e "${GREEN}[PASS]${NC} Security SAST passed"
        exit 0
    elif [ "$OVERALL_STATUS" = "warning" ]; then
        echo -e "${YELLOW}[WARN]${NC} Security SAST passed with warnings"
        echo -e "Report: ${REPORT_FILE}"
        exit 0
    else
        echo -e "${RED}[FAIL]${NC} Security SAST failed"
        echo -e "Report: ${REPORT_FILE}"
        exit 1
    fi
fi

# =====================
# Standard (no --changed) path — byte-identical to original logic
# =====================

# Check DDEV (standard path always requires a running site)
if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
    exit 2
fi

# Every analyzer that contributed no counts, whatever the reason. Reported as
# tools_absent[] so a reader can see which layers this scan did not include.
SKIPPED_TOOLS=()

# The tools that were never installed. Most analyzers here are optional by design and
# missing on a normal machine, so their absence is expected and must NOT bear on the
# verdict: treating "never installed" as failed coverage would put every real run at
# "skipped", and a verdict that fires on every run carries no information.
#
# The tools that DID fail are derived as SKIPPED_TOOLS minus ABSENT_TOOLS rather than
# listed a second time by hand. Two consequences, both wanted: the failed list cannot
# drift out of sync with the recorded skips, and the default is fail-CLOSED — a tool
# that records a skip counts against the verdict unless a branch explicitly declares its
# absence expected. drush pm:security and composer audit have no absent branch at all
# (DDEV is a hard prerequisite here), so a failure in either is correctly a failure.
ABSENT_TOOLS=()


echo -e "${BLUE}[1/10]${NC} Checking Drupal security advisories..."
# =====================
# Drush pm:security
# =====================
DRUSH_SECURITY_JSON="${REPORT_DIR}/security/drush-security.json"
set +e
# `ddev exec drush`, not `ddev drush`: the same swallow class as composer audit.
# drush pm:security exits non-zero when it finds advisories, and `ddev drush` treats
# any non-zero exit as a failed command, printing its own error and emitting nothing
# on stdout. `ddev exec` passes stdout through unchanged.
ddev exec drush pm:security --format=json > "$DRUSH_SECURITY_JSON" 2>/dev/null
DRUSH_EXIT=$?
set -e

# As with composer audit, the exit status cannot tell "found advisories" apart from
# "failed to run". Parseability decides; the status is carried for diagnostics.
# Ordering here is SAFETY-CRITICAL and deliberately not the same as the other layers.
#
# drush pm:security has no not-installed branch (DDEV is a hard prerequisite), so
# anything classed as a failure here lands in tools_failed, degrades the gate to
# "skipped", caps /audit at "warning" and exits 1. If "wrote nothing" were the failure
# signal, then a healthy Drupal site with ZERO advisories — the overwhelmingly common
# case, and the primary target platform — would fail its audit on every run. drush
# commands can legitimately return early and print nothing when a result set is empty.
#
# So empty output is NOT read as failure. A parseable report decides when there is one;
# otherwise a clean exit means "ran, found nothing" and only a non-zero exit WITH no
# usable output is a failure. On a healthy site the gate therefore reaches pass whether
# drush prints "[]" or prints nothing at all.
#
# UNVERIFIED, and stated so it can be confirmed: whether `drush pm:security
# --format=json` emits an empty JSON document or emits nothing on an advisory-free site
# could not be checked here, because it needs a live DDEV project. This branch is
# written so that BOTH answers reach the same, correct verdict. It errs OPEN for drush
# specifically: a drush that fails while exiting 0 would be read as clean. That is the
# deliberate trade — erring closed here breaks every healthy site, which is a worse and
# far more likely failure than the case it would catch.
DRUSH_FAILED=0
ADVISORY_COUNT=0
if [ -f "$DRUSH_SECURITY_JSON" ] && [ -s "$DRUSH_SECURITY_JSON" ]; then
    set +e
    ADVISORY_COUNT=$(jq 'length' "$DRUSH_SECURITY_JSON" 2>/dev/null)
    JQ_EXIT=$?
    set -e
    if [ "$JQ_EXIT" -ne 0 ] || ! [[ "$ADVISORY_COUNT" =~ ^[0-9]+$ ]]; then
        DRUSH_FAILED=1
        ADVISORY_COUNT=0
    fi
elif [ "$DRUSH_EXIT" -eq 0 ]; then
    # Ran to completion and printed nothing: no advisories.
    ADVISORY_COUNT=0
else
    # Non-zero AND nothing usable to read. Nothing was learned about this site.
    DRUSH_FAILED=1
    ADVISORY_COUNT=0
fi

if [ "$DRUSH_FAILED" -eq 1 ]; then
    echo -e "  ${YELLOW}[SKIP]${NC} drush pm:security produced no usable report (exit ${DRUSH_EXIT})"
    SKIPPED_TOOLS+=("drush_pm_security")
    DRUSH_VIOLATIONS="[]"
elif [ "$ADVISORY_COUNT" -gt 0 ]; then
    echo -e "  ${RED}Found ${ADVISORY_COUNT} security advisories${NC}"

    # Convert to violations format
    DRUSH_VIOLATIONS=$(jq '[.[] | {
        category: "Drupal Security Advisory",
        severity: "critical",
        file: .name,
        line: 0,
        message: (.title + " - " + .link),
        owasp: "A06:2021",
        remediation: "Update to recommended version: \(.recommended)"
    }]' "$DRUSH_SECURITY_JSON" 2>/dev/null || echo "[]")

    CRITICAL_COUNT=$((CRITICAL_COUNT + ADVISORY_COUNT))
else
    echo -e "  ${GREEN}No security advisories${NC}"
    DRUSH_VIOLATIONS="[]"
fi

echo ""
echo -e "${BLUE}[2/10]${NC} Checking composer package vulnerabilities..."
# =====================
# Composer audit
# =====================
COMPOSER_AUDIT_JSON="${REPORT_DIR}/security/composer-audit.json"
set +e
# `ddev exec composer`, not `ddev composer`: composer audit exits 1 whenever it finds
# advisories, and `ddev composer` treats any non-zero exit as a failed command — it
# prints its own error and emits nothing on stdout. The file would be empty and this
# block would report "unavailable" exactly when there IS something to report.
# `ddev exec` passes stdout through unchanged.
#
# Deliberately NOT --locked. That audits composer.lock instead of the installed
# packages, so on a drifted checkout — a lock declaring one version while vendor/ and
# the docroot hold another, which happens after a failed composer install — it audits
# a declaration rather than the code that actually runs, and can report clean while a
# vulnerable package sits in vendor/. Lock-vs-installed drift is its own problem and
# is tracked separately; auditing the installed tree is the security-correct default.
ddev exec composer audit --format=json > "$COMPOSER_AUDIT_JSON" 2>/dev/null
COMPOSER_EXIT=$?
set -e

# Exit status cannot discriminate here: composer audit exits 1 both when it finds
# advisories and when it fails outright. Only a PARSEABLE report can, so the status is
# carried for diagnostics and parseability decides the verdict.
COMPOSER_FAILED=0
if [ -f "$COMPOSER_AUDIT_JSON" ] && [ -s "$COMPOSER_AUDIT_JSON" ]; then
    set +e
    VULN_COUNT=$(jq '[.advisories // {} | to_entries[]] | length' "$COMPOSER_AUDIT_JSON" 2>/dev/null)
    JQ_EXIT=$?
    set -e
    # A present-but-unparseable report is not evidence of a clean tree. Swallowing
    # jq's failure into 0 would print the clean message while the tool said nothing.
    if [ "$JQ_EXIT" -ne 0 ] || ! [[ "$VULN_COUNT" =~ ^[0-9]+$ ]]; then
        COMPOSER_FAILED=1
        VULN_COUNT=0
    fi
else
    # composer audit writes a JSON document whenever it can run at all, whatever its
    # exit status, so no output means it did not run.
    COMPOSER_FAILED=1
    VULN_COUNT=0
fi

if [ "$COMPOSER_FAILED" -eq 1 ]; then
    echo -e "  ${YELLOW}[SKIP]${NC} composer audit produced no usable report (exit ${COMPOSER_EXIT})"
    SKIPPED_TOOLS+=("composer_audit")
    COMPOSER_VIOLATIONS="[]"
elif [ "$VULN_COUNT" -gt 0 ]; then
    echo -e "  ${RED}Found ${VULN_COUNT} package vulnerabilities${NC}"

    # Convert to violations format
    COMPOSER_VIOLATIONS=$(jq '[.advisories // {} | to_entries[] | .value[] | {
        category: "Composer Vulnerability",
        severity: (if .severity == "high" or .severity == "critical" then "high" else "medium" end),
        file: .packageName,
        line: 0,
        message: (.title + " (" + .cve + ")"),
        owasp: "A06:2021",
        remediation: .link
    }]' "$COMPOSER_AUDIT_JSON" 2>/dev/null || echo "[]")

    # Count by severity
    HIGH_VULNS=$(echo "$COMPOSER_VIOLATIONS" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
    MED_VULNS=$(echo "$COMPOSER_VIOLATIONS" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
    HIGH_COUNT=$((HIGH_COUNT + HIGH_VULNS))
    MEDIUM_COUNT=$((MEDIUM_COUNT + MED_VULNS))
else
    echo -e "  ${GREEN}No package vulnerabilities${NC}"
    COMPOSER_VIOLATIONS="[]"
fi

echo ""
echo -e "${BLUE}[3/10]${NC} Running PHPCS security linter (OWASP/CIS)..."
# =====================
# yousha/php-security-linter
# =====================
PHPCS_SECURITY_JSON="${REPORT_DIR}/security/phpcs-security.json"

if ddev exec test -f vendor/bin/php-security-linter &> /dev/null; then
    set +e
    ddev exec vendor/bin/php-security-linter scan \
        "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}" \
        --format=json \
        2>/dev/null > "$PHPCS_SECURITY_JSON"
    PHPCS_SEC_EXIT=$?
    set -e

    # The exit table for yousha/php-security-linter was not verified here, so only a
    # shell-level failure (126/127, 128+N) is read from the status; everything else is
    # decided by the report. It writes a JSON document whenever it runs, and the
    # redirection above creates the file before it starts, so an empty file means it
    # produced no output at all.
    resolve_tool_result "$PHPCS_SECURITY_JSON" "$PHPCS_SEC_EXIT" 126 \
        '[.files // {} | to_entries[] | .value.messages[]] | length'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "  ${YELLOW}[SKIP]${NC} php-security-linter produced no usable report (exit ${PHPCS_SEC_EXIT})"
        SKIPPED_TOOLS+=("php-security-linter")
        PHPCS_ISSUES="[]"
    else
        PHPCS_ISSUES=$(jq '[.files // {} | to_entries[] | .key as $file | .value.messages[] | {
            category: ("PHPCS Security - " + (.source // "Unknown")),
            severity: (if .type == "ERROR" then "high" else "medium" end),
            file: $file,
            line: .line,
            message: .message,
            owasp: "Various",
            remediation: "Fix security issue in code"
        }]' "$PHPCS_SECURITY_JSON" 2>/dev/null || echo "[]")

        PHPCS_COUNT=$(echo "$PHPCS_ISSUES" | jq 'length' 2>/dev/null || echo "0")
        if [ "$PHPCS_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${PHPCS_COUNT} PHPCS security issues${NC}"

            PHPCS_HIGH=$(echo "$PHPCS_ISSUES" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
            PHPCS_MED=$(echo "$PHPCS_ISSUES" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
            HIGH_COUNT=$((HIGH_COUNT + PHPCS_HIGH))
            MEDIUM_COUNT=$((MEDIUM_COUNT + PHPCS_MED))
        else
            echo -e "  ${GREEN}No PHPCS security issues${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} php-security-linter not installed (tool absent)"
    SKIPPED_TOOLS+=("php-security-linter")
    ABSENT_TOOLS+=("php-security-linter")
    PHPCS_ISSUES="[]"
fi

echo ""
echo -e "${BLUE}[4/10]${NC} Running Psalm taint analysis..."
# =====================
# Psalm taint analysis
# =====================
PSALM_TAINT_JSON="${REPORT_DIR}/security/psalm-taint.json"

if ddev exec test -f vendor/bin/psalm &> /dev/null; then
    # Check if psalm.xml exists, if not create minimal config
    if ! ddev exec test -f psalm.xml &> /dev/null; then
        echo -e "  ${YELLOW}Creating minimal psalm.xml${NC}"
        cat > psalm.xml <<'EOF'
<?xml version="1.0"?>
<psalm
    errorLevel="7"
    resolveFromConfigFile="true"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns="https://getpsalm.org/schema/config"
    xsi:schemaLocation="https://getpsalm.org/schema/config vendor/vimeo/psalm/config.xsd"
>
    <projectFiles>
        <directory name="web/modules/custom" />
        <directory name="web/themes/custom" />
        <ignoreFiles>
            <directory name="vendor" />
        </ignoreFiles>
    </projectFiles>
</psalm>
EOF
    fi

    set +e
    # psalm writes out of band via --report, so a report from an earlier run would
    # otherwise be read as this run's result.
    clear_stale_report "$PSALM_TAINT_JSON"
    # --report is read by the CONTAINER; PSALM_TAINT_JSON is a HOST path. See the
    # host/container note at the top of this file.
    PSALM_TAINT_CONTAINER="${CQT_CONTAINER_STAGE}/psalm-taint.json"
    ddev exec mkdir -p "${CQT_CONTAINER_STAGE}" >/dev/null 2>&1
    ddev exec vendor/bin/psalm --taint-analysis \
        --report="${PSALM_TAINT_CONTAINER}" \
        --output-format=json \
        --no-cache \
        2>/dev/null
    PSALM_EXIT=$?
    # Carried across before the status is judged. A psalm that wrote a report and exited
    # non-zero is a psalm that found taint, and the report has to be here for the
    # resolve_tool_result call below to read it.
    cqt_fetch_from_container "${PSALM_TAINT_CONTAINER}" "${PSALM_TAINT_JSON}"
    ddev exec rm -rf "${CQT_CONTAINER_STAGE}" >/dev/null 2>&1
    set -e

    # psalm exits non-zero when it finds issues, so the status cannot separate "found
    # taint" from "failed"; only a shell-level failure is read from it.
    #
    # UNVERIFIED ASSUMPTION, stated so it can be confirmed or narrowed: this treats a
    # missing or empty --report file as a FAILED run, which assumes psalm writes that
    # file whenever a run completes — including a run that finds nothing. That could not
    # be checked here because psalm is not installed in this environment. It is the only
    # one of the five where "no report" is not true by construction; the other four are
    # shell redirections, where `> file` creates the file before the tool starts.
    #
    # It errs CLOSED: if the assumption is wrong, a clean psalm run is reported as a
    # skipped tool and the gate says "incomplete" when it was actually complete. The code
    # this replaced erred OPEN — it printed "No taint analysis issues" for a psalm that
    # never ran. On a security gate, over-reporting incompleteness is the safe direction.
    # A maintainer with psalm installed should confirm the write-on-clean behaviour and
    # narrow this if it holds.
    resolve_tool_result "$PSALM_TAINT_JSON" "$PSALM_EXIT" 126 'length'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "  ${YELLOW}[SKIP]${NC} psalm produced no usable report (exit ${PSALM_EXIT})"
        SKIPPED_TOOLS+=("psalm")
        PSALM_ISSUES="[]"
    else
        # `|| echo "[]"` here would be a false clean in the OTHER direction: this
        # transform can fail on a report full of REAL findings, and swallowing that into
        # an empty array prints "No taint analysis issues" for a psalm that found taint.
        # `.type | contains("Sql")` is the specific hazard — psalm omits .type on some
        # issue shapes, and `null | contains(...)` aborts the whole expression, so one
        # such entry zeroes every finding in the file. Capture jq's status and treat a
        # transform failure as a failed run, the way the gitleaks block does.
        set +e
        PSALM_ISSUES=$(jq '[.[] | {
            category: ("Psalm Taint - " + (.type // "Unknown")),
            severity: (if (.severity // 0) <= 3 then "high" elif (.severity // 0) <= 5 then "medium" else "low" end),
            file: .file_path,
            line: .line_from,
            message: .message,
            owasp: (if ((.type // "") | contains("Sql")) then "A03:2021" elif ((.type // "") | contains("Html")) or ((.type // "") | contains("Xss")) then "A03:2021" else "Various" end),
            remediation: "Sanitize tainted input before use"
        }]' "$PSALM_TAINT_JSON" 2>/dev/null)
        PSALM_JQ_EXIT=$?
        set -e

        if [ "$PSALM_JQ_EXIT" -ne 0 ]; then
            echo -e "  ${YELLOW}[SKIP]${NC} psalm report could not be parsed into findings — taint results not counted"
            SKIPPED_TOOLS+=("psalm")
            PSALM_ISSUES="[]"
            PSALM_COUNT=0
        else

        PSALM_COUNT=$(echo "$PSALM_ISSUES" | jq 'length' 2>/dev/null || echo "0")
        if [ "$PSALM_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${PSALM_COUNT} taint analysis issues${NC}"

            PSALM_HIGH=$(echo "$PSALM_ISSUES" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
            PSALM_MED=$(echo "$PSALM_ISSUES" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
            PSALM_LOW=$(echo "$PSALM_ISSUES" | jq '[.[] | select(.severity == "low")] | length' 2>/dev/null || echo "0")
            HIGH_COUNT=$((HIGH_COUNT + PSALM_HIGH))
            MEDIUM_COUNT=$((MEDIUM_COUNT + PSALM_MED))
            LOW_COUNT=$((LOW_COUNT + PSALM_LOW))
        else
            echo -e "  ${GREEN}No taint analysis issues${NC}"
        fi
        fi
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} psalm not installed (tool absent)"
    SKIPPED_TOOLS+=("psalm")
    ABSENT_TOOLS+=("psalm")
    PSALM_ISSUES="[]"
fi

echo ""
echo -e "${BLUE}[5/10]${NC} Checking custom Drupal security patterns..."
# =====================
# Custom Drupal Pattern Checks
# =====================
CUSTOM_ISSUES="[]"

# SQL Injection patterns
if [ -d "${DRUPAL_MODULES_PATH}" ]; then
    # Unsafe db_query usage. The pattern matches interpolation inside a double-quoted
    # first argument, or concatenation onto it, so the safe placeholder-array form
    # (db_query('... :id', [':id' => $id])) no longer counts as a finding.
    DB_QUERY_UNSAFE=$(grep -rEHn 'db_query([^"]*"[^"]*\$|.*\.[[:space:]]*\$)' "${DRUPAL_MODULES_PATH}" --include="*.php" --include="*.module" --include="*.inc" 2>/dev/null || true)
    if [ -n "$DB_QUERY_UNSAFE" ]; then
        DB_ISSUES=$(pattern_issues "$DB_QUERY_UNSAFE" \
            "SQL Injection Risk" "high" \
            "Potentially unsafe db_query() with variable concatenation" \
            "A03:2021" "Use placeholders or query builder")
        DB_COUNT=$(echo "$DB_ISSUES" | jq 'length')
        if [ "$DB_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${DB_COUNT} potentially unsafe db_query() calls${NC}"
            HIGH_COUNT=$((HIGH_COUNT + DB_COUNT))
            CUSTOM_ISSUES=$(echo "$CUSTOM_ISSUES" | jq --argjson add "$DB_ISSUES" '. + $add')
        fi
    fi

    # Twig |raw filter. Kept as a basic-regex grep: under -E the '|' would be alternation.
    RAW_FILTER=$(grep -rHn "|raw" "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}" --include="*.twig" 2>/dev/null || true)
    if [ -n "$RAW_FILTER" ]; then
        RAW_ISSUES=$(pattern_issues "$RAW_FILTER" \
            "XSS Risk" "medium" \
            "Use of |raw filter may expose XSS vulnerabilities" \
            "A03:2021" "Remove |raw or ensure input is sanitized")
        RAW_COUNT=$(echo "$RAW_ISSUES" | jq 'length')
        if [ "$RAW_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${RAW_COUNT} uses of |raw filter in Twig${NC}"
            MEDIUM_COUNT=$((MEDIUM_COUNT + RAW_COUNT))
            CUSTOM_ISSUES=$(echo "$CUSTOM_ISSUES" | jq --argjson add "$RAW_ISSUES" '. + $add')
        fi
    fi

    # unserialize() on user input
    UNSERIALIZE=$(grep -rHn "unserialize.*\$_" "${DRUPAL_MODULES_PATH}" --include="*.php" --include="*.module" 2>/dev/null || true)
    if [ -n "$UNSERIALIZE" ]; then
        UNSER_ISSUES=$(pattern_issues "$UNSERIALIZE" \
            "Insecure Deserialization" "high" \
            "unserialize() on user input can lead to RCE" \
            "A08:2021" "Use JSON or validate serialized data")
        UNSER_COUNT=$(echo "$UNSER_ISSUES" | jq 'length')
        if [ "$UNSER_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${UNSER_COUNT} potentially unsafe unserialize() calls${NC}"
            HIGH_COUNT=$((HIGH_COUNT + UNSER_COUNT))
            CUSTOM_ISSUES=$(echo "$CUSTOM_ISSUES" | jq --argjson add "$UNSER_ISSUES" '. + $add')
        fi
    fi
fi

if [ ! -d "${DRUPAL_MODULES_PATH}" ]; then
    # The pattern layer scanned nothing because the configured path does not exist —
    # an empty site, or DRUPAL_MODULES_PATH pointing somewhere wrong. Either way it
    # produced no coverage and must say so instead of contributing a silent zero.
    # Recorded as expected: a site with no custom modules is a legitimate setup, so
    # this is visible in tools_absent without moving the verdict.
    echo -e "  ${YELLOW}[SKIP]${NC} ${DRUPAL_MODULES_PATH} does not exist — no custom code scanned"
    SKIPPED_TOOLS+=("custom_patterns")
    ABSENT_TOOLS+=("custom_patterns")
elif [ "$CUSTOM_ISSUES" = "[]" ]; then
    echo -e "  ${GREEN}No custom pattern violations${NC}"
fi

echo ""
echo -e "${BLUE}[6/10]${NC} Running Security Review module..."
# =====================
# Security Review module (if installed)
# =====================
SECREVIEW_JSON="${REPORT_DIR}/security/security-review.json"

if ddev drush pm:list --filter=security_review --format=json 2>/dev/null | jq -e '.security_review' &> /dev/null; then
    set +e
    ddev drush security-review --format=json > "$SECREVIEW_JSON" 2>/dev/null
    SECREVIEW_EXIT=$?
    set -e

    # drush security-review reports failing checks as data, not as an exit status, and
    # the drush exit table was not verified here — so only a shell-level failure is read
    # from the status and the report decides the rest. The redirection creates the file
    # before drush runs, so an empty file means it emitted nothing.
    resolve_tool_result "$SECREVIEW_JSON" "$SECREVIEW_EXIT" 126 \
        '[.[] | select(.result == "fail")] | length'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "  ${YELLOW}[SKIP]${NC} security-review produced no usable report (exit ${SECREVIEW_EXIT})"
        SKIPPED_TOOLS+=("security_review")
        SECREVIEW_ISSUES="[]"
    else
        FAILED_CHECKS="$TOOL_COUNT"
        if [ "$FAILED_CHECKS" -gt 0 ]; then
            echo -e "  ${YELLOW}${FAILED_CHECKS} security review checks failed${NC}"

            SECREVIEW_ISSUES=$(jq '[.[] | select(.result == "fail") | {
                category: "Drupal Configuration",
                severity: "medium",
                file: "Configuration",
                line: 0,
                message: (.title + ": " + (.findings[0] // "Review required")),
                owasp: "A05:2021",
                remediation: "Check Drupal security review report"
            }]' "$SECREVIEW_JSON" 2>/dev/null || echo "[]")

            MEDIUM_COUNT=$((MEDIUM_COUNT + FAILED_CHECKS))
        else
            echo -e "  ${GREEN}All security review checks passed${NC}"
            SECREVIEW_ISSUES="[]"
        fi
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} security_review module not installed (tool absent)"
    SKIPPED_TOOLS+=("security_review")
    ABSENT_TOOLS+=("security_review")
    SECREVIEW_ISSUES="[]"
fi

echo ""
echo -e "${BLUE}[7/10]${NC} Running Semgrep SAST (multi-language)..."
# =====================
# Semgrep SAST
# =====================
SEMGREP_JSON="${REPORT_DIR}/security/semgrep.json"
SEMGREP_ISSUES="[]"

# Pick the runner by where semgrep ACTUALLY is, not by whether DDEV is up. See the
# matching comment in the --changed branch: `in-container OR on-host` followed by a
# dispatch on `ddev describe` invokes a host-only semgrep inside the container.
SEMGREP_RUNNER=""
if ddev exec semgrep --version &> /dev/null; then
    SEMGREP_RUNNER="container"
elif command -v semgrep &> /dev/null; then
    SEMGREP_RUNNER="host"
fi

if [ -n "$SEMGREP_RUNNER" ]; then
    set +e
    # Run Semgrep with auto config (includes security rules)
    if [ "$SEMGREP_RUNNER" = "container" ]; then
        ddev exec semgrep scan --config=auto --json \
            "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}" > "$SEMGREP_JSON" 2>/dev/null
    else
        semgrep scan --config=auto --json \
            "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}" > "$SEMGREP_JSON" 2>/dev/null
    fi
    SEMGREP_EXIT=$?
    set -e

    # Verified against semgrep 1.172.0 (same fact the Next.js gate records): findings do
    # NOT change the exit status unless --error is passed, so exit 0 means it ran and ANY
    # non-zero means it failed. It still writes a report in those cases, with results
    # empty and the real problem in .errors, so the report alone reads as a clean tree.
    resolve_tool_result "$SEMGREP_JSON" "$SEMGREP_EXIT" 1 \
        '[.results[] | select(.extra.severity == "ERROR" or .extra.severity == "WARNING")] | length'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "  ${YELLOW}[SKIP]${NC} semgrep produced no usable report (exit ${SEMGREP_EXIT})"
        SKIPPED_TOOLS+=("semgrep")
    else
        VULN_COUNT="$TOOL_COUNT"
        if [ "$VULN_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${VULN_COUNT} Semgrep findings${NC}"

            # Convert to violations format
            SEMGREP_ISSUES=$(jq '[.results[] | {
                category: "Semgrep SAST",
                severity: (if .extra.severity == "ERROR" then "high" elif .extra.severity == "WARNING" then "medium" else "low" end),
                file: .path,
                line: .start.line,
                message: .extra.message,
                owasp: (.extra.metadata.owasp // "N/A" | if type == "array" then join(", ") else . end),
                remediation: (.extra.fix // "Review and fix the security issue")
            }]' "$SEMGREP_JSON" 2>/dev/null || echo "[]")

            # Update severity counts
            SEMGREP_HIGH=$(echo "$SEMGREP_ISSUES" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
            SEMGREP_MEDIUM=$(echo "$SEMGREP_ISSUES" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
            SEMGREP_LOW=$(echo "$SEMGREP_ISSUES" | jq '[.[] | select(.severity == "low")] | length' 2>/dev/null || echo "0")

            HIGH_COUNT=$((HIGH_COUNT + SEMGREP_HIGH))
            MEDIUM_COUNT=$((MEDIUM_COUNT + SEMGREP_MEDIUM))
            LOW_COUNT=$((LOW_COUNT + SEMGREP_LOW))
        else
            echo -e "  ${GREEN}No Semgrep issues${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} semgrep not installed (tool absent)"
    SKIPPED_TOOLS+=("semgrep")
    ABSENT_TOOLS+=("semgrep")
fi

echo ""
echo -e "${BLUE}[8/10]${NC} Running Trivy dependency/secret scanner..."
# =====================
# Trivy Scanner
# =====================
TRIVY_JSON="${REPORT_DIR}/security/trivy.json"
TRIVY_ISSUES="[]"

if command -v trivy &> /dev/null; then
    set +e
    # trivy writes out of band via --output, so clear any report from an earlier run.
    clear_stale_report "$TRIVY_JSON"
    # Run Trivy on filesystem (dependency + secret scanning)
    trivy fs --scanners vuln,secret --format json --output "$TRIVY_JSON" . 2>/dev/null
    TRIVY_EXIT=$?
    set -e

    # Verified against trivy 0.73.0 (same fact the Next.js gate records): findings do NOT
    # change the exit status unless --exit-code is passed, so exit 0 means it ran and ANY
    # non-zero means it failed. A bad scanner name, a missing target and an unwritable
    # --output all exit 1 and write no report at all.
    resolve_tool_result "$TRIVY_JSON" "$TRIVY_EXIT" 1 \
        '[.Results[]?.Vulnerabilities[]?, .Results[]?.Secrets[]?] | length'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "  ${YELLOW}[SKIP]${NC} trivy produced no usable report (exit ${TRIVY_EXIT})"
        SKIPPED_TOOLS+=("trivy")
    else
        VULN_COUNT="$TOOL_COUNT"
        if [ "$VULN_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${VULN_COUNT} Trivy findings${NC}"

            # Convert vulnerabilities to violations format
            TRIVY_VULN=$(jq '[.Results[]?.Vulnerabilities[]? | {
                category: "Trivy Vulnerability",
                severity: (if .Severity == "CRITICAL" then "critical" elif .Severity == "HIGH" then "high" elif .Severity == "MEDIUM" then "medium" else "low" end),
                file: .PkgName,
                line: 0,
                message: (.VulnerabilityID + ": " + .Title),
                owasp: "A06:2021",
                remediation: ("Update to " + (.FixedVersion // "latest version"))
            }]' "$TRIVY_JSON" 2>/dev/null || echo "[]")

            # Convert secrets to violations format
            TRIVY_SECRETS=$(jq '[.Results[]?.Secrets[]? | {
                category: "Trivy Secret Detection",
                severity: "critical",
                file: .Target,
                line: .StartLine,
                message: ("Potential secret detected: " + .Title),
                owasp: "A02:2021",
                remediation: "Remove secret from code and rotate credentials"
            }]' "$TRIVY_JSON" 2>/dev/null || echo "[]")

            # Combine and update counts
            TRIVY_ISSUES=$(jq -n --argjson vuln "$TRIVY_VULN" --argjson secrets "$TRIVY_SECRETS" '$vuln + $secrets')

            TRIVY_CRITICAL=$(echo "$TRIVY_ISSUES" | jq '[.[] | select(.severity == "critical")] | length' 2>/dev/null || echo "0")
            TRIVY_HIGH=$(echo "$TRIVY_ISSUES" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
            TRIVY_MEDIUM=$(echo "$TRIVY_ISSUES" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
            TRIVY_LOW=$(echo "$TRIVY_ISSUES" | jq '[.[] | select(.severity == "low")] | length' 2>/dev/null || echo "0")

            CRITICAL_COUNT=$((CRITICAL_COUNT + TRIVY_CRITICAL))
            HIGH_COUNT=$((HIGH_COUNT + TRIVY_HIGH))
            MEDIUM_COUNT=$((MEDIUM_COUNT + TRIVY_MEDIUM))
            LOW_COUNT=$((LOW_COUNT + TRIVY_LOW))
        else
            echo -e "  ${GREEN}No Trivy issues${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} trivy not installed (tool absent)"
    SKIPPED_TOOLS+=("trivy")
    ABSENT_TOOLS+=("trivy")
fi

echo ""
echo -e "${BLUE}[9/10]${NC} Running Gitleaks secret detection..."
# =====================
# Gitleaks Secret Detection
# =====================
GITLEAKS_JSON="${REPORT_DIR}/security/gitleaks.json"
GITLEAKS_ISSUES="[]"

if command -v gitleaks &> /dev/null; then
    set +e
    # Drop any report from a previous run: a failed run writes no report, and a stale
    # one would otherwise be parsed as if it were this run's result. This sits INSIDE
    # the set +e bracket because `rm` fails on an unwritable report directory, which
    # under set -e would abort the entire security gate. A stale report that cannot be
    # removed is itself the false-clean case, so it is treated as a failed run below
    # rather than trusted.
    rm -f "$GITLEAKS_JSON" 2>/dev/null
    GITLEAKS_STALE=0
    if [ -e "$GITLEAKS_JSON" ]; then
        GITLEAKS_STALE=1
    fi

    # Run Gitleaks on the repository. --redact keeps matched secret values out of the
    # report file, which is written inside the tree being audited.
    gitleaks detect --redact --report-format json --report-path "$GITLEAKS_JSON" --no-git 2>/dev/null
    GITLEAKS_EXIT=$?
    set -e

    # Exit status alone cannot tell "found leaks" from "failed to run". Verified against
    # gitleaks 8.30.1: exit 0 means it ran and found nothing, but exit 1 means EITHER it
    # found leaks OR it errored — a bad config, an unwritable --report-path, a missing
    # --source and a bad --report-format all exit 1, because gitleaks fatals through
    # os.Exit(1). Only a PARSEABLE report distinguishes the two. Exit >= 2 is a
    # shell-level failure (126/127, 128+N), which produces no report either.
    GITLEAKS_FAILED=0
    SECRET_COUNT=0

    if [ "$GITLEAKS_STALE" -eq 1 ]; then
        # A report from an earlier run could not be removed, so this run's report
        # cannot be told apart from it. Unprovable provenance is not a clean tree.
        GITLEAKS_FAILED=1
    elif [ "$GITLEAKS_EXIT" -ge 2 ]; then
        GITLEAKS_FAILED=1
    elif [ -f "$GITLEAKS_JSON" ] && [ -s "$GITLEAKS_JSON" ]; then
        set +e
        SECRET_COUNT=$(jq 'length' "$GITLEAKS_JSON" 2>/dev/null)
        JQ_EXIT=$?
        set -e
        # A report that is present but unparseable is not evidence of a clean tree.
        # Swallowing jq's failure into 0 would report clean while gitleaks is saying
        # the opposite.
        if [ "$JQ_EXIT" -ne 0 ] || ! [[ "$SECRET_COUNT" =~ ^[0-9]+$ ]]; then
            GITLEAKS_FAILED=1
            SECRET_COUNT=0
        fi
    elif [ "$GITLEAKS_EXIT" -ne 0 ]; then
        # Exit 1 with no report at all: gitleaks errored rather than found anything.
        GITLEAKS_FAILED=1
    fi

    if [ "$GITLEAKS_FAILED" -eq 1 ]; then
        echo -e "  ${YELLOW}[SKIP]${NC} gitleaks produced no usable report (exit ${GITLEAKS_EXIT})"
        SKIPPED_TOOLS+=("gitleaks")
    elif [ "$SECRET_COUNT" -gt 0 ]; then
        echo -e "  ${RED}Found ${SECRET_COUNT} potential secrets${NC}"

        # Convert to violations format
        GITLEAKS_ISSUES=$(jq '[.[] | {
            category: "Gitleaks Secret",
            severity: "critical",
            file: .File,
            line: .StartLine,
            message: ("Potential secret detected: " + .Description),
            owasp: "A02:2021",
            remediation: "Remove secret from code, rotate credentials, and use secret management"
        }]' "$GITLEAKS_JSON" 2>/dev/null || echo "[]")

        CRITICAL_COUNT=$((CRITICAL_COUNT + SECRET_COUNT))
    else
        echo -e "  ${GREEN}No secrets detected${NC}"
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} gitleaks not installed (tool absent)"
    SKIPPED_TOOLS+=("gitleaks")
    ABSENT_TOOLS+=("gitleaks")
fi

# =====================
# Secret history — phase 2, confirmation
# =====================
# Deliberately OUTSIDE the gitleaks block above. That block is the phase-1 scan of
# the working tree; this is a different job with a different failure mode, and
# neither must be able to take the other down.
#
# What it adds to each secret finding: first_seen_commit, first_seen_date, author
# and commit_count. Without them a finding is a location, and a location does not
# decide the remediation — never committed means edit the file, in history for two
# years means rotate at the provider and editing the file achieves nothing.
#
# It never moves the VERDICT (a secret is critical either way) and never records a
# skipped tool, so a project with no git history cannot turn a completed secret scan
# into an incomplete one. Every failure degrades to an explicit "could not check".
if [ "$GITLEAKS_ISSUES" != "[]" ]; then
    echo -e "  ${BLUE}[HISTORY]${NC} Confirming which findings already reached git history..."
    set +e
    GITLEAKS_HISTORY=$(cqt_secret_history_json "$GITLEAKS_JSON" ".")
    GITLEAKS_ISSUES=$(cqt_secret_history_attach "$GITLEAKS_ISSUES" "$GITLEAKS_HISTORY")
    set -e
    while IFS= read -r HISTORY_LINE; do
        [ -n "$HISTORY_LINE" ] && printf '    %s\n' "$HISTORY_LINE"
    done < <(cqt_secret_history_report "$GITLEAKS_ISSUES")
fi

echo ""
echo -e "${BLUE}[10/10]${NC} Verifying Roave Security Advisories (prevention layer)..."
# =====================
# Roave Security Advisories (Prevention Layer)
# =====================
ROAVE_ISSUES="[]"

if ddev composer show roave/security-advisories &> /dev/null; then
    echo -e "  ${GREEN}Roave Security Advisories is installed${NC}"
    echo -e "  ${BLUE}[INFO]${NC} Prevents installation of packages with known vulnerabilities"
    # Roave is installed - no issues to report (it prevents issues at install time)
else
    echo -e "  ${YELLOW}Roave Security Advisories not installed (recommended)${NC}"
    echo -e "  ${BLUE}[INFO]${NC} Install with: ddev composer require --dev roave/security-advisories:dev-master"

    # Add informational issue
    ROAVE_ISSUES=$(jq -n '[{
        category: "Roave Prevention Layer",
        severity: "low",
        file: "composer.json",
        line: 1,
        message: "Roave Security Advisories not installed - prevents vulnerable package installation",
        owasp: "A06:2021",
        remediation: "Run: ddev composer require --dev roave/security-advisories:dev-master"
    }]')

    LOW_COUNT=$((LOW_COUNT + 1))
fi

# =====================
# Combine all issues
# =====================
ISSUES=$(jq -n \
    --argjson drush "$DRUSH_VIOLATIONS" \
    --argjson composer "$COMPOSER_VIOLATIONS" \
    --argjson phpcs "$PHPCS_ISSUES" \
    --argjson psalm "$PSALM_ISSUES" \
    --argjson custom "$CUSTOM_ISSUES" \
    --argjson secreview "$SECREVIEW_ISSUES" \
    --argjson semgrep "$SEMGREP_ISSUES" \
    --argjson trivy "$TRIVY_ISSUES" \
    --argjson gitleaks "$GITLEAKS_ISSUES" \
    --argjson roave "$ROAVE_ISSUES" \
    '$drush + $composer + $phpcs + $psalm + $custom + $secreview + $semgrep + $trivy + $gitleaks + $roave')

# =====================
# Determine overall status
# =====================
# The severity counts are only half the verdict. The failed set — the analyzers that
# were present and still returned nothing usable — is what a zero cannot be trusted
# from. Absent-by-design tools stay in tools_absent[] and are reported, but they do not
# move the verdict; see resolve_security_status().
# tools_absent[] and tools_failed[] are DISJOINT, and each name means exactly what it
# says. tools_absent = the layer never ran and that was expected (tool not installed,
# nothing eligible to scan, target path absent) — it does not move the verdict.
# tools_failed = the layer was there and returned nothing usable (crashed, unparseable
# report, stale report) — a zero from it is not evidence, so it downgrades a would-be
# pass to "skipped". Every non-produced result lands in exactly one of the two; the
# union is "everything this scan did not cover".
SKIPPED_TOOLS_JSON=$(to_json_array "${SKIPPED_TOOLS[@]+"${SKIPPED_TOOLS[@]}"}")
ABSENT_TOOLS_JSON=$(to_json_array "${ABSENT_TOOLS[@]+"${ABSENT_TOOLS[@]}"}")
FAILED_TOOLS_JSON=$(jq -n --argjson skipped "$SKIPPED_TOOLS_JSON" \
    --argjson absent "$ABSENT_TOOLS_JSON" '$skipped - $absent')
FAILED_COUNT=$(echo "$FAILED_TOOLS_JSON" | jq 'length')

OVERALL_STATUS=$(resolve_security_status \
    "$CRITICAL_COUNT" "$HIGH_COUNT" "$MEDIUM_COUNT" "$FAILED_COUNT")

# =====================
# Generate final report
# =====================
REPORT_FILE="${REPORT_DIR}/security-report.json"

jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "$OVERALL_STATUS" \
    --argjson critical "$CRITICAL_COUNT" \
    --argjson high "$HIGH_COUNT" \
    --argjson medium "$MEDIUM_COUNT" \
    --argjson low "$LOW_COUNT" \
    --argjson issues "$ISSUES" \
    --argjson tools_absent "$ABSENT_TOOLS_JSON" \
    --argjson tools_failed "$FAILED_TOOLS_JSON" \
    '{
        meta: {
            timestamp: $timestamp,
            scan_type: "security_audit",
            tools: ["drush_pm_security", "composer_audit", "phpcs_security_linter", "psalm_taint", "custom_patterns", "security_review", "semgrep", "trivy", "gitleaks", "roave"],
            tools_absent: $tools_absent,
            tools_failed: $tools_failed
        },
        summary: {
            overall_status: $status,
            security_score: $status,
            total_issues: ($critical + $high + $medium + $low),
            by_severity: {
                critical: $critical,
                high: $high,
                medium: $medium,
                low: $low
            }
        },
        thresholds: {
            critical: {pass: 0, warning: 0, fail: ">0"},
            high: {pass: 0, warning: "1-3", fail: ">3"},
            medium: {pass: 0, warning: "1-10", fail: ">10"},
            low: {pass: 0, warning: "any", fail: ">20"}
        },
        issues: $issues
    }' > "$REPORT_FILE"

echo ""
echo "=== Security Audit Summary ==="
echo ""
echo -e "Critical: ${CRITICAL_COUNT}"
echo -e "High:     ${HIGH_COUNT}"
echo -e "Medium:   ${MEDIUM_COUNT}"
echo -e "Low:      ${LOW_COUNT}"
echo ""

if [ "$OVERALL_STATUS" = "skipped" ]; then
    # Zero findings, but the scan did not cover its ground. Exits 0 like the pass it
    # would otherwise have been — the consequence is carried by the status, which
    # full-audit.sh reads from the report and does not count as a produced result.
    echo -e "${YELLOW}⚠ Security audit incomplete — no findings, but ${FAILED_COUNT} installed tool(s) returned no usable result${NC}"
    echo -e "Tools that failed: $(echo "$FAILED_TOOLS_JSON" | jq -r 'join(", ")')"
    echo -e "Report: ${REPORT_FILE}"
    exit 0
elif [ "$OVERALL_STATUS" = "pass" ]; then
    echo -e "${GREEN}✓ Security audit passed${NC}"
    exit 0
elif [ "$OVERALL_STATUS" = "warning" ]; then
    echo -e "${YELLOW}⚠ Security audit passed with warnings${NC}"
    echo -e "Report: ${REPORT_FILE}"
    exit 0
else
    echo -e "${RED}✗ Security audit failed${NC}"
    echo -e "Report: ${REPORT_FILE}"
    exit 1
fi
