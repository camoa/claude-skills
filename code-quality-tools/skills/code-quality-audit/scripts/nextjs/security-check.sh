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
cqt_report_dir_init
cqt_announce_report_dir
# Phase 2 of secret scanning: for a secret phase 1 already found, when did it enter
# history and by whom. Shared with drupal/security-check.sh so both stacks answer the
# question the same way. See the file header for why the matched value never reaches
# a file, a log line or any process's argv.
# shellcheck source=../core/secret-history.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/secret-history.sh"
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
    # under set -e would abort the entire security audit.
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
        echo -e "  ${YELLOW}Gitleaks produced no usable report (exit ${GITLEAKS_EXIT}) - secret scan did not complete${NC}"
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
    echo -e "  ${YELLOW}Gitleaks not installed (optional)${NC}"
    SKIPPED_TOOLS+=("gitleaks")
    ABSENT_TOOLS+=("gitleaks")
fi

# =====================
# Secret history — phase 2, confirmation
# =====================
# Byte-for-byte the same step as in drupal/security-check.sh, deliberately:
# /code-quality-tools:security routes by project type, and a secret finding must
# carry the same history evidence whichever stack produced it.
#
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
    # SRC_PATH does not exist, so this layer scanned nothing. Recorded as expected —
    # a project laying its source out differently is legitimate — but recorded, so a
    # scan that examined no source cannot look identical to one that examined all of it.
    echo -e "  ${YELLOW}${SRC_PATH} does not exist — no source scanned for custom patterns${NC}"
    SKIPPED_TOOLS+=("custom_patterns")
    ABSENT_TOOLS+=("custom_patterns")
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
    set +e
    SOCKET_OUTPUT=$(npx socket-npm audit 2>&1 || true)
    SOCKET_EXIT=$?
    set -e

    if [ $SOCKET_EXIT -ne 0 ] && echo "$SOCKET_OUTPUT" | grep -q "issues found"; then
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
            project_type: "nextjs",
            tools: ["npm_audit", "eslint_security", "semgrep", "trivy", "gitleaks", "custom_patterns", "socket"],
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
