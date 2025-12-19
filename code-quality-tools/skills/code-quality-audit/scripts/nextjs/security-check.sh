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

REPORT_DIR="${REPORT_DIR:-.reports}"
SRC_PATH="${SRC_PATH:-src}"

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

# Create temp directory for individual reports
mkdir -p "${REPORT_DIR}/security"

echo -e "${BLUE}[1/7]${NC} Checking npm package vulnerabilities..."
# =====================
# npm audit
# =====================
NPM_AUDIT_JSON="${REPORT_DIR}/security/npm-audit.json"
set +e
npm audit --json > "$NPM_AUDIT_JSON" 2>/dev/null
NPM_EXIT=$?
set -e

NPM_VIOLATIONS="[]"
if [ -f "$NPM_AUDIT_JSON" ] && [ -s "$NPM_AUDIT_JSON" ]; then
    VULN_COUNT=$(jq '.metadata.vulnerabilities | (.critical + .high + .moderate + .low)' "$NPM_AUDIT_JSON" 2>/dev/null || echo "0")
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

        ((CRITICAL_COUNT += NPM_CRITICAL))
        ((HIGH_COUNT += NPM_HIGH))
        ((MEDIUM_COUNT += NPM_MEDIUM))
        ((LOW_COUNT += NPM_LOW))
    else
        echo -e "  ${GREEN}No package vulnerabilities${NC}"
    fi
else
    echo -e "  ${YELLOW}npm audit unavailable${NC}"
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
    npx eslint --format json --ext .js,.jsx,.ts,.tsx . > "$ESLINT_JSON" 2>/dev/null
    ESLINT_EXIT=$?
    set -e

    if [ -f "$ESLINT_JSON" ] && [ -s "$ESLINT_JSON" ]; then
        # Filter for security-related rules
        SECURITY_COUNT=$(jq '[.[] | .messages[] | select(.ruleId | startswith("security/") or startswith("no-secrets/"))] | length' "$ESLINT_JSON" 2>/dev/null || echo "0")
        if [ "$SECURITY_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${SECURITY_COUNT} ESLint security findings${NC}"

            # Convert to violations format
            ESLINT_ISSUES=$(jq '[.[] | .filePath as $file | .messages[] | select(.ruleId | startswith("security/") or startswith("no-secrets/")) | {
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

            ((HIGH_COUNT += ESLINT_HIGH))
            ((MEDIUM_COUNT += ESLINT_MEDIUM))
        else
            echo -e "  ${GREEN}No ESLint security issues${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}eslint-plugin-security not installed (optional)${NC}"
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
    # Run Semgrep with auto config (includes React/JS/TS security rules)
    semgrep scan --config=auto --json --output "$SEMGREP_JSON" . 2>/dev/null
    SEMGREP_EXIT=$?
    set -e

    if [ -f "$SEMGREP_JSON" ] && [ -s "$SEMGREP_JSON" ]; then
        VULN_COUNT=$(jq '[.results[] | select(.extra.severity == "ERROR" or .extra.severity == "WARNING")] | length' "$SEMGREP_JSON" 2>/dev/null || echo "0")
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

            ((HIGH_COUNT += SEMGREP_HIGH))
            ((MEDIUM_COUNT += SEMGREP_MEDIUM))
            ((LOW_COUNT += SEMGREP_LOW))
        else
            echo -e "  ${GREEN}No Semgrep issues${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}Semgrep not installed (optional)${NC}"
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
    # Run Trivy on filesystem (dependency + secret scanning)
    trivy fs --scanners vuln,secret --format json --output "$TRIVY_JSON" . 2>/dev/null
    TRIVY_EXIT=$?
    set -e

    if [ -f "$TRIVY_JSON" ] && [ -s "$TRIVY_JSON" ]; then
        VULN_COUNT=$(jq '[.Results[]?.Vulnerabilities[]?, .Results[]?.Secrets[]?] | length' "$TRIVY_JSON" 2>/dev/null || echo "0")
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

            ((CRITICAL_COUNT += TRIVY_CRITICAL))
            ((HIGH_COUNT += TRIVY_HIGH))
            ((MEDIUM_COUNT += TRIVY_MEDIUM))
            ((LOW_COUNT += TRIVY_LOW))
        else
            echo -e "  ${GREEN}No Trivy issues${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}Trivy not installed (optional)${NC}"
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
    # Run Gitleaks on the repository
    gitleaks detect --report-format json --report-path "$GITLEAKS_JSON" --no-git 2>/dev/null
    GITLEAKS_EXIT=$?
    set -e

    if [ -f "$GITLEAKS_JSON" ] && [ -s "$GITLEAKS_JSON" ]; then
        SECRET_COUNT=$(jq 'length' "$GITLEAKS_JSON" 2>/dev/null || echo "0")
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

            ((CRITICAL_COUNT += SECRET_COUNT))
        else
            echo -e "  ${GREEN}No secrets detected${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}Gitleaks not installed (optional)${NC}"
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
        ((MEDIUM_COUNT += CUSTOM_COUNT))
    fi

    # Check for eval() usage
    EVAL_USAGE=$(grep -rn "\beval(" "$SRC_PATH" 2>/dev/null || true)
    if [ -n "$EVAL_USAGE" ]; then
        echo -e "  ${YELLOW}Found eval() usage${NC}"
        EVAL_COUNT=$(echo "$EVAL_USAGE" | wc -l)
        ((HIGH_COUNT += EVAL_COUNT))
    fi

    # Check for window.location href XSS
    HREF_XSS=$(grep -rn "window\.location\.href\s*=" "$SRC_PATH" 2>/dev/null || true)
    if [ -n "$HREF_XSS" ]; then
        echo -e "  ${YELLOW}Found window.location.href assignments (potential XSS)${NC}"
        HREF_COUNT=$(echo "$HREF_XSS" | wc -l)
        ((MEDIUM_COUNT += HREF_COUNT))
    fi

    if [ -z "$DANGEROUS_HTML" ] && [ -z "$EVAL_USAGE" ] && [ -z "$HREF_XSS" ]; then
        echo -e "  ${GREEN}No custom pattern violations${NC}"
    fi
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
        ((MEDIUM_COUNT += 1))
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

    ((LOW_COUNT += 1))
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
OVERALL_STATUS="pass"
if [ "$CRITICAL_COUNT" -gt 0 ]; then
    OVERALL_STATUS="fail"
elif [ "$HIGH_COUNT" -gt 3 ]; then
    OVERALL_STATUS="fail"
elif [ "$HIGH_COUNT" -gt 0 ] || [ "$MEDIUM_COUNT" -gt 10 ]; then
    OVERALL_STATUS="warning"
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
    '{
        meta: {
            timestamp: $timestamp,
            scan_type: "security_audit",
            project_type: "nextjs",
            tools: ["npm_audit", "eslint_security", "semgrep", "trivy", "gitleaks", "custom_patterns", "socket"]
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

if [ "$OVERALL_STATUS" = "pass" ]; then
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
