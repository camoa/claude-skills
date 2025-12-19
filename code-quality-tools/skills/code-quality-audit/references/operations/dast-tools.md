# DAST Security Tools (Optional)

Dynamic Application Security Testing for pre-production and staging environments.

## Contents

- [Overview](#overview)
- [SAST vs DAST](#sast-vs-dast)
- [When to Use DAST](#when-to-use-dast)
- [OWASP ZAP](#owasp-zap)
- [Nuclei](#nuclei)
- [Installation](#installation)
- [Usage Examples](#usage-examples)
- [CI/CD Integration](#cicd-integration)

---

## Overview

DAST (Dynamic Application Security Testing) tools test running applications to find vulnerabilities that only appear at runtime.

**Status:** Optional - Use in staging/pre-production environments
**Requires:** Running application (local dev server, staging URL, or production-like environment)
**Phase:** Pre-production testing (after SAST, before release)

---

## SAST vs DAST

### SAST (v2.0.0 - Already Implemented)
- **Analyzes:** Source code (static analysis)
- **Runs:** Without executing the application
- **Finds:** Code-level vulnerabilities, patterns, misconfigurations
- **Speed:** Fast (seconds to minutes)
- **When:** During development, in CI/CD
- **Tools:** Semgrep, PHPStan, ESLint, Psalm, Trivy

### DAST (v2.1.0 - This Document)
- **Analyzes:** Running application (dynamic testing)
- **Runs:** Against deployed/running application
- **Finds:** Runtime vulnerabilities, configuration issues, authentication flaws
- **Speed:** Slower (minutes to hours)
- **When:** Staging, pre-production, security audits
- **Tools:** OWASP ZAP, Nuclei

**Key Difference:** SAST finds issues in code, DAST finds issues in running applications.

---

## When to Use DAST

### ✅ Good Use Cases

**Staging/Pre-Production:**
- Before major releases
- Weekly/monthly security audits
- After infrastructure changes
- Before penetration testing

**Local Development:**
- Testing authentication flows
- Validating API security
- Checking CORS configurations
- Testing rate limiting

**Security Audits:**
- Compliance requirements (PCI-DSS, HIPAA)
- Internal security reviews
- External penetration test preparation

### ❌ NOT Recommended

**CI/CD Pipelines:**
- Too slow for every commit
- Requires running application
- Can cause false positives on incomplete features

**Development Workflow:**
- Use SAST (Semgrep, PHPStan) instead
- DAST is for integration/staging phase

**Production:**
- Use DAST on staging environment that mirrors production
- Active scanning can impact performance

---

## OWASP ZAP

OWASP Zed Attack Proxy - Full-featured DAST scanner maintained by OWASP.

### Features

**Active Scanning:**
- SQL injection testing
- XSS vulnerability detection
- Path traversal testing
- Command injection detection

**Passive Scanning:**
- Analyzes traffic without attacking
- Detects missing security headers
- Identifies sensitive data exposure
- Checks cookie security

**Spider/Crawler:**
- Discovers all application endpoints
- Maps application structure
- Finds hidden pages
- Tests authentication flows

**Authentication Testing:**
- Session management
- Password policies
- Multi-factor authentication
- OAuth/SAML flows

### OWASP Top 10 Coverage

| Category | Detection Method |
|----------|-----------------|
| A01:2021 Broken Access Control | Active scan + manual testing |
| A02:2021 Cryptographic Failures | Passive scan (weak SSL/TLS) |
| A03:2021 Injection | Active scan (SQLi, XSS, command) |
| A04:2021 Insecure Design | Manual testing required |
| A05:2021 Security Misconfiguration | Passive scan (headers, versions) |
| A06:2021 Vulnerable Components | Version detection |
| A07:2021 Authentication Failures | Authentication testing |
| A08:2021 Software/Data Integrity | Passive scan |
| A09:2021 Security Logging | Manual review |
| A10:2021 SSRF | Active scan |

---

## Nuclei

Template-based vulnerability scanner by ProjectDiscovery.

### Features

**1000+ Templates:**
- CVE detection (latest vulnerabilities)
- Misconfiguration detection
- Exposed admin panels
- Default credentials
- Technology fingerprinting

**Fast and Efficient:**
- Parallel scanning
- Low false positive rate
- Regular template updates
- Custom template support

**Coverage Areas:**
- Known CVEs (2015-2025)
- Exposed services (phpMyAdmin, Jenkins, etc.)
- Misconfigurations (CORS, CSP, etc.)
- Information disclosure
- DNS/subdomain enumeration

### Template Categories

| Category | Examples |
|----------|----------|
| CVEs | CVE-2023-*, CVE-2024-* |
| Exposed Panels | phpMyAdmin, Adminer, Grafana |
| Misconfigurations | CORS, CSP, HTTP headers |
| Default Credentials | Admin panels, databases |
| Technologies | Framework detection, version info |

---

## Installation

### OWASP ZAP

**Option 1: Docker (Recommended)**
```bash
# Pull OWASP ZAP Docker image
docker pull zaproxy/zap-stable

# Verify installation
docker run --rm zaproxy/zap-stable zap.sh -version
```

**Option 2: Direct Install**
```bash
# Download from https://www.zaproxy.org/download/
# Install for your OS (Linux/Mac/Windows)

# Verify installation
zap.sh -version
```

**Option 3: Snap (Linux)**
```bash
sudo snap install zaproxy --classic
zap.sh -version
```

### Nuclei

**Installation via Go:**
```bash
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Update templates
nuclei -update-templates

# Verify installation
nuclei -version
```

**Installation via Package Manager (Linux):**
```bash
# Download latest release
wget https://github.com/projectdiscovery/nuclei/releases/download/v3.1.5/nuclei_3.1.5_linux_amd64.zip
unzip nuclei_3.1.5_linux_amd64.zip
sudo mv nuclei /usr/local/bin/

# Update templates
nuclei -update-templates
```

**Docker (Alternative):**
```bash
docker pull projectdiscovery/nuclei:latest
docker run --rm projectdiscovery/nuclei:latest -version
```

---

## Usage Examples

### OWASP ZAP - Quick Scan

**Basic Baseline Scan:**
```bash
# Scan a local development site
docker run --rm \
  -v $(pwd):/zap/wrk/:rw \
  zaproxy/zap-stable \
  zap-baseline.py \
  -t http://localhost:3000 \
  -r zap-report.html

# Scan staging site
docker run --rm \
  -v $(pwd):/zap/wrk/:rw \
  zaproxy/zap-stable \
  zap-baseline.py \
  -t https://staging.example.com \
  -r zap-report.html
```

**Full Active Scan:**
```bash
# More thorough scan (takes longer)
docker run --rm \
  -v $(pwd):/zap/wrk/:rw \
  zaproxy/zap-stable \
  zap-full-scan.py \
  -t https://staging.example.com \
  -r zap-full-report.html

# With authentication context
docker run --rm \
  -v $(pwd):/zap/wrk/:rw \
  zaproxy/zap-stable \
  zap-full-scan.py \
  -t https://staging.example.com \
  -c zap-context.xml \
  -r zap-auth-report.html
```

**API Scan:**
```bash
# Scan API with OpenAPI spec
docker run --rm \
  -v $(pwd):/zap/wrk/:rw \
  zaproxy/zap-stable \
  zap-api-scan.py \
  -t https://api.example.com/v1 \
  -f openapi \
  -r zap-api-report.html
```

### Nuclei - Template Scanning

**Basic Vulnerability Scan:**
```bash
# Scan with all templates
nuclei -u https://staging.example.com

# Scan with specific severity
nuclei -u https://staging.example.com -severity critical,high

# Scan with specific tags
nuclei -u https://staging.example.com -tags cve,owasp
```

**CVE Detection:**
```bash
# Scan for latest CVEs
nuclei -u https://staging.example.com -tags cve

# Scan for specific CVE year
nuclei -u https://staging.example.com -tags cve2024

# Generate JSON report
nuclei -u https://staging.example.com -json -o nuclei-report.json
```

**Technology Detection:**
```bash
# Detect technologies and frameworks
nuclei -u https://staging.example.com -tags tech

# Detect exposed panels
nuclei -u https://staging.example.com -tags panel

# Detect misconfigurations
nuclei -u https://staging.example.com -tags misconfiguration
```

**Multiple Targets:**
```bash
# Create targets file
cat > targets.txt <<EOF
https://staging.example.com
https://api.example.com
https://admin.example.com
EOF

# Scan all targets
nuclei -list targets.txt -severity critical,high -o results.txt
```

---

## CI/CD Integration

### GitHub Actions - Weekly DAST Scan

```yaml
name: Weekly DAST Security Scan

on:
  schedule:
    # Run every Sunday at 2 AM
    - cron: '0 2 * * 0'
  workflow_dispatch: # Allow manual trigger

jobs:
  dast-scan:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # Deploy to staging for testing (example)
      - name: Deploy to staging
        run: |
          # Your deployment commands here
          echo "Deploying to staging..."

      # OWASP ZAP Baseline Scan
      - name: OWASP ZAP Baseline Scan
        uses: zaproxy/action-baseline@v0.10.0
        with:
          target: 'https://staging.example.com'
          rules_file_name: '.zap/rules.tsv'
          cmd_options: '-a'

      # Nuclei Scan
      - name: Run Nuclei Scan
        uses: projectdiscovery/nuclei-action@main
        with:
          target: 'https://staging.example.com'
          severity: 'critical,high'

      # Upload results
      - name: Upload ZAP Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: zap-scan-results
          path: report_html.html

      - name: Upload Nuclei Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: nuclei-results
          path: nuclei.log
```

### GitLab CI - Monthly DAST Audit

```yaml
# .gitlab-ci.yml
dast-monthly:
  stage: security
  image: docker:latest
  services:
    - docker:dind

  only:
    - schedules # Configure monthly schedule in GitLab

  script:
    # OWASP ZAP Scan
    - docker run --rm
        -v $(pwd):/zap/wrk/:rw
        zaproxy/zap-stable
        zap-full-scan.py
        -t https://staging.example.com
        -r zap-report.html

    # Nuclei Scan
    - docker run --rm
        -v $(pwd):/output
        projectdiscovery/nuclei:latest
        -u https://staging.example.com
        -severity critical,high
        -json -o /output/nuclei-report.json

  artifacts:
    paths:
      - zap-report.html
      - nuclei-report.json
    expire_in: 30 days
```

### Local Pre-Release Checklist

```bash
#!/bin/bash
# pre-release-dast-check.sh

set -e

STAGING_URL="https://staging.example.com"
REPORT_DIR="security-reports/$(date +%Y-%m-%d)"

mkdir -p "$REPORT_DIR"

echo "Starting DAST Security Audit for Pre-Release..."
echo "Target: $STAGING_URL"
echo "Report Directory: $REPORT_DIR"
echo ""

# 1. OWASP ZAP Baseline Scan
echo "[1/3] Running OWASP ZAP Baseline Scan..."
docker run --rm \
  -v $(pwd)/$REPORT_DIR:/zap/wrk/:rw \
  zaproxy/zap-stable \
  zap-baseline.py \
  -t "$STAGING_URL" \
  -r zap-baseline-report.html

# 2. Nuclei CVE Scan
echo "[2/3] Running Nuclei CVE Scan..."
nuclei -u "$STAGING_URL" \
  -tags cve \
  -severity critical,high \
  -json -o "$REPORT_DIR/nuclei-cve.json"

# 3. Nuclei Misconfiguration Scan
echo "[3/3] Running Nuclei Misconfiguration Scan..."
nuclei -u "$STAGING_URL" \
  -tags misconfiguration,exposure \
  -json -o "$REPORT_DIR/nuclei-config.json"

echo ""
echo "DAST Audit Complete!"
echo "Reports available in: $REPORT_DIR"
echo ""
echo "Review reports before release:"
echo "  - ZAP Report: $REPORT_DIR/zap-baseline-report.html"
echo "  - Nuclei CVE: $REPORT_DIR/nuclei-cve.json"
echo "  - Nuclei Config: $REPORT_DIR/nuclei-config.json"
```

---

## Report Interpretation

### OWASP ZAP Report Severity

| Risk Level | Action Required |
|------------|----------------|
| High | Fix before release |
| Medium | Review and assess risk |
| Low | Address in next sprint |
| Informational | Good to know |

**Common High-Risk Findings:**
- SQL Injection vulnerabilities
- Cross-Site Scripting (XSS)
- Command Injection
- Path Traversal
- Authentication bypass

### Nuclei Report Analysis

**Critical Severity:**
- Active exploitation in the wild
- Fix immediately
- May indicate compromise

**High Severity:**
- Known vulnerabilities with PoC
- Fix before release
- High impact if exploited

**Medium/Low:**
- Misconfigurations
- Information disclosure
- Best practice violations

---

## Best Practices

### DO:
✅ Run DAST on staging environment
✅ Schedule regular scans (weekly/monthly)
✅ Test before major releases
✅ Review all high/critical findings
✅ Combine with SAST results
✅ Keep tools and templates updated

### DON'T:
❌ Run active scans on production
❌ Skip SAST in favor of DAST only
❌ Ignore medium/low findings indefinitely
❌ Run DAST in CI/CD for every commit
❌ Test without proper authorization
❌ Scan third-party sites without permission

---

## Troubleshooting

### OWASP ZAP Issues

**Problem:** Too many false positives
**Solution:** Create ZAP context file, configure authentication, use baseline scan first

**Problem:** Scan takes too long
**Solution:** Use baseline scan instead of full scan, configure scan policy

**Problem:** Docker permission errors
**Solution:** Add `-u $(id -u):$(id -g)` to docker run command

### Nuclei Issues

**Problem:** Templates outdated
**Solution:** Run `nuclei -update-templates` regularly

**Problem:** Rate limiting
**Solution:** Add `-rate-limit 150` flag to slow down requests

**Problem:** SSL certificate errors
**Solution:** Use `-disable-update-check` if running in restricted environments

---

## Additional Resources

**OWASP ZAP:**
- Documentation: https://www.zaproxy.org/docs/
- Docker Images: https://www.zaproxy.org/docs/docker/
- User Guide: https://www.zaproxy.org/getting-started/

**Nuclei:**
- Documentation: https://docs.projectdiscovery.io/tools/nuclei/overview
- Templates: https://github.com/projectdiscovery/nuclei-templates
- Community: https://discord.gg/projectdiscovery

**DAST Best Practices:**
- OWASP Testing Guide: https://owasp.org/www-project-web-security-testing-guide/
- NIST Guide: https://csrc.nist.gov/publications/detail/sp/800-115/final
