#!/bin/bash
# security-check.sh - Run comprehensive security audit for Next.js
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
# CQT_STATUS_UNMEASURED / CQT_EXIT_UNMEASURED — the word and the exit code for "this gate
# produced no measurement", so a caller with only an exit status cannot read it as a pass.
# shellcheck source=../core/path-resolve.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/path-resolve.sh"
cqt_report_dir_init
cqt_announce_report_dir
# Phase 2 of secret scanning: for a secret phase 1 already found, when did it enter
# history and by whom. Shared with drupal/security-check.sh so both stacks answer the
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
SRC_PATH="${SRC_PATH:-src}"

# Render a bash array as a JSON array. Mirrors the Drupal security-check helper so both
# reports express "this tool did not run" the same way to downstream consumers.
to_json_array() {
    if [ "$#" -eq 0 ]; then
        echo "[]"
    else
        printf '%s\n' "$@" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]"
    fi
}

# Resolve the gate verdict from the severity counts AND the coverage of the scan.
# Mirrors the Drupal security-check helper so both stacks reach the same verdict from
# the same evidence; /code-quality-tools:security routes by project type, so a rule
# applied to one file only would leave the other stack able to claim clean.
#
# A verdict of "pass" is a claim that the tree is clean, and a tool that produced no
# usable result contributed a zero by not looking. So a would-be "pass" is downgraded
# to "skipped" — the value the Drupal --changed envelope already uses for "this gate
# produced no result to trust".
#
# The fourth argument is the count of UNEXPECTED failures (SKIPPED_TOOLS minus
# ABSENT_TOOLS), not of every absent tool. An optional analyzer that was never installed
# is expected absence: most machines do not have semgrep, trivy or
# eslint-plugin-security, and counting those would put every real run at "skipped",
# which is a verdict carrying no information. What does count is a tool that was present
# and still returned nothing usable.
#
# Only a would-be pass is downgraded. "warning" and "fail" already say the tree is not
# clean, and they carry findings the partial scan did produce; rewriting them as
# "skipped" would discard real evidence.
#
# Self-contained on purpose (reads no globals, echoes the verdict) so the spec can
# extract and source it in isolation.
#   resolve_security_status <critical> <high> <medium> <failed_tool_count>
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
# An exit status alone cannot decide this. For some tools a non-zero exit means "found
# things" and for others it means "failed to run", and several write a well-formed report
# even when they failed — so the count has to be read out of the report and checked, not
# swallowed into a zero. A zero that came from a tool that never ran is a clean result
# nobody earned. Each caller states its own threshold because the tools disagree; see the
# comment at each call site for what was verified about that tool.
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

    # Every one of these tools writes its report on a run that completed, so a missing or
    # empty report means the run did not complete, whatever it exited.
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

echo "=== Security Audit (Next.js/React) ==="
echo ""

# Check npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} npm is not installed"
    exit 2
fi

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

# Every analyzer that contributed no counts, whatever the reason. Reported as
# tools_absent[] so a reader can see which layers this scan did not include.
SKIPPED_TOOLS=()

# The tools that were never installed. Most analyzers here are optional by design and
# missing on a normal machine, so their absence is expected and must NOT bear on the
# verdict: treating "never installed" as failed coverage would put every real run at
# "skipped", and a verdict that fires on every run carries no information.
#
# The tools that DID fail are then derived as SKIPPED_TOOLS minus ABSENT_TOOLS, rather
# than listed a second time by hand. Two consequences, both wanted:
#   - the failed list cannot drift out of sync with the recorded skips;
#   - the default is fail-CLOSED. A tool that records a skip counts against the verdict
#     unless a branch explicitly declares its absence expected. For a security gate,
#     over-reporting incompleteness is the safe direction; the "default machine" cases
#     in false-clean-spec.sh section H catch it immediately if a branch is misfiled.
ABSENT_TOOLS=()

# Layers whose TOOL was present but whose GROUND was not. A third fact, distinct from both
# neighbours: absent = not installed, a fact about the machine; failed = ran and returned
# nothing usable; unmeasured = never asked, because the path it would have read does not
# exist. The Drupal gate grew this list in 3.9.6 and this one did not, so its only
# path-absent case — SRC_PATH missing, no source scanned for custom patterns at all — was
# filed under tools_absent[] and read as an expected absence. No scope excuses an
# unmeasured layer: it is a fact about THIS RUN, not about what is installed.
UNMEASURED_TOOLS=()

# Layers deliberately not measured, recorded so `declared - reported` is computable.
#
# A PREVENTION layer is not a scanner. Socket CLI absent already produces its own
# low-severity finding recommending installation, so filing it under tools_absent[]
# would make a consumer's fail-closed scope rule block a Next.js review on every
# project that has not installed it — the class of wrong answer cqt 3.10.0 removed on
# the Drupal side. But pushing it NOWHERE was the other error: `socket` was declared in
# meta.tools[] and appeared in no coverage array at all, so a missing Socket CLI could
# not reach any list a consumer reads. This is the third answer: recorded, visible,
# and not a coverage gap. It is subtracted from the derived failed list below.
SKIPPED_BY_DESIGN=()

# Create temp directory for individual reports
mkdir -p "${REPORT_DIR}/security"

echo -e "${BLUE}[1/7]${NC} Checking npm package vulnerabilities..."
# =====================
# npm audit
# =====================
NPM_AUDIT_JSON="${REPORT_DIR}/security/npm-audit.json"
set +e
clear_stale_report "$NPM_AUDIT_JSON"
npm audit --json > "$NPM_AUDIT_JSON" 2>/dev/null
NPM_EXIT=$?
set -e

# Verified against npm 11.6.0: exit 1 means EITHER it found vulnerabilities OR it failed.
# With no lockfile it exits 1 and writes {"error":{"code":"ENOLOCK",...}} to stdout, which
# lands in the report as well-formed JSON — so neither the exit status nor "is the report
# parseable" separates the two. What does separate them is whether the report carries a
# numeric vulnerability count, which the error object does not: the count expression
# yields null there, and the old code compared that null against 0 and printed "No package
# vulnerabilities". Exit >= 2 is a shell-level failure (126/127, 128+N).
NPM_VIOLATIONS="[]"
resolve_tool_result "$NPM_AUDIT_JSON" "$NPM_EXIT" 2 \
    '.metadata.vulnerabilities | (.critical + .high + .moderate + .low)'

if [ "$TOOL_FAILED" -eq 1 ]; then
    echo -e "  ${YELLOW}npm audit produced no usable report (exit ${NPM_EXIT}) - dependency scan did not complete${NC}"
    # npm is a hard prerequisite of this gate (it exits 2 above when npm is missing), so
    # npm audit failing is never expected absence: it is not in ABSENT_TOOLS and so
    # counts as a failure.
    SKIPPED_TOOLS+=("npm_audit")
else
    VULN_COUNT="$TOOL_COUNT"
    if [ "$VULN_COUNT" -gt 0 ]; then
        echo -e "  ${RED}Found ${VULN_COUNT} package vulnerabilities${NC}"

        # Convert to violations format
        NPM_VIOLATIONS=$(jq '[.vulnerabilities | to_entries[] | .value | {
            category: "npm Vulnerability",
            severity: (if .severity == "critical" then "critical" elif .severity == "high" then "high" elif .severity == "moderate" then "medium" else "low" end),
            file: .name,
            line: 0,
            message: (.title + " in " + .name),
            owasp: "A06:2021",
            remediation: (.recommendation.action // "Update to latest version")
        }]' "$NPM_AUDIT_JSON" 2>/dev/null || echo "[]")

        # Count by severity
        NPM_CRITICAL=$(echo "$NPM_VIOLATIONS" | jq '[.[] | select(.severity == "critical")] | length' 2>/dev/null || echo "0")
        NPM_HIGH=$(echo "$NPM_VIOLATIONS" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
        NPM_MEDIUM=$(echo "$NPM_VIOLATIONS" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
        NPM_LOW=$(echo "$NPM_VIOLATIONS" | jq '[.[] | select(.severity == "low")] | length' 2>/dev/null || echo "0")

        CRITICAL_COUNT=$((CRITICAL_COUNT + NPM_CRITICAL))
        HIGH_COUNT=$((HIGH_COUNT + NPM_HIGH))
        MEDIUM_COUNT=$((MEDIUM_COUNT + NPM_MEDIUM))
        LOW_COUNT=$((LOW_COUNT + NPM_LOW))
    else
        echo -e "  ${GREEN}No package vulnerabilities${NC}"
    fi
fi

echo ""
echo -e "${BLUE}[2/7]${NC} Running ESLint security checks..."
# =====================
# ESLint Security Plugins
# =====================
ESLINT_JSON="${REPORT_DIR}/security/eslint-security.json"
ESLINT_ISSUES="[]"

# Check if eslint-plugin-security is installed
if npm list eslint-plugin-security &> /dev/null; then
    set +e
    clear_stale_report "$ESLINT_JSON"
    npx eslint --format json --ext .js,.jsx,.ts,.tsx . > "$ESLINT_JSON" 2>/dev/null
    ESLINT_EXIT=$?
    set -e

    # Verified against eslint 10.8.1: exit 1 means it RAN and found lint errors, which is
    # a finding and not a failure. Only exit >= 2 is fatal — a bad config or no matching
    # files — and eslint leaves the report empty in those cases.
    #
    # The rule filter is null-safe on purpose. A file eslint cannot parse produces a
    # message with ruleId null, and `null | startswith(...)` fails the whole expression;
    # one syntax error anywhere in the tree used to zero out the security count for the
    # entire project.
    resolve_tool_result "$ESLINT_JSON" "$ESLINT_EXIT" 2 \
        '[.[] | .messages[] | select((.ruleId // "") | startswith("security/") or startswith("no-secrets/"))] | length'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "  ${YELLOW}ESLint produced no usable report (exit ${ESLINT_EXIT}) - security lint did not complete${NC}"
        # Reached only inside the "eslint-plugin-security is installed" branch, so the
        # tool was there and failed. The else branch below is the expected absence.
        SKIPPED_TOOLS+=("eslint_security")
    else
        SECURITY_COUNT="$TOOL_COUNT"
        if [ "$SECURITY_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${SECURITY_COUNT} ESLint security findings${NC}"

            # Convert to violations format
            ESLINT_ISSUES=$(jq '[.[] | .filePath as $file | .messages[] | select((.ruleId // "") | startswith("security/") or startswith("no-secrets/")) | {
                category: "ESLint Security",
                severity: (if .severity == 2 then "high" else "medium" end),
                file: $file,
                line: .line,
                message: .message,
                owasp: "A03:2021",
                remediation: ("Fix " + .ruleId + " violation")
            }]' "$ESLINT_JSON" 2>/dev/null || echo "[]")

            ESLINT_HIGH=$(echo "$ESLINT_ISSUES" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
            ESLINT_MEDIUM=$(echo "$ESLINT_ISSUES" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")

            HIGH_COUNT=$((HIGH_COUNT + ESLINT_HIGH))
            MEDIUM_COUNT=$((MEDIUM_COUNT + ESLINT_MEDIUM))
        else
            echo -e "  ${GREEN}No ESLint security issues${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}eslint-plugin-security not installed (optional)${NC}"
    SKIPPED_TOOLS+=("eslint_security")
    ABSENT_TOOLS+=("eslint_security")
fi

echo ""
echo -e "${BLUE}[3/7]${NC} Running Semgrep SAST (React/Next.js)..."
# =====================
# Semgrep SAST
# =====================
SEMGREP_JSON="${REPORT_DIR}/security/semgrep.json"
SEMGREP_ISSUES="[]"

if command -v semgrep &> /dev/null; then
    set +e
    clear_stale_report "$SEMGREP_JSON"
    # Run Semgrep with auto config (includes React/JS/TS security rules)
    semgrep scan --config=auto --json --output "$SEMGREP_JSON" . 2>/dev/null
    SEMGREP_EXIT=$?
    set -e

    # Verified against semgrep 1.172.0: findings do NOT change the exit status unless
    # --error is passed, so exit 0 means it ran and ANY non-zero means it failed — 2 for
    # an invalid scanning root, 7 when every rule fails to load. It still writes a report
    # in those cases, with results empty and the real problem in .errors, so the report on
    # its own reads as a clean tree.
    resolve_tool_result "$SEMGREP_JSON" "$SEMGREP_EXIT" 1 \
        '[.results[] | select(.extra.severity == "ERROR" or .extra.severity == "WARNING")] | length'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "  ${YELLOW}Semgrep produced no usable report (exit ${SEMGREP_EXIT}) - SAST scan did not complete${NC}"
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
    echo -e "  ${YELLOW}Semgrep not installed (optional)${NC}"
    SKIPPED_TOOLS+=("semgrep")
    ABSENT_TOOLS+=("semgrep")
fi

echo ""
echo -e "${BLUE}[4/7]${NC} Running Trivy dependency/secret scanner..."
# =====================
# Trivy Scanner
# =====================
TRIVY_JSON="${REPORT_DIR}/security/trivy.json"
TRIVY_ISSUES="[]"

if command -v trivy &> /dev/null; then
    set +e
    clear_stale_report "$TRIVY_JSON"
    # Run Trivy on filesystem (dependency + secret scanning)
    trivy fs --scanners vuln,secret --format json --output "$TRIVY_JSON" . 2>/dev/null
    TRIVY_EXIT=$?
    set -e

    # Verified against trivy 0.73.0: findings do NOT change the exit status unless
    # --exit-code is passed, so exit 0 means it ran and ANY non-zero means it failed. A
    # bad scanner name, a missing target and an unwritable --output all exit 1 and write
    # no report at all, which is why the report path is cleared before the run.
    resolve_tool_result "$TRIVY_JSON" "$TRIVY_EXIT" 1 \
        '[.Results[]?.Vulnerabilities[]?, .Results[]?.Secrets[]?] | length'

    if [ "$TOOL_FAILED" -eq 1 ]; then
        echo -e "  ${YELLOW}Trivy produced no usable report (exit ${TRIVY_EXIT}) - dependency and secret scan did not complete${NC}"
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
    echo -e "  ${YELLOW}Trivy not installed (optional)${NC}"
    SKIPPED_TOOLS+=("trivy")
    ABSENT_TOOLS+=("trivy")
fi

echo ""
echo -e "${BLUE}[5/7]${NC} Running Gitleaks secret detection..."
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
echo -e "${BLUE}[6/7]${NC} Checking React/Next.js security patterns..."
# =====================
# Custom React/Next.js Pattern Checks
# =====================
CUSTOM_ISSUES="[]"

# Check for dangerouslySetInnerHTML
if [ -d "$SRC_PATH" ]; then
    DANGEROUS_HTML=$(grep -rn "dangerouslySetInnerHTML" "$SRC_PATH" 2>/dev/null || true)
    if [ -n "$DANGEROUS_HTML" ]; then
        echo -e "  ${YELLOW}Found dangerouslySetInnerHTML usage${NC}"
        CUSTOM_COUNT=$(echo "$DANGEROUS_HTML" | wc -l)
        MEDIUM_COUNT=$((MEDIUM_COUNT + CUSTOM_COUNT))
    fi

    # Check for eval() usage
    EVAL_USAGE=$(grep -rn "\beval(" "$SRC_PATH" 2>/dev/null || true)
    if [ -n "$EVAL_USAGE" ]; then
        echo -e "  ${YELLOW}Found eval() usage${NC}"
        EVAL_COUNT=$(echo "$EVAL_USAGE" | wc -l)
        HIGH_COUNT=$((HIGH_COUNT + EVAL_COUNT))
    fi

    # Check for window.location href XSS
    HREF_XSS=$(grep -rn "window\.location\.href\s*=" "$SRC_PATH" 2>/dev/null || true)
    if [ -n "$HREF_XSS" ]; then
        echo -e "  ${YELLOW}Found window.location.href assignments (potential XSS)${NC}"
        HREF_COUNT=$(echo "$HREF_XSS" | wc -l)
        MEDIUM_COUNT=$((MEDIUM_COUNT + HREF_COUNT))
    fi

    if [ -z "$DANGEROUS_HTML" ] && [ -z "$EVAL_USAGE" ] && [ -z "$HREF_XSS" ]; then
        echo -e "  ${GREEN}No custom pattern violations${NC}"
    fi
else
    # SRC_PATH does not exist, so this layer scanned NOTHING. That is the GROUND being
    # absent, not the TOOL: the pattern check is a grep implemented here and is always
    # present. Recorded as tools_absent[] it read as an expected, non-blocking absence —
    # and since 3.10.2 classifies custom_patterns as `builtin` (nothing to install), it
    # stopped blocking altogether, so a Next.js scan that examined no source at all
    # reported the same clean bill of health as one that examined everything. The two
    # facts have been conflated in this codebase before; tools_unmeasured[] is the one
    # that means "the path it would have read is not there", and no scope excuses it.
    echo -e "  ${YELLOW}[UNMEASURED]${NC} ${SRC_PATH} does not exist — no source was scanned for custom patterns"
    SKIPPED_TOOLS+=("custom_patterns")
    UNMEASURED_TOOLS+=("custom_patterns")
fi

echo ""
echo -e "${BLUE}[7/7]${NC} Verifying Socket CLI (supply chain security)..."
# =====================
# Socket CLI (Supply Chain Security)
# =====================
SOCKET_ISSUES="[]"

if npx socket-npm --version &> /dev/null 2>&1; then
    echo -e "  ${GREEN}Socket CLI is installed${NC}"
    echo -e "  ${BLUE}[INFO]${NC} Socket CLI detects supply chain attacks in npm packages"

    # Run Socket CLI audit (lightweight check)
    #
    # The `|| true` used to sit INSIDE this command substitution. A substitution's exit
    # status is the status of the command inside it, so `$(... || true)` always
    # succeeded and SOCKET_EXIT was 0 on every run. The guard below is `-ne 0`, so its
    # findings branch was unreachable: an INSTALLED Socket CLI printed "No supply chain
    # issues detected" whatever it had actually found, and one of the seven layers this
    # gate advertises could not report anything. `set +e` is what keeps the non-zero
    # from aborting the script; the `|| true` was never doing that job.
    set +e
    SOCKET_OUTPUT=$(npx socket-npm audit 2>&1)
    SOCKET_EXIT=$?
    set -e

    if [ "$SOCKET_EXIT" -ne 0 ] && echo "$SOCKET_OUTPUT" | grep -q "issues found"; then
        echo -e "  ${YELLOW}Socket CLI found supply chain issues${NC}"
        # Add informational issue
        SOCKET_ISSUES=$(jq -n '[{
            category: "Socket Supply Chain",
            severity: "medium",
            file: "package.json",
            line: 1,
            message: "Socket CLI detected supply chain security issues",
            owasp: "A08:2021",
            remediation: "Review Socket CLI output: npx socket-npm audit"
        }]')
        MEDIUM_COUNT=$((MEDIUM_COUNT + 1))
    elif [ "$SOCKET_EXIT" -ne 0 ]; then
        # It ran, it failed, and it said nothing this gate can read — not authenticated,
        # no network, an unrecognised subcommand. That is not a clean bill of health, so
        # it is recorded as a skip and lands in tools_failed[] through the derivation
        # below. Reachable only because SOCKET_EXIT is now the audit's own status.
        echo -e "  ${YELLOW}[SKIP]${NC} Socket CLI exited ${SOCKET_EXIT} with no readable result"
        SKIPPED_TOOLS+=("socket")
    else
        echo -e "  ${GREEN}No supply chain issues detected${NC}"
    fi
else
    echo -e "  ${YELLOW}Socket CLI not installed (recommended)${NC}"
    echo -e "  ${BLUE}[INFO]${NC} Install with: npm install -D @socketsecurity/cli"

    # Add informational issue
    SOCKET_ISSUES=$(jq -n '[{
        category: "Socket Supply Chain",
        severity: "low",
        file: "package.json",
        line: 1,
        message: "Socket CLI not installed - detects supply chain attacks",
        owasp: "A08:2021",
        remediation: "Run: npm install -D @socketsecurity/cli"
    }]')

    LOW_COUNT=$((LOW_COUNT + 1))
    # Declared in meta.tools[] and pushed nowhere until 3.10.4, so a missing Socket CLI
    # reached no coverage list. By-design rather than absent: see SKIPPED_BY_DESIGN.
    SKIPPED_TOOLS+=("socket")
    SKIPPED_BY_DESIGN+=("socket")
fi

# =====================
# Combine all issues
# =====================
ISSUES=$(jq -n \
    --argjson npm "$NPM_VIOLATIONS" \
    --argjson eslint "$ESLINT_ISSUES" \
    --argjson semgrep "$SEMGREP_ISSUES" \
    --argjson trivy "$TRIVY_ISSUES" \
    --argjson gitleaks "$GITLEAKS_ISSUES" \
    --argjson custom "$CUSTOM_ISSUES" \
    --argjson socket "$SOCKET_ISSUES" \
    '$npm + $eslint + $semgrep + $trivy + $gitleaks + $custom + $socket')

# =====================
# Determine overall status
# =====================
# The severity counts are only half the verdict. The failed set — the analyzers that
# were present and still returned nothing usable — is what a zero cannot be trusted
# from. Absent-by-design tools stay in tools_absent[] and are reported, but they do not
# move the verdict; see resolve_security_status().
# THREE disjoint lists, each stating ONE fact — the same split the Drupal gate carries.
# tools_absent = the BINARY IS NOT INSTALLED, a fact about the machine; it does not move
# this gate's own verdict, and it is the only one of the three a consumer's scope rule may
# excuse. tools_failed = the layer was there and returned nothing usable (crashed,
# unparseable report, stale report) — a zero from it is not evidence, so it downgrades a
# would-be pass. tools_unmeasured = the layer was never asked, because the path it would
# have read does not exist. Every non-produced result lands in exactly one of the three.
SKIPPED_TOOLS_JSON=$(to_json_array "${SKIPPED_TOOLS[@]+"${SKIPPED_TOOLS[@]}"}")
ABSENT_TOOLS_JSON=$(to_json_array "${ABSENT_TOOLS[@]+"${ABSENT_TOOLS[@]}"}")
UNMEASURED_TOOLS_JSON=$(to_json_array "${UNMEASURED_TOOLS[@]+"${UNMEASURED_TOOLS[@]}"}")
BY_DESIGN_TOOLS_JSON=$(to_json_array "${SKIPPED_BY_DESIGN[@]+"${SKIPPED_BY_DESIGN[@]}"}")
FAILED_TOOLS_JSON=$(jq -n --argjson skipped "$SKIPPED_TOOLS_JSON" \
    --argjson absent "$ABSENT_TOOLS_JSON" \
    --argjson unmeasured "$UNMEASURED_TOOLS_JSON" \
    --argjson by_design "$BY_DESIGN_TOOLS_JSON" \
    '$skipped - $absent - $unmeasured - $by_design')
FAILED_COUNT=$(echo "$FAILED_TOOLS_JSON" | jq 'length')

OVERALL_STATUS=$(resolve_security_status \
    "$CRITICAL_COUNT" "$HIGH_COUNT" "$MEDIUM_COUNT" "$FAILED_COUNT")

# A layer that was never asked CAPS a would-be pass, exactly as it does on the Drupal path.
# A scan that read no source at all must not report what a scan that read all of it reports.
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
            project_type: "nextjs",
            tools: ["npm_audit", "eslint_security", "semgrep", "trivy", "gitleaks", "custom_patterns", "socket"],
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
    # A layer was never asked, because the path it would have read is not there. Exits 4
    # and never 0: a caller with only the exit code reads a zero as a pass, which is how a
    # Next.js scan that read no source at all reported a clean tree.
    echo -e "${YELLOW}⚠ Security audit UNMEASURED — $(echo "$UNMEASURED_TOOLS_JSON" | jq -r 'join(", ")') had nothing to read${NC}"
    echo -e "Report: ${REPORT_FILE}"
    exit "$CQT_EXIT_UNMEASURED"
elif [ "$OVERALL_STATUS" = "skipped" ]; then
    # Zero findings, but the scan did not cover its ground. Exits 0 like the pass it
    # would otherwise have been — the consequence is carried by the status, not by a
    # new exit code.
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
