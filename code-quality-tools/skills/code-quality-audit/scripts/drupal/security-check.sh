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
# Phases 1 and 3: which ground the secret scan covers (working tree, a bounded
# commit range, or all of history), how each gitleaks command line is built, and how
# far a finding reaches once a build artifact is deployed to a second repository.
# Sourced unconditionally so a missing library is a loud failure here rather than a
# silently narrower scan later.
# shellcheck source=../core/secret-scan.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/secret-scan.sh"

# Where this project's custom code lives is answered in ONE place, for every gate. Both
# of these used to default to a web/ literal here, which on a docroot-layout (Acquia)
# project pointed every path-taking layer at directories detect-environment.sh had
# already ruled out — and, because the pattern layer is gated on the modules path
# existing, silently removed it from the scan altogether.
# shellcheck source=../core/path-resolve.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/path-resolve.sh"
cqt_resolve_drupal_paths

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

# Somebody else's code, vendored into this tree — the list cqt_vendor_excludes publishes,
# in the spelling semgrep takes. architecture/security-check.md committed this gate to
# three exclusions and only the pattern greps shipped: the semgrep invocations carried
# `--config=auto --json` and nothing else, so a node_modules bundle under a custom theme
# produced findings attributed to this project on both the whole-tree and --changed paths.
#
# Built once, used at both call sites, so the two cannot drift.
SEMGREP_EXCLUDES=()
while IFS= read -r _cqt_ex; do
    [ -n "$_cqt_ex" ] && SEMGREP_EXCLUDES+=("--exclude=${_cqt_ex}")
done < <(cqt_vendor_excludes)

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

    # What is not this project's code, expressed against THIS project's layout. The list
    # used to name web/core/, web/themes/contrib/ and web/modules/contrib/ — the same
    # literal that was replaced in lint-check.sh and solid-check.sh, left in place here.
    # On an Acquia project every changed path begins docroot/, so nothing matched and
    # Drupal core was handed to semgrep and the pattern layer as custom code. The core
    # prefix now comes from the resolved Drupal root, and everything else is matched
    # wherever it appears in the path rather than at one layout's spelling of it.
    CHANGED_ROOT_PREFIX="$(cqt_drupal_root_prefix)"
    [ -n "$CHANGED_ROOT_PREFIX" ] && CHANGED_ROOT_PREFIX="${CHANGED_ROOT_PREFIX}/"
    CHANGED_EXCLUDE_RE="^(vendor/|${CHANGED_ROOT_PREFIX}core/)|(^|/)(vendor|node_modules|bower_components|contrib)/"

    # Filter: keep relevant extensions, exclude vendor/core/contrib, and keep only what
    # is actually on disk.
    #
    # The on-disk filter is the same one lint-check.sh and solid-check.sh carry, and for
    # the same reason: semgrep, php-security-linter and the pattern greps are all handed
    # these paths directly and none of them can report on a file that is not there. A
    # changed set of deleted files used to reach them as nonexistent paths, and their
    # empty output was read exactly the way a clean scan is.
    RELEVANT_FILES=()
    MISSING_FILES=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if ! echo "$f" | grep -qE "$LINTABLE_EXTS"; then
            continue
        fi
        if echo "$f" | grep -qE "$CHANGED_EXCLUDE_RE"; then
            continue
        fi
        if [ -e "$f" ]; then
            RELEVANT_FILES+=("$f")
        else
            MISSING_FILES+=("$f")
        fi
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

    CHANGED_MISSING_JSON=$(printf '%s\n' "${MISSING_FILES[@]+"${MISSING_FILES[@]}"}" \
        | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

    # Named PHP files, none of them on disk. The gate was ASKED about them and cannot
    # answer, which is not the same question as a docs-only diff — and the branch below
    # answered both with a clean skip and exit 0. Every SAST layer here reads the file
    # list directly, so with nothing on disk all three had no ground: that is what
    # tools_unmeasured records, and it is the field the --changed branch declared and
    # never wrote.
    if [ "${#RELEVANT_FILES[@]}" -eq 0 ] && [ "${#MISSING_FILES[@]}" -gt 0 ] \
       && [ "$HAS_COMPOSER" = false ]; then
        cqt_unmeasured "every SAST-eligible file in the changed set is missing from disk — security was NOT checked" \
            "${MISSING_FILES[@]}"
        jq -n \
            --arg note "$ADVISORY_SKIP_NOTE" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg status "${CQT_STATUS_UNMEASURED}" \
            --argjson missing "$CHANGED_MISSING_JSON" \
            '{
                meta: {
                    timestamp: $ts,
                    scan_type: "security_audit_changed",
                    mode: "changed",
                    tools_run: [],
                    tools_absent: [],
                    tools_failed: [],
                    tools_unmeasured: ["semgrep","php-security-linter","custom_patterns"],
                    paths_missing: $missing,
                    tools_skipped: ["drush_pm_security","composer_audit","psalm","security_review","trivy","gitleaks","roave"]
                },
                summary: {
                    overall_status: $status,
                    total_issues: 0,
                    by_severity: {critical:0,high:0,medium:0,low:0}
                },
                messages: [$note],
                issues: []
            }' > "${REPORT_DIR}/security-report.json"
        exit "$CQT_EXIT_UNMEASURED"
    fi

    # Nothing in the diff this gate has any business reading — a docs-only or CSS-only
    # change. `overall_status: "skipped"` is the same word the standard path uses for the
    # very different state "the tools were here and returned nothing usable", so this
    # branch names its reason in meta.skip_reason. Without it a consumer cannot tell a
    # correctly scoped no-op from a scan that learned nothing it was supposed to learn,
    # and the safe reading of the ambiguity — fail closed — puts a red on every docs PR.
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
                    tools_absent: [],
                    tools_failed: [],
                    tools_unmeasured: [],
                    paths_missing: [],
                    tools_skipped: ["drush_pm_security","composer_audit","php-security-linter","psalm","security_review","semgrep","trivy","gitleaks","roave"],
                    skip_reason: "no_eligible_changes"
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
    # Layers whose TOOL was present but whose GROUND was not there. Distinct from both
    # neighbours: absent = not installed (a fact about the machine, expected, does not
    # move the verdict); failed = ran and returned nothing usable; unmeasured = never
    # asked, because the path it would have read does not exist. Filing the third under
    # the first is what let an audit of no custom code at all report a pass.
    UNMEASURED_TOOLS=()
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
    # Layers this mode did not run because the CHANGED SET gave them nothing to do:
    # composer audit with no composer.json/lock in the diff, the SAST layers with no
    # PHP in it. That is scoping working exactly as designed, and it is a different
    # fact from "the binary is not installed" — which is why it no longer shares a
    # list with it. These names join the by-design tools_skipped[] the mode already
    # emits; they are NOT a coverage gap and nothing downstream may read them as one.
    SCOPED_OUT_TOOLS=()
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
                    "${SEMGREP_EXCLUDES[@]}" \
                    "${RELEVANT_FILES[@]}" > "$SEMGREP_JSON" 2>/dev/null
            else
                # shellcheck disable=SC2046
                semgrep scan --config=auto --json \
                    "${SEMGREP_EXCLUDES[@]}" \
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
        if [ "${#MISSING_FILES[@]}" -gt 0 ]; then
            # The tool may well be here; the GROUND is not. Three different findings,
            # and filing this one under "absent" is what let a changed set of deleted
            # files read as expected coverage.
            echo -e "  ${YELLOW}[UNMEASURED]${NC} the changed files are not on disk — Semgrep had nothing to read"
            SKIPPED_TOOLS+=("semgrep")
            UNMEASURED_TOOLS+=("semgrep")
        else
            echo -e "  ${YELLOW}No SAST-eligible files — skipping Semgrep${NC}"
            SKIPPED_TOOLS+=("semgrep")
            SCOPED_OUT_TOOLS+=("semgrep")
        fi
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
        if [ "${#MISSING_FILES[@]}" -gt 0 ]; then
            # The tool may well be here; the GROUND is not. Three different findings,
            # and filing this one under "absent" is what let a changed set of deleted
            # files read as expected coverage.
            echo -e "  ${YELLOW}[UNMEASURED]${NC} the changed files are not on disk — php-security-linter had nothing to read"
            SKIPPED_TOOLS+=("php-security-linter")
            UNMEASURED_TOOLS+=("php-security-linter")
        else
            echo -e "  ${YELLOW}No SAST-eligible files — skipping php-security-linter${NC}"
            SKIPPED_TOOLS+=("php-security-linter")
            SCOPED_OUT_TOOLS+=("php-security-linter")
        fi
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
        if [ "${#MISSING_FILES[@]}" -gt 0 ]; then
            # The tool may well be here; the GROUND is not. Three different findings,
            # and filing this one under "absent" is what let a changed set of deleted
            # files read as expected coverage.
            echo -e "  ${YELLOW}[UNMEASURED]${NC} the changed files are not on disk — custom patterns had nothing to read"
            SKIPPED_TOOLS+=("custom_patterns")
            UNMEASURED_TOOLS+=("custom_patterns")
        else
            echo -e "  ${YELLOW}No SAST-eligible files — skipping custom patterns${NC}"
            SKIPPED_TOOLS+=("custom_patterns")
            SCOPED_OUT_TOOLS+=("custom_patterns")
        fi
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
        # Scoped out by design: no dependency file changed, so there is nothing for an
        # advisory scan to be about. This is the mode doing its job, not a gap in it,
        # and it belongs in tools_skipped[] beside the other by-design omissions. It sat
        # in tools_absent[] until 3.10.1, and every consumer that treats that list as a
        # coverage gap therefore put a false red on the majority of pull requests: most
        # of them touch PHP and not composer.lock.
        echo -e "${YELLOW}[SKIP]${NC} composer audit — composer.json/lock not in changed set"
        SKIPPED_TOOLS+=("composer_audit")
        SCOPED_OUT_TOOLS+=("composer_audit")
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
    # SKIPPED_TOOLS is the union of every non-producing layer, and the three named lists
    # below say why each one did not produce, so only the unnamed remainder — the ones
    # that failed — bears on the verdict.
    # FOUR disjoint lists, and each one states ONE fact. Until 3.10.1 tools_absent[]
    # documented itself as three facts at once — "tool not installed, nothing eligible to
    # scan, target path absent" — and a reader could not tell them apart, so every reading
    # of it was wrong in one direction or the other. A consumer that treats the list as a
    # coverage gap red-flags a correctly scoped run; one that does not lets a genuinely
    # missing gitleaks through.
    #
    #   tools_absent[]     the BINARY IS NOT INSTALLED. A fact about the machine, and the
    #                      only one of the four that is a coverage gap.
    #   tools_failed[]     the layer was there and returned nothing usable (crashed,
    #                      unparseable report, stale report). A zero from it is not
    #                      evidence, so it downgrades a would-be pass to "skipped".
    #   tools_unmeasured[] the layer was never asked, because the path it would have read
    #                      does not exist. A configuration fact about the project.
    #   tools_skipped[]    omitted BY DESIGN — the whole-project-only advisory layers this
    #                      mode never runs, plus the layers the changed set gave nothing to
    #                      do. Not a gap; the scoping working.
    #
    # Every non-produced result lands in exactly one of the four.
    SKIPPED_TOOLS_JSON=$(to_json_array "${SKIPPED_TOOLS[@]+"${SKIPPED_TOOLS[@]}"}")
    ABSENT_TOOLS_JSON=$(to_json_array "${ABSENT_TOOLS[@]+"${ABSENT_TOOLS[@]}"}")
    UNMEASURED_TOOLS_JSON=$(to_json_array "${UNMEASURED_TOOLS[@]+"${UNMEASURED_TOOLS[@]}"}")
    SCOPED_OUT_TOOLS_JSON=$(to_json_array "${SCOPED_OUT_TOOLS[@]+"${SCOPED_OUT_TOOLS[@]}"}")
    # The failed list stays DERIVED rather than listed by hand, so it cannot drift from the
    # recorded skips and the default stays fail-CLOSED: a name counts as a failure unless a
    # branch explicitly declared why it did not run.
    FAILED_TOOLS_JSON=$(jq -n --argjson skipped "$SKIPPED_TOOLS_JSON" \
        --argjson absent "$ABSENT_TOOLS_JSON" \
        --argjson unmeasured "$UNMEASURED_TOOLS_JSON" \
        --argjson scoped "$SCOPED_OUT_TOOLS_JSON" \
        '$skipped - $absent - $unmeasured - $scoped')
    FAILED_COUNT=$(echo "$FAILED_TOOLS_JSON" | jq 'length')
    # The by-design list a reader sees: the advisory layers this mode never runs, plus
    # whatever the changed set scoped out on this particular run.
    TOOLS_SKIPPED_JSON=$(jq -n --argjson scoped "$SCOPED_OUT_TOOLS_JSON" \
        '(["drush_pm_security","psalm","security_review","trivy","gitleaks","roave"] + $scoped) | unique')

    if [ "$RAN_ANALYZERS" -eq 0 ]; then
        OVERALL_STATUS="skipped"
    else
        OVERALL_STATUS=$(resolve_security_status \
            "$CRITICAL_COUNT" "$HIGH_COUNT" "$MEDIUM_COUNT" "$FAILED_COUNT")
    fi

    # A layer that was never asked CAPS a would-be pass, exactly as it does on the
    # standard path.
    if [ "${#UNMEASURED_TOOLS[@]}" -gt 0 ] \
       && { [ "$OVERALL_STATUS" = "pass" ] || [ "$OVERALL_STATUS" = "skipped" ]; }; then
        OVERALL_STATUS="${CQT_STATUS_UNMEASURED}"
    fi

    # A PARTIALLY MEASURABLE SET: some of the named files were read and some are not on
    # disk. The verdict for that shape, and why it is neither 0 nor 4 nor a failure, is
    # recorded once in lint-check.sh's --changed branch. Last, so a real finding is never
    # softened into a coverage note.
    if [ "${#MISSING_FILES[@]}" -gt 0 ] && [ "$OVERALL_STATUS" = "pass" ]; then
        OVERALL_STATUS="partial"
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
        --argjson tools_unmeasured "$UNMEASURED_TOOLS_JSON" \
        --argjson tools_skipped "$TOOLS_SKIPPED_JSON" \
        --argjson paths_missing "$CHANGED_MISSING_JSON" \
        --arg advisory_note "$ADVISORY_SKIP_NOTE" \
        '{
            meta: {
                timestamp: $timestamp,
                scan_type: "security_audit_changed",
                mode: "changed",
                analyzers_ran: $analyzers_ran,
                tools_run: ["semgrep","php-security-linter","custom_patterns","composer_audit"],
                tools_absent: $tools_absent,
                tools_failed: $tools_failed,
                tools_unmeasured: $tools_unmeasured,
                paths_missing: $paths_missing,
                tools_skipped: $tools_skipped
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

    if [ "$OVERALL_STATUS" = "${CQT_STATUS_UNMEASURED}" ]; then
        echo -e "${YELLOW}[UNMEASURED]${NC} $(echo "$UNMEASURED_TOOLS_JSON" | jq -r 'join(", ")') had nothing to read — security was NOT verified for the changed set"
        echo -e "Report: ${REPORT_FILE}"
        exit "$CQT_EXIT_UNMEASURED"
    elif [ "$OVERALL_STATUS" = "partial" ]; then
        echo -e "${YELLOW}[PARTIAL]${NC} No findings in what was read, but ${#MISSING_FILES[@]} changed file(s) were not on disk — coverage is incomplete"
        echo -e "Report: ${REPORT_FILE}"
        exit "$CQT_EXIT_WARNING"
    elif [ "$OVERALL_STATUS" = "skipped" ]; then
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

# Layers whose TOOL was present but whose GROUND was not. See the note in the --changed
# branch: absent, failed and unmeasured are three different findings, and only the first
# is allowed not to move the verdict.
UNMEASURED_TOOLS=()

# Layers deliberately not measured on this path, recorded so a consumer can compute
# `declared - reported`. The whole-project path has no diff to scope anything out, so
# until 3.10.4 it emitted no by-design list at all — and `roave`, a PREVENTION layer
# whose absence is a finding rather than a coverage gap, was declared in meta.tools[]
# and pushed nowhere. This is where it goes. It is NOT tools_absent[]: a fail-closed
# consumer reading absence as an install gap would block a review on every project
# without the package.
SKIPPED_BY_DESIGN=()

# The custom-code paths that are actually there, and the ones that are not. Resolved
# once, here, and read by every layer below that takes a path — so a themes directory
# this project does not have cannot take the modules scan down with it, and an absent
# modules directory cannot silently remove the pattern layer.
SEC_SCAN_PATHS=()
SEC_MISSING_PATHS=()
for sec_candidate in "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}"; do
    [ -n "$sec_candidate" ] || continue
    if [ "$(cqt_scan_path_state "$sec_candidate")" = "ok" ]; then
        SEC_SCAN_PATHS+=("$sec_candidate")
    else
        SEC_MISSING_PATHS+=("$sec_candidate")
    fi
done
SEC_MODULES_STATE="$(cqt_scan_path_state "${DRUPAL_MODULES_PATH}")"

# Trees that are somebody else's code, vendored into this one. The Next.js gates already
# exclude these; the Drupal pattern greps did not, so a node_modules tree under a custom
# theme produced findings attributed to this project.
SEC_GREP_EXCLUDES=(--exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=bower_components)


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

if ddev exec test -f vendor/bin/php-security-linter &> /dev/null && [ "${#SEC_SCAN_PATHS[@]}" -eq 0 ]; then
    # The tool is installed and there is nothing for it to read. Not "absent" — that is
    # a fact about the machine and is allowed not to move the verdict — and not a
    # failure either, because it never ran.
    cqt_unmeasured "php-security-linter was not run: no custom code path exists" \
        "${SEC_MISSING_PATHS[@]+"${SEC_MISSING_PATHS[@]}"}"
    SKIPPED_TOOLS+=("php-security-linter")
    UNMEASURED_TOOLS+=("php-security-linter")
    PHPCS_ISSUES="[]"
elif ddev exec test -f vendor/bin/php-security-linter &> /dev/null; then
    set +e
    ddev exec vendor/bin/php-security-linter scan \
        "${SEC_SCAN_PATHS[@]}" \
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
        # The heredoc STAYS QUOTED — it is XML, and an unquoted one would have the shell
        # interpret it — so the resolved paths cannot be interpolated into it. They go in
        # as placeholders and one substitution pass afterwards.
        #
        # TWO ARTIFACTS, ONE FILENAME. templates/drupal/psalm.xml is a different file:
        # cqt-install.sh places it at install time, only when psalm is in the config's
        # tools, and it carries an <autoloader> and the same ignore list. This heredoc is
        # what a project that never ran /code-quality-tools:setup gets, written by the
        # gate at scan time. Neither is dead — they cover disjoint cases — and both have
        # to carry the exclusions, because a project only ever has one of them.
        #
        # This file outlives the run that wrote it: it is created only when the project
        # has none, and found on every later run. A layout literal baked in here
        # therefore keeps psalm pointed at directories that do not exist long after the
        # gate itself has been fixed, and the taint layer analyses nothing for as long
        # as the file survives.
        #
        # A path containing a double quote would break the XML attribute, so it is
        # refused rather than written. The same guard rector-fix.sh applies for a
        # single quote in generated PHP.
        if [ "${DRUPAL_MODULES_PATH}" != "${DRUPAL_MODULES_PATH//\"/}" ] \
           || [ "${DRUPAL_THEMES_PATH}" != "${DRUPAL_THEMES_PATH//\"/}" ]; then
            echo -e "  ${YELLOW}[SKIP]${NC} psalm.xml not generated: a custom path contains a double quote"
        else
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
        <directory name="@CQT_MODULES@" />
        <directory name="@CQT_THEMES@" />
        <ignoreFiles>
            <!--
              Somebody else's code, vendored into this tree. `vendor` alone left psalm
              analysing every bundled dependency under a custom module or theme and
              attributing what it found to this project — and this file outlives the run
              that wrote it, so it kept doing so long after the gate was fixed. The same
              list the placed templates/drupal/psalm.xml carries; see the note above the
              heredoc on why these are two different artifacts.
            -->
            <directory name="vendor" />
            <directory name="@CQT_MODULES@/*/vendor" />
            <directory name="@CQT_THEMES@/*/vendor" />
            <directory name="@CQT_MODULES@/*/node_modules" />
            <directory name="@CQT_THEMES@/*/node_modules" />
        </ignoreFiles>
    </projectFiles>
</psalm>
EOF
        # `|` as the sed delimiter, because the values are paths and contain `/`.
        # `g`: the placeholders now appear more than once each (projectFiles and
        # ignoreFiles), and a substitution without it would leave the ignore list naming
        # a literal @CQT_MODULES@ directory that exists nowhere.
        sed -i.cqtbak \
            -e "s|@CQT_MODULES@|${DRUPAL_MODULES_PATH}|g" \
            -e "s|@CQT_THEMES@|${DRUPAL_THEMES_PATH}|g" \
            psalm.xml
        rm -f psalm.xml.cqtbak
        fi
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

# SQL Injection patterns.
#
# Gated per PATH rather than all-or-nothing on the modules directory. The |raw check
# reads BOTH paths, so a project with themes and no custom modules had its Twig
# templates silently dropped from the scan along with everything else.
if [ "$SEC_MODULES_STATE" = "ok" ]; then
    # Unsafe db_query usage. The pattern matches interpolation inside a double-quoted
    # first argument, or concatenation onto it, so the safe placeholder-array form
    # (db_query('... :id', [':id' => $id])) no longer counts as a finding.
    DB_QUERY_UNSAFE=$(grep -rEHn 'db_query([^"]*"[^"]*\$|.*\.[[:space:]]*\$)' "${DRUPAL_MODULES_PATH}" --include="*.php" --include="*.module" --include="*.inc" "${SEC_GREP_EXCLUDES[@]}" 2>/dev/null || true)
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

    # unserialize() on user input
    UNSERIALIZE=$(grep -rHn "unserialize.*\$_" "${DRUPAL_MODULES_PATH}" --include="*.php" --include="*.module" "${SEC_GREP_EXCLUDES[@]}" 2>/dev/null || true)
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

# The Twig layer reads whichever of the two paths is there. Its own gate, because a
# theme-only project is a legitimate shape and its templates are custom code.
if [ "${#SEC_SCAN_PATHS[@]}" -gt 0 ]; then
    # Twig |raw filter. Kept as a basic-regex grep: under -E the '|' would be alternation.
    RAW_FILTER=$(grep -rHn "|raw" "${SEC_SCAN_PATHS[@]}" --include="*.twig" "${SEC_GREP_EXCLUDES[@]}" 2>/dev/null || true)
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
fi

if [ "$SEC_MODULES_STATE" != "ok" ]; then
    # The pattern layer scanned no PHP because the configured path does not exist — an
    # empty site, or DRUPAL_MODULES_PATH pointing somewhere wrong. It produced no
    # coverage and must say so instead of contributing a silent zero.
    #
    # This used to be recorded in tools_absent, which is documented as "expected, does
    # not move the verdict" — so a run that read none of the project's custom code
    # reported a pass. It is unmeasured: the check was there, the ground was not.
    cqt_unmeasured "the custom modules path is not there — no custom PHP was scanned" \
        "${DRUPAL_MODULES_PATH}"
    SKIPPED_TOOLS+=("custom_patterns")
    UNMEASURED_TOOLS+=("custom_patterns")
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

if [ -n "$SEMGREP_RUNNER" ] && [ "${#SEC_SCAN_PATHS[@]}" -eq 0 ]; then
    cqt_unmeasured "semgrep was not run: no custom code path exists" \
        "${SEC_MISSING_PATHS[@]+"${SEC_MISSING_PATHS[@]}"}"
    SKIPPED_TOOLS+=("semgrep")
    UNMEASURED_TOOLS+=("semgrep")
elif [ -n "$SEMGREP_RUNNER" ]; then
    set +e
    # Run Semgrep with auto config (includes security rules)
    if [ "$SEMGREP_RUNNER" = "container" ]; then
        ddev exec semgrep scan --config=auto --json \
            "${SEMGREP_EXCLUDES[@]}" \
            "${SEC_SCAN_PATHS[@]}" > "$SEMGREP_JSON" 2>/dev/null
    else
        semgrep scan --config=auto --json \
            "${SEMGREP_EXCLUDES[@]}" \
            "${SEC_SCAN_PATHS[@]}" > "$SEMGREP_JSON" 2>/dev/null
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
# --- cqt:secret-scan-block:start ---
# =====================
# Gitleaks Secret Detection — phases 1 and 3
# =====================
# WHAT GROUND THIS COVERS is a decision, and it used to be made silently. The old
# invocation was the legacy `gitleaks detect` spelling with version control switched
# off, which is what `gitleaks dir` is now: the working tree and nothing else, with
# no line of output saying so. A credential
# committed in one release and gitignored in the next was invisible to it, and
# "0 findings" read as proof of a clean repository rather than of a clean checkout.
#
# core/secret-scan.sh resolves the ground (tree by default, or a bounded commit
# range, or all of history on request), builds every gitleaks command line, and
# merges overlapping passes. This block runs the working-tree pass, decides whether
# what came back is a RESULT or a FAILURE, and asks the library for the extra pass
# when one was asked for. The default stays the working tree because full-history
# discovery is not affordable on a repository that ever committed vendor/ — 2,368
# commits and 224.84 MiB of history took longer than a ten-minute limit on the
# project this came from.
GITLEAKS_JSON="${REPORT_DIR}/security/gitleaks.json"
GITLEAKS_ISSUES="[]"

# What the MACHINE-READABLE report records about the ground this scan covered.
# security-report.json used to be byte-identical between a working-tree-only scan and
# a full-history one, and between a filtered scan and an unfiltered one: every word
# about scope went to the terminal and none of it to the artifact that full-audit.sh
# and every later reader actually consume. The [SCOPE] and [FILTER] lines printed
# below are built from the SAME strings these fields carry.
#
# What that does NOT amount to, stated rather than implied away: the console and the
# file are not guaranteed to say the same thing. [SCOPE] is printed BEFORE the scan
# runs, because a reader watching a long pass needs to know what it is watching, and
# a pass that then fails rewrites these fields. On a failed run the terminal
# therefore holds a scope line describing the intended ground while the file records
# "nothing was scanned: ...". The console is not left misleading - the [SKIP] line
# follows it, and that is the whole reason the ordering is acceptable - but the two
# artifacts differ, and the FILE is the one that carries the corrected answer.
GITLEAKS_SCOPE_TEXT="gitleaks is not installed, so no secret scan was performed"
GITLEAKS_SCOPE_MODE="none"
GITLEAKS_SCOPE_RANGE=""
GITLEAKS_SCOPE_STATUS="absent"
GITLEAKS_SCOPE_HISTORY="false"
GITLEAKS_ALLOWLIST_NAME="none"
GITLEAKS_ALLOWLIST_CONFIG=""

if command -v gitleaks &> /dev/null; then
    # core/secret-scan.sh is sourced at the top of this script, so the plan resolves
    # on every real run. The guard is here because the audit suite also extracts
    # this block and executes it on its own against a stubbed gitleaks to check the
    # failure discrimination below; with no plan resolved the ground is the shipped
    # default, the working tree, which is what the literal invocation further down
    # scans.
    GITLEAKS_LIB=0
    GITLEAKS_MODE="tree"
    GITLEAKS_RANGE=""
    GITLEAKS_RANGE_KIND=""
    GITLEAKS_PLAN="ok"
    GITLEAKS_PLAN_REASON=""
    if declare -F cqt_gitleaks_plan >/dev/null 2>&1 && declare -F cqt_gitleaks_argv >/dev/null 2>&1; then
        GITLEAKS_LIB=1
        cqt_gitleaks_plan "."
        GITLEAKS_MODE="$CQT_GL_MODE"
        GITLEAKS_RANGE="$CQT_GL_RANGE"
        GITLEAKS_RANGE_KIND="$CQT_GL_RANGE_KIND"
        GITLEAKS_PLAN="$CQT_GL_STATUS"
        GITLEAKS_PLAN_REASON="$CQT_GL_REASON"
    fi

    GITLEAKS_SCOPE_MODE="$GITLEAKS_MODE"
    GITLEAKS_SCOPE_RANGE="$GITLEAKS_RANGE"
    GITLEAKS_SCOPE_STATUS="$GITLEAKS_PLAN"

    if [ "$GITLEAKS_PLAN" != "ok" ]; then
        # The requested scan cannot be run. Running a NARROWER one and reporting the
        # result as if the requested one had happened is the whole defect: an
        # unresolvable diff base must not silently become "scan everything", a base
        # equal to HEAD must not silently become "an empty range we scanned", and a
        # quoted value that gitleaks word-splits into a no-op must not silently
        # become "scanned, found nothing".
        echo -e "  ${YELLOW}[SKIP]${NC} gitleaks: ${GITLEAKS_PLAN_REASON} (${GITLEAKS_PLAN})"
        SKIPPED_TOOLS+=("gitleaks")
        GITLEAKS_SCOPE_TEXT="nothing was scanned: ${GITLEAKS_PLAN_REASON}"
    else
        # Every pass is wrapped in timeout(1), never in gitleaks' own --timeout.
        # Measured on 8.30.1: gitleaks given its own budget writes a well-formed
        # EMPTY report, logs "partial scan completed" and exits 1, so a reader that
        # sees "report present, parses, length 0" calls a truncated scan a clean
        # tree. timeout(1) exits 124 and writes nothing, which cannot be mistaken
        # for a result. Without timeout(1) there is no budget at all, and the scope
        # line below says that rather than naming a limit nothing enforces.
        GITLEAKS_RUNNER=()
        GITLEAKS_BUDGET_NOTE="no budget: timeout(1) is not installed, so CQT_SECRET_SCAN_TIMEOUT is not enforced"
        if command -v timeout >/dev/null 2>&1; then
            GITLEAKS_RUNNER=(timeout "${CQT_SECRET_SCAN_TIMEOUT:-300}")
            GITLEAKS_BUDGET_NOTE="budget ${CQT_SECRET_SCAN_TIMEOUT:-300}s per pass"
        fi

        # "Gitleaks: 0 findings" means two different things with and without
        # history, so the run says which one it did before it says what it found.
        # The budget note is on EVERY mode, not only the two history branches: a
        # working-tree or diff pass runs under the same timeout(1) or under no
        # budget at all, and a scope line that mentions a limit in one mode and
        # stays silent about it in another is telling the reader the limit does not
        # apply there.
        case "$GITLEAKS_MODE" in
            history)
                if [ -n "$GITLEAKS_RANGE" ]; then
                    GITLEAKS_SCOPE_TEXT="working tree plus the git history selected by '${GITLEAKS_RANGE}'; commits outside it were not scanned (${GITLEAKS_BUDGET_NOTE})"
                else
                    GITLEAKS_SCOPE_TEXT="working tree plus every commit reachable from every ref (${GITLEAKS_BUDGET_NOTE})"
                fi
                GITLEAKS_SCOPE_HISTORY="true"
                ;;
            diff)
                # CQT_SECRET_SCAN_LOG_OPTS DISCARDS the resolved base: gitleaks takes
                # one --log-opts string and the operator's is the one git sees. So a
                # diff run carrying a selector did not scan "the commit range X with
                # history before the base left out" — with --all it read ALL of
                # history. Over-covering rather than under-covering, but the sentence
                # was untrue, and a scope line that misdescribes the ground is the
                # defect this whole block exists to remove.
                if [ "${GITLEAKS_RANGE_KIND:-}" = "selector" ]; then
                    GITLEAKS_SCOPE_TEXT="working tree plus the git history selected by '${GITLEAKS_RANGE}', which REPLACED the diff base; commits outside that selection were not scanned (${GITLEAKS_BUDGET_NOTE})"
                else
                    GITLEAKS_SCOPE_TEXT="working tree plus the commit range ${GITLEAKS_RANGE}; git history before the base was not scanned (${GITLEAKS_BUDGET_NOTE})"
                fi
                GITLEAKS_SCOPE_HISTORY="true"
                ;;
            *)
                GITLEAKS_SCOPE_TEXT="working tree only; git history was not scanned. Use CQT_SECRET_SCAN=diff with CQT_SECRET_SCAN_BASE=<ref> for a bounded range, or CQT_SECRET_SCAN=history for every commit (${GITLEAKS_BUDGET_NOTE})"
                GITLEAKS_SCOPE_HISTORY="false"
                ;;
        esac
        echo -e "  ${BLUE}[SCOPE]${NC} ${GITLEAKS_SCOPE_TEXT}"

        # An allowlist SUPPRESSES findings, so a run with one in force can print
        # "No secrets detected" about a repository that holds secrets in every
        # suppressed path. Undisclosed suppression is the exact shape this gate
        # exists to refuse, so the run names the config that is filtering it.
        #
        # The disclosure USED TO be tied to CQT_SECRET_SCAN_ALLOWLIST=vendored, on
        # the reasoning that our opt-in is the only way a config reaches the command
        # line. It is the only way one reaches the COMMAND LINE and not the only way
        # one reaches the SCAN: measured on gitleaks 8.30.1, a .gitleaks.toml in the
        # scanned directory and a GITLEAKS_CONFIG environment variable each take
        # effect on their own, turning a one-finding repository into a zero-finding
        # report while our argv named no config at all. Reporting allowlist:"none"
        # there was a positive false claim about a suppressed live credential, so
        # what is asked for now is what is IN FORCE. See cqt_gitleaks_effective_config.
        if [ "$GITLEAKS_LIB" -eq 1 ]; then
            GITLEAKS_ALLOWLIST_PAIR="$(cqt_gitleaks_effective_config ".")"
            GITLEAKS_ALLOWLIST_NAME="${GITLEAKS_ALLOWLIST_PAIR%%|*}"
            GITLEAKS_ALLOWLIST_CONFIG="${GITLEAKS_ALLOWLIST_PAIR#*|}"
            if [ "$GITLEAKS_ALLOWLIST_NAME" = "none" ]; then
                GITLEAKS_ALLOWLIST_CONFIG=""
            else
                echo -e "  ${YELLOW}[FILTER]${NC} an allowlist config is in force (${GITLEAKS_ALLOWLIST_CONFIG}); findings in the paths it matches were SUPPRESSED and are not counted below"
            fi
        fi

        set +e
        # Drop any report from a previous run: a failed run writes no report, and a
        # stale one would otherwise be parsed as if it were this run's result. This
        # sits INSIDE the set +e bracket because `rm` fails on an unwritable report
        # directory, which under set -e would abort the entire security gate. A stale
        # report that cannot be removed is itself the false-clean case, so it is
        # treated as a failed run below rather than trusted.
        rm -f "$GITLEAKS_JSON" 2>/dev/null
        GITLEAKS_STALE=0
        if [ -e "$GITLEAKS_JSON" ]; then
            GITLEAKS_STALE=1
        fi
        # A per-mode report from an earlier run is dropped for the same reason. The
        # extra pass merges its own gitleaks-<mode>.json into gitleaks.json and then
        # deletes it, but a history run followed by a tree run would otherwise leave
        # last week's gitleaks-history.json sitting next to a current tree-only
        # report, where nothing marks it as belonging to a different scan.
        if declare -F cqt_gitleaks_clear_extra >/dev/null 2>&1; then
            cqt_gitleaks_clear_extra "$GITLEAKS_JSON"
        fi

        # The command line comes from cqt_gitleaks_argv, which is the single place
        # gitleaks' flags are decided — the opt-in vendored allowlist is added
        # there, so a block that assembled its own command line would ignore it.
        # The literal invocation in the else branch is the same working-tree pass
        # written out, and it is what runs when this block is executed on its own
        # with the library not sourced. Each form is what one part of the audit
        # suite executes, so neither is dead code. The suite now asserts the two are
        # ARGUMENT-FOR-ARGUMENT EQUAL, so a change to the builder that is not
        # mirrored here fails the spec instead of drifting quietly.
        GITLEAKS_ARGV=()
        if [ "$GITLEAKS_LIB" -eq 1 ]; then
            while IFS= read -r GITLEAKS_ARG; do
                GITLEAKS_ARGV+=("$GITLEAKS_ARG")
            done < <(cqt_gitleaks_argv tree "." "$GITLEAKS_JSON")
        fi
        if [ "${#GITLEAKS_ARGV[@]}" -gt 0 ]; then
            "${GITLEAKS_RUNNER[@]}" "${GITLEAKS_ARGV[@]}" 2>/dev/null
            GITLEAKS_EXIT=$?
        else
            "${GITLEAKS_RUNNER[@]}" \
                gitleaks dir . --redact --report-format json --report-path "$GITLEAKS_JSON" --no-banner 2>/dev/null
            GITLEAKS_EXIT=$?
        fi
        set -e

        # Exit status alone cannot tell "found leaks" from "failed to run". Verified
        # against gitleaks 8.30.1: exit 0 means it ran and found nothing, but exit 1
        # means EITHER it found leaks OR it errored — a bad config, an unwritable
        # --report-path, a missing --source and a bad --report-format all exit 1,
        # because gitleaks fatals through os.Exit(1). Only a PARSEABLE report
        # distinguishes the two. Exit >= 2 is a shell-level failure (126/127,
        # 128+N), which produces no report either.
        GITLEAKS_FAILED=0
        GITLEAKS_FAIL_REASON=""
        # The EXTRA pass is tracked separately from the working-tree pass, because
        # they fail independently and only one of them can invalidate a finding. See
        # the block below the working-tree verdict for why they were conflated and
        # what that cost.
        GITLEAKS_HISTORY_FAILED=0
        GITLEAKS_HISTORY_FAIL_REASON=""
        SECRET_COUNT=0

        if [ "$GITLEAKS_STALE" -eq 1 ]; then
            # A report from an earlier run could not be removed, so this run's report
            # cannot be told apart from it. Unprovable provenance is not a clean tree.
            GITLEAKS_FAILED=1
            GITLEAKS_FAIL_REASON="a report from an earlier run could not be removed"
        elif [ "$GITLEAKS_EXIT" -eq 124 ] || [ "$GITLEAKS_EXIT" -eq 137 ]; then
            GITLEAKS_FAILED=1
            GITLEAKS_FAIL_REASON="the scan ran past its budget (CQT_SECRET_SCAN_TIMEOUT=${CQT_SECRET_SCAN_TIMEOUT:-300}s) and was killed, so nothing was proven"
        elif [ "$GITLEAKS_EXIT" -ge 2 ]; then
            GITLEAKS_FAILED=1
            GITLEAKS_FAIL_REASON="gitleaks exited ${GITLEAKS_EXIT}"
        elif [ -f "$GITLEAKS_JSON" ] && [ -s "$GITLEAKS_JSON" ]; then
            set +e
            SECRET_COUNT=$(jq 'length' "$GITLEAKS_JSON" 2>/dev/null)
            JQ_EXIT=$?
            set -e
            # A report that is present but unparseable is not evidence of a clean
            # tree. Swallowing jq's failure into 0 would report clean while gitleaks
            # is saying the opposite.
            if [ "$JQ_EXIT" -ne 0 ] || ! [[ "$SECRET_COUNT" =~ ^[0-9]+$ ]]; then
                GITLEAKS_FAILED=1
                SECRET_COUNT=0
                GITLEAKS_FAIL_REASON="the report is present but does not parse"
            elif [ "$GITLEAKS_EXIT" -ne 0 ] && [ "$SECRET_COUNT" -eq 0 ]; then
                # gitleaks exits 0 when it ran and found nothing, so a non-zero exit
                # alongside an empty report is a failed or truncated scan. This is
                # the shape a partial scan takes, and reading it as a clean tree is
                # the most expensive way to be wrong here.
                GITLEAKS_FAILED=1
                SECRET_COUNT=0
                GITLEAKS_FAIL_REASON="gitleaks exited ${GITLEAKS_EXIT} and wrote an empty report — a failed or partial scan, not a clean tree"
            fi
        elif [ "$GITLEAKS_EXIT" -ne 0 ]; then
            # Exit 1 with no report at all: gitleaks errored rather than found anything.
            GITLEAKS_FAILED=1
            GITLEAKS_FAIL_REASON="gitleaks exited ${GITLEAKS_EXIT} and wrote no report"
        fi

        # The pass beyond the working tree, when one was asked for. It runs before
        # the verdict below so SECRET_COUNT is the DEDUPLICATED total across both
        # passes: the same secret is reported by the tree pass and again by every
        # commit that introduced it, and a run that added those up would triple-count
        # what a one-pass run counted once.
        if [ "$GITLEAKS_FAILED" -eq 0 ] && [ "$GITLEAKS_LIB" -eq 1 ] && [ "$GITLEAKS_MODE" != "tree" ]; then
            set +e
            cqt_gitleaks_extra_scan "." "$GITLEAKS_JSON"
            set -e
            if [ "$CQT_GL_EXTRA_STATUS" != "ok" ]; then
                # A history pass that did not finish says nothing about history, and
                # a working-tree result presented as a history result is the false
                # clean in its most convincing form. So the HISTORY claim is withdrawn
                # below — but the working-tree findings are NOT.
                #
                # This used to set GITLEAKS_FAILED=1 and SECRET_COUNT=0, which erased
                # findings the working-tree pass had already made and written to
                # $GITLEAKS_JSON. One live secret in the tree, three runs: `tree`
                # reported it, a `diff` over a deletion-only range reported Critical:0,
                # and a tree pass killed on its budget reported Critical:0 — with
                # security/gitleaks.json holding the finding and security-report.json
                # holding zero Gitleaks issues, in the same directory, from the same
                # run. A 300s budget kill on a large repository is ordinary, so this
                # was not a rare path. A finding that was actually made is not
                # unmade by an ADDITIONAL pass failing.
                GITLEAKS_HISTORY_FAILED=1
                GITLEAKS_HISTORY_FAIL_REASON="$CQT_GL_EXTRA_REASON"
            else
                SECRET_COUNT="$CQT_GL_MERGED_COUNT"
            fi
        fi

        if [ "$GITLEAKS_FAILED" -eq 1 ]; then
            echo -e "  ${YELLOW}[SKIP]${NC} gitleaks produced no usable report: ${GITLEAKS_FAIL_REASON} (exit ${GITLEAKS_EXIT})"
            SKIPPED_TOOLS+=("gitleaks")
            # The ground the run INTENDED to cover is not the ground it covered. The
            # artifact records the failure, not the intention.
            GITLEAKS_SCOPE_STATUS="failed"
            GITLEAKS_SCOPE_HISTORY="false"
            GITLEAKS_SCOPE_TEXT="nothing was scanned: ${GITLEAKS_FAIL_REASON}"
        else
            if [ "$GITLEAKS_HISTORY_FAILED" -eq 1 ]; then
                # Strictly more information than the old zero: the tree findings
                # stand and are reported below, AND the run says history is not
                # covered. The tool is still recorded as skipped, so the aggregate
                # verdict cannot come back "pass" off a run that only half happened.
                echo -e "  ${YELLOW}[SKIP]${NC} gitleaks ${GITLEAKS_MODE} pass: ${GITLEAKS_HISTORY_FAIL_REASON}. The working-tree findings below stand; git history was NOT covered."
                SKIPPED_TOOLS+=("gitleaks")
                GITLEAKS_SCOPE_STATUS="history_failed"
                GITLEAKS_SCOPE_HISTORY="false"
                GITLEAKS_SCOPE_TEXT="working tree only; the ${GITLEAKS_MODE} pass did not complete, so no history was covered: ${GITLEAKS_HISTORY_FAIL_REASON}"
            fi

            if [ "$SECRET_COUNT" -gt 0 ]; then
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
            elif [ "$GITLEAKS_HISTORY_FAILED" -eq 0 ]; then
                echo -e "  ${GREEN}No secrets detected${NC}"
            fi
        fi
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} gitleaks not installed (tool absent)"
    SKIPPED_TOOLS+=("gitleaks")
    ABSENT_TOOLS+=("gitleaks")
fi

# =====================
# Secret history — phase 2, confirmation
# =====================
# Deliberately OUTSIDE the gitleaks block above. That block is the scan; this is a
# different job with a different failure mode, and neither must be able to take the
# other down.
#
# What it adds to each secret finding: first_seen_commit, first_seen_date, author
# and commit_count. Without them a finding is a location, and a location does not
# decide the remediation — never committed means edit the file, in history for two
# years means rotate at the provider and editing the file achieves nothing.
#
# It never moves the VERDICT (a secret is critical either way) and never records a
# skipped tool, so a project with no git history cannot turn a completed secret scan
# into an incomplete one. Every failure degrades to an explicit "could not check".
#
# The backfill after it is what stops a history-only finding being reported as
# "history could not be checked". Phase 2 recovers the secret VALUE from the
# working-tree file and walks history for it, so a file that is no longer in the
# tree gives it nothing to work with — while the history pass that produced the
# finding already knows the commit, the author and the date. See
# cqt_gitleaks_history_backfill for why phase 2 still wins wherever it answered.
if [ "$GITLEAKS_ISSUES" != "[]" ]; then
    echo -e "  ${BLUE}[HISTORY]${NC} Confirming which findings already reached git history..."
    set +e
    GITLEAKS_HISTORY=$(cqt_secret_history_json "$GITLEAKS_JSON" ".")
    GITLEAKS_HISTORY=$(cqt_gitleaks_history_backfill "$GITLEAKS_HISTORY" "$GITLEAKS_JSON")
    GITLEAKS_ISSUES=$(cqt_secret_history_attach "$GITLEAKS_ISSUES" "$GITLEAKS_HISTORY")
    set -e
    while IFS= read -r HISTORY_LINE; do
        [ -n "$HISTORY_LINE" ] && printf '    %s\n' "$HISTORY_LINE"
    done < <(cqt_secret_history_report "$GITLEAKS_ISSUES")
fi

# =====================
# Deploy artifact — how far a finding reaches (item 17)
# =====================
# `acli push:artifact` commits the built tree to a SECOND git repository with its
# own remote, its own clones and its own access list. A credential in exported
# config therefore lives in two histories, and every deploy writes it into the
# second one again until the value leaves config. "Found in 44 commits" against the
# source repository alone understates the blast radius and prescribes a remediation
# that leaves the credential live.
#
# Detection is about THIS repository — an Acquia remote, or a project-local acli
# config — never about the machine. See cqt_deploy_artifact_detect.
if [ "$GITLEAKS_ISSUES" != "[]" ]; then
    set +e
    GITLEAKS_DEPLOY=$(cqt_deploy_artifact_detect ".")
    if [ -n "$GITLEAKS_DEPLOY" ]; then
        GITLEAKS_DEPLOY_REMOTES=$(cqt_deploy_artifact_remotes ".")
        GITLEAKS_ISSUES=$(cqt_deploy_artifact_annotate "$GITLEAKS_ISSUES" "$GITLEAKS_DEPLOY" "$GITLEAKS_DEPLOY_REMOTES")
        # Conditional, because the detection knows this project deploys through an
        # artifact and does NOT know which files the build ships. A finding in
        # test/fixtures/mock.js reaches no `acli push:artifact` tree, and asserting a
        # blast radius the code cannot establish is the same over-reach
        # cqt_deploy_artifact_detect refuses when it declines to read ~/.acquia-cli.yml.
        # The remotes are already redacted of any embedded credential; see
        # cqt_deploy_artifact_remotes.
        echo -e "  ${YELLOW}[DEPLOY]${NC} This project deploys through an Acquia build artifact, so findings in files that reach the build artifact also land in the deploy repository: ${GITLEAKS_DEPLOY_REMOTES}"
    fi
    set -e
fi

# =====================
# What the artifact records about the ground covered
# =====================
# Terminal output is read once, by whoever was watching. security-report.json is what
# full-audit.sh consumes and what anyone reads afterwards, and it carried no trace of
# whether history was scanned or whether an allowlist had suppressed findings — so two
# runs covering completely different ground produced byte-identical artifacts. Every
# field below is the value the [SCOPE] and [FILTER] lines were built from, so the two
# cannot disagree.
GITLEAKS_SCOPE_JSON=$(jq -n \
    --arg mode "$GITLEAKS_SCOPE_MODE" \
    --arg range "$GITLEAKS_SCOPE_RANGE" \
    --arg status "$GITLEAKS_SCOPE_STATUS" \
    --arg scope "$GITLEAKS_SCOPE_TEXT" \
    --arg allowlist "$GITLEAKS_ALLOWLIST_NAME" \
    --arg allowlist_config "$GITLEAKS_ALLOWLIST_CONFIG" \
    --argjson history_scanned "$GITLEAKS_SCOPE_HISTORY" \
    '{mode: $mode, range: $range, status: $status, history_scanned: $history_scanned,
      allowlist: $allowlist, allowlist_config: $allowlist_config, scope: $scope}' \
    2>/dev/null || printf '%s' '{"mode":"unknown","status":"unknown","history_scanned":false,"allowlist":"unknown","scope":"the scope record could not be built"}')
# --- cqt:secret-scan-block:end ---

echo ""
echo -e "${BLUE}[10/10]${NC} Verifying Roave Security Advisories (prevention layer)..."
# =====================
# Roave Security Advisories (Prevention Layer)
# =====================
ROAVE_ISSUES="[]"

# `roave` was DECLARED in meta.tools[] below and pushed into no coverage array at all,
# so a consumer computing coverage as `declared - reported` saw a layer permanently
# missing. It is a PREVENTION layer, not a scanner: when it is absent that is a finding,
# not a coverage gap, so it belongs in the by-design list rather than tools_absent[] —
# filing it under absence would block a review on every project that has not installed
# it. The probe's status is read explicitly, because `composer show` failing because the
# package is not required and `ddev` failing because it cannot run are different facts
# and the `&> /dev/null` test answered both with "not installed".
set +e
ROAVE_PROBE_OUT=$(ddev composer show roave/security-advisories 2>&1)
ROAVE_PROBE_EXIT=$?
set -e

if [ "$ROAVE_PROBE_EXIT" -eq 0 ]; then
    echo -e "  ${GREEN}Roave Security Advisories is installed${NC}"
    echo -e "  ${BLUE}[INFO]${NC} Prevents installation of packages with known vulnerabilities"
    # Roave is installed - no issues to report (it prevents issues at install time)
elif [ "$ROAVE_PROBE_EXIT" -ge 126 ]; then
    # 126/127 and 128+N are shell-level: the command could not be run or was killed.
    # Nothing was learned about the project, and a layer that was never asked must not
    # read as one that answered.
    echo -e "  ${YELLOW}[UNMEASURED]${NC} could not ask composer about roave/security-advisories (exit ${ROAVE_PROBE_EXIT}): $(printf '%s' "$ROAVE_PROBE_OUT" | head -1)"
    SKIPPED_TOOLS+=("roave")
    UNMEASURED_TOOLS+=("roave")
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
    SKIPPED_TOOLS+=("roave")
    SKIPPED_BY_DESIGN+=("roave")
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
# from. An uninstalled binary stays in tools_absent[] and is reported, but it does not
# move the verdict; see resolve_security_status().
# The three lists are DISJOINT and each states ONE fact; see the --changed path for the
# full four-way split and why conflating them was a defect.
#   tools_absent[]     the BINARY IS NOT INSTALLED — a fact about the machine, and the
#                      only one of the three that is a coverage gap. Every push into it
#                      on this path is a `command -v` / `test -f vendor/bin/...` miss.
#   tools_failed[]     present and returned nothing usable — a zero from it is not
#                      evidence, so it downgrades a would-be pass to "skipped".
#   tools_unmeasured[] never asked, because the path it would have read is not there.
#   tools_skipped[]    deliberately not measured — the prevention layer whose absence
#                      is already a finding. Nothing here is scoped out by a diff, but
#                      "no diff-scoping" is not the same as "nothing by design", and
#                      reading it that way left `roave` declared and unreportable.
SKIPPED_TOOLS_JSON=$(to_json_array "${SKIPPED_TOOLS[@]+"${SKIPPED_TOOLS[@]}"}")
ABSENT_TOOLS_JSON=$(to_json_array "${ABSENT_TOOLS[@]+"${ABSENT_TOOLS[@]}"}")
UNMEASURED_TOOLS_JSON=$(to_json_array "${UNMEASURED_TOOLS[@]+"${UNMEASURED_TOOLS[@]}"}")
BY_DESIGN_TOOLS_JSON=$(to_json_array "${SKIPPED_BY_DESIGN[@]+"${SKIPPED_BY_DESIGN[@]}"}")
# Four disjoint sets now, and the failed one is still derived rather than listed by
# hand: everything that recorded a skip, minus the three kinds with a name for why.
FAILED_TOOLS_JSON=$(jq -n --argjson skipped "$SKIPPED_TOOLS_JSON" \
    --argjson absent "$ABSENT_TOOLS_JSON" \
    --argjson unmeasured "$UNMEASURED_TOOLS_JSON" \
    --argjson by_design "$BY_DESIGN_TOOLS_JSON" \
    '$skipped - $absent - $unmeasured - $by_design')
FAILED_COUNT=$(echo "$FAILED_TOOLS_JSON" | jq 'length')

OVERALL_STATUS=$(resolve_security_status \
    "$CRITICAL_COUNT" "$HIGH_COUNT" "$MEDIUM_COUNT" "$FAILED_COUNT")

# A layer that was never asked CAPS a would-be pass, and does not touch a real finding.
# Ten layers run here; two absent paths must not erase the eight that produced results,
# and must not let the two that did not produce a clean bill of health either.
if [ "${#UNMEASURED_TOOLS[@]}" -gt 0 ] \
   && { [ "$OVERALL_STATUS" = "pass" ] || [ "$OVERALL_STATUS" = "skipped" ]; }; then
    OVERALL_STATUS="${CQT_STATUS_UNMEASURED}"
fi

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
    --argjson tools_unmeasured "$UNMEASURED_TOOLS_JSON" \
    --argjson tools_skipped "$BY_DESIGN_TOOLS_JSON" \
    --argjson secret_scan "$GITLEAKS_SCOPE_JSON" \
    '{
        meta: {
            timestamp: $timestamp,
            scan_type: "security_audit",
            tools: ["drush_pm_security", "composer_audit", "php-security-linter", "psalm", "custom_patterns", "security_review", "semgrep", "trivy", "gitleaks", "roave"],
            tools_absent: $tools_absent,
            tools_failed: $tools_failed,
            tools_unmeasured: $tools_unmeasured,
            tools_skipped: $tools_skipped,
            secret_scan: $secret_scan
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

if [ "$OVERALL_STATUS" = "${CQT_STATUS_UNMEASURED}" ]; then
    # NOT exit 0, unlike "skipped". A layer that was never asked is a configuration fact
    # about the project, and a caller with only the exit code — a standalone run, or
    # AIDA's /validate-* wrappers — reads a zero as a pass. 4, never 3, which already
    # means the installed tree does not match composer.lock.
    echo -e "${YELLOW}⚠ Security audit incomplete — $(echo "$UNMEASURED_TOOLS_JSON" | jq -r 'join(", ")') had nothing to read${NC}"
    echo -e "Report: ${REPORT_FILE}"
    exit "$CQT_EXIT_UNMEASURED"
elif [ "$OVERALL_STATUS" = "skipped" ]; then
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
