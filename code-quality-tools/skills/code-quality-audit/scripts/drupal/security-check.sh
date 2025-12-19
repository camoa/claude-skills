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

REPORT_DIR="${REPORT_DIR:-.reports}"
DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"
DRUPAL_THEMES_PATH="${DRUPAL_THEMES_PATH:-web/themes/custom}"

echo "=== Security Audit (OWASP + Drupal) ==="
echo ""

# Check DDEV
if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
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

echo -e "${BLUE}[1/10]${NC} Checking Drupal security advisories..."
# =====================
# Drush pm:security
# =====================
DRUSH_SECURITY_JSON="${REPORT_DIR}/security/drush-security.json"
set +e
ddev drush pm:security --format=json > "$DRUSH_SECURITY_JSON" 2>/dev/null
DRUSH_EXIT=$?
set -e

if [ -f "$DRUSH_SECURITY_JSON" ] && [ -s "$DRUSH_SECURITY_JSON" ]; then
    ADVISORY_COUNT=$(jq 'length' "$DRUSH_SECURITY_JSON" 2>/dev/null || echo "0")
    if [ "$ADVISORY_COUNT" -gt 0 ]; then
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

        ((CRITICAL_COUNT += ADVISORY_COUNT))
    else
        echo -e "  ${GREEN}No security advisories${NC}"
        DRUSH_VIOLATIONS="[]"
    fi
else
    echo -e "  ${YELLOW}Drush security check unavailable${NC}"
    DRUSH_VIOLATIONS="[]"
fi

echo ""
echo -e "${BLUE}[2/10]${NC} Checking composer package vulnerabilities..."
# =====================
# Composer audit
# =====================
COMPOSER_AUDIT_JSON="${REPORT_DIR}/security/composer-audit.json"
set +e
ddev composer audit --format=json > "$COMPOSER_AUDIT_JSON" 2>/dev/null
COMPOSER_EXIT=$?
set -e

if [ -f "$COMPOSER_AUDIT_JSON" ] && [ -s "$COMPOSER_AUDIT_JSON" ]; then
    VULN_COUNT=$(jq '[.advisories // {} | to_entries[]] | length' "$COMPOSER_AUDIT_JSON" 2>/dev/null || echo "0")
    if [ "$VULN_COUNT" -gt 0 ]; then
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
        ((HIGH_COUNT += HIGH_VULNS))
        ((MEDIUM_COUNT += MED_VULNS))
    else
        echo -e "  ${GREEN}No package vulnerabilities${NC}"
        COMPOSER_VIOLATIONS="[]"
    fi
else
    echo -e "  ${YELLOW}Composer audit unavailable${NC}"
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

    if [ -f "$PHPCS_SECURITY_JSON" ] && [ -s "$PHPCS_SECURITY_JSON" ]; then
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
            ((HIGH_COUNT += PHPCS_HIGH))
            ((MEDIUM_COUNT += PHPCS_MED))
        else
            echo -e "  ${GREEN}No PHPCS security issues${NC}"
        fi
    else
        echo -e "  ${GREEN}No PHPCS security issues${NC}"
        PHPCS_ISSUES="[]"
    fi
else
    echo -e "  ${YELLOW}PHPCS security linter not installed (optional)${NC}"
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
    ddev exec vendor/bin/psalm --taint-analysis \
        --report="${PSALM_TAINT_JSON}" \
        --output-format=json \
        --no-cache \
        2>/dev/null
    PSALM_EXIT=$?
    set -e

    if [ -f "$PSALM_TAINT_JSON" ] && [ -s "$PSALM_TAINT_JSON" ]; then
        PSALM_ISSUES=$(jq '[.[] | {
            category: ("Psalm Taint - " + (.type // "Unknown")),
            severity: (if (.severity // 0) <= 3 then "high" elif (.severity // 0) <= 5 then "medium" else "low" end),
            file: .file_path,
            line: .line_from,
            message: .message,
            owasp: (if (.type | contains("Sql")) then "A03:2021" elif (.type | contains("Html") or (.type | contains("Xss"))) then "A03:2021" else "Various" end),
            remediation: "Sanitize tainted input before use"
        }]' "$PSALM_TAINT_JSON" 2>/dev/null || echo "[]")

        PSALM_COUNT=$(echo "$PSALM_ISSUES" | jq 'length' 2>/dev/null || echo "0")
        if [ "$PSALM_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}Found ${PSALM_COUNT} taint analysis issues${NC}"

            PSALM_HIGH=$(echo "$PSALM_ISSUES" | jq '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
            PSALM_MED=$(echo "$PSALM_ISSUES" | jq '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
            PSALM_LOW=$(echo "$PSALM_ISSUES" | jq '[.[] | select(.severity == "low")] | length' 2>/dev/null || echo "0")
            ((HIGH_COUNT += PSALM_HIGH))
            ((MEDIUM_COUNT += PSALM_MED))
            ((LOW_COUNT += PSALM_LOW))
        else
            echo -e "  ${GREEN}No taint analysis issues${NC}"
        fi
    else
        echo -e "  ${GREEN}No taint analysis issues${NC}"
        PSALM_ISSUES="[]"
    fi
else
    echo -e "  ${YELLOW}Psalm not installed (optional but recommended)${NC}"
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
    # Unsafe db_query usage
    DB_QUERY_UNSAFE=$(grep -rn "db_query.*\$" "${DRUPAL_MODULES_PATH}" --include="*.php" --include="*.module" --include="*.inc" 2>/dev/null || true)
    if [ -n "$DB_QUERY_UNSAFE" ]; then
        DB_COUNT=$(echo "$DB_QUERY_UNSAFE" | wc -l)
        echo -e "  ${YELLOW}Found ${DB_COUNT} potentially unsafe db_query() calls${NC}"
        ((HIGH_COUNT += DB_COUNT))

        # Add to issues (simplified)
        CUSTOM_ISSUES=$(echo "$CUSTOM_ISSUES" | jq '. + [{
            category: "SQL Injection Risk",
            severity: "high",
            file: "Multiple files",
            line: 0,
            message: "Potentially unsafe db_query() with variable concatenation",
            owasp: "A03:2021",
            remediation: "Use placeholders or query builder"
        }]')
    fi

    # Twig |raw filter
    RAW_FILTER=$(grep -rn "|raw" "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}" --include="*.twig" 2>/dev/null || true)
    if [ -n "$RAW_FILTER" ]; then
        RAW_COUNT=$(echo "$RAW_FILTER" | wc -l)
        echo -e "  ${YELLOW}Found ${RAW_COUNT} uses of |raw filter in Twig${NC}"
        ((MEDIUM_COUNT += RAW_COUNT))

        CUSTOM_ISSUES=$(echo "$CUSTOM_ISSUES" | jq '. + [{
            category: "XSS Risk",
            severity: "medium",
            file: "Twig templates",
            line: 0,
            message: "Use of |raw filter may expose XSS vulnerabilities",
            owasp: "A03:2021",
            remediation: "Remove |raw or ensure input is sanitized"
        }]')
    fi

    # unserialize() on user input
    UNSERIALIZE=$(grep -rn "unserialize.*\$_" "${DRUPAL_MODULES_PATH}" --include="*.php" --include="*.module" 2>/dev/null || true)
    if [ -n "$UNSERIALIZE" ]; then
        UNSER_COUNT=$(echo "$UNSERIALIZE" | wc -l)
        echo -e "  ${YELLOW}Found ${UNSER_COUNT} potentially unsafe unserialize() calls${NC}"
        ((HIGH_COUNT += UNSER_COUNT))

        CUSTOM_ISSUES=$(echo "$CUSTOM_ISSUES" | jq '. + [{
            category: "Insecure Deserialization",
            severity: "high",
            file: "Multiple files",
            line: 0,
            message: "unserialize() on user input can lead to RCE",
            owasp: "A08:2021",
            remediation: "Use JSON or validate serialized data"
        }]')
    fi
fi

if [ "$CUSTOM_ISSUES" = "[]" ]; then
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

    if [ -f "$SECREVIEW_JSON" ] && [ -s "$SECREVIEW_JSON" ]; then
        FAILED_CHECKS=$(jq '[.[] | select(.result == "fail")] | length' "$SECREVIEW_JSON" 2>/dev/null || echo "0")
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

            ((MEDIUM_COUNT += FAILED_CHECKS))
        else
            echo -e "  ${GREEN}All security review checks passed${NC}"
            SECREVIEW_ISSUES="[]"
        fi
    else
        SECREVIEW_ISSUES="[]"
    fi
else
    echo -e "  ${YELLOW}Security Review module not installed (optional)${NC}"
    SECREVIEW_ISSUES="[]"
fi

echo ""
echo -e "${BLUE}[7/10]${NC} Running Semgrep SAST (multi-language)..."
# =====================
# Semgrep SAST
# =====================
SEMGREP_JSON="${REPORT_DIR}/security/semgrep.json"
SEMGREP_ISSUES="[]"

if ddev exec semgrep --version &> /dev/null || command -v semgrep &> /dev/null; then
    set +e
    # Run Semgrep with auto config (includes security rules)
    if ddev describe &> /dev/null; then
        ddev exec semgrep scan --config=auto --json \
            "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}" > "$SEMGREP_JSON" 2>/dev/null
    else
        semgrep scan --config=auto --json \
            "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}" > "$SEMGREP_JSON" 2>/dev/null
    fi
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
echo -e "${BLUE}[8/10]${NC} Running Trivy dependency/secret scanner..."
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
echo -e "${BLUE}[9/10]${NC} Running Gitleaks secret detection..."
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

    ((LOW_COUNT += 1))
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
            tools: ["drush_pm_security", "composer_audit", "phpcs_security_linter", "psalm_taint", "custom_patterns", "security_review", "semgrep", "trivy", "gitleaks", "roave"]
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
