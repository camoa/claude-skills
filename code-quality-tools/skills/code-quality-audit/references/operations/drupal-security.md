# Drupal Security Audit

Comprehensive security audit for Drupal projects with 9 security layers.

## Contents

- [Overview](#overview)
- [Security Layers](#security-layers)
- [Installation](#installation)
- [Usage](#usage)
- [Why Modern Tools](#why-modern-tools)

---

## Overview

When user says "check security", "find vulnerabilities", "security audit", "OWASP check":

Run `scripts/drupal/security-check.sh` which performs a comprehensive 9-layer security audit.

**Security Coverage:** 85% (expanded from 40% in v1.7.0)

---

## Security Layers

The audit performs 9 complementary security checks:

### 1. Drush pm:security
- **Type:** Drupal-specific advisory check
- **Coverage:** Known Drupal vulnerabilities (OWASP A06:2021)
- **Status:** Built-in, no installation needed

### 2. Composer audit
- **Type:** PHP package vulnerability scanner
- **Coverage:** Composer dependencies (OWASP A06:2021)
- **Status:** Built-in (Composer 2.4+)

### 3. yousha/php-security-linter
- **Type:** PHPCS security rules
- **Coverage:** OWASP Top 10 + CIS benchmarks
- **Status:** ✅ Actively maintained (Dec 2025)
- **Installation:** `ddev composer require --dev yousha/php-security-linter`

### 4. Psalm Taint Analysis
- **Type:** Dataflow analysis
- **Coverage:** XSS, SQLi detection (OWASP A03:2021)
- **Status:** ✅ Active (recommended but optional)
- **Installation:** `ddev composer require --dev vimeo/psalm`

### 5. Custom Drupal Patterns
- **Type:** Regex-based detection
- **Patterns:**
  - SQL Injection: Unsafe `db_query()` with variable concatenation
  - XSS: Twig `|raw` filter usage
  - Insecure Deserialization: `unserialize()` on user input
  - Command Injection: `exec()`, `shell_exec()` patterns

### 6. drupal/security_review (Optional)
- **Type:** Drupal configuration audit
- **Coverage:** Misconfiguration detection (OWASP A05:2021)
- **Status:** ✅ Actively maintained
- **Installation:**
  ```bash
  ddev composer require drupal/security_review
  ddev drush pm:enable security_review
  ```

### 7. Semgrep SAST
- **Type:** Multi-language static analysis
- **Coverage:** 20,000+ security rules for PHP, JS, TS
- **Status:** ✅ Actively maintained
- **Installation:** `ddev exec pip3 install semgrep`
- **Command:** `semgrep scan --config=auto`

### 8. Trivy Scanner
- **Type:** Dependency/container/secret scanner
- **Coverage:**
  - Package vulnerabilities (npm + Composer)
  - Secret detection (API keys, tokens)
  - Container/IaC misconfigurations
- **Status:** ✅ Actively maintained
- **Installation:** See `scripts/core/install-tools.sh`
- **Command:** `trivy fs --scanners vuln,secret`

### 9. Gitleaks
- **Type:** Secret detection
- **Coverage:** 800+ patterns, entropy analysis
- **Status:** ✅ Actively maintained
- **Installation:** See `scripts/core/install-tools.sh`
- **Command:** `gitleaks detect --no-git`

---

## Installation

### Required Tools
```bash
# PHP Security Linter
ddev composer require --dev yousha/php-security-linter
```

### Recommended Tools
```bash
# Psalm (for taint analysis)
ddev composer require --dev vimeo/psalm

# Cross-stack security tools (install via install-tools.sh)
# Or manually:
ddev exec pip3 install semgrep
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
curl -sfL https://raw.githubusercontent.com/gitleaks/gitleaks/master/scripts/install.sh | sh -s -- -b /usr/local/bin
```

### Optional Tools
```bash
# Security Review module
ddev composer require drupal/security_review
ddev drush pm:enable security_review
```

---

## Usage

### Full Security Audit
```bash
# Run all 9 security layers
ddev exec bash skills/code-quality-audit/scripts/drupal/security-check.sh

# View report
cat .reports/security-report.json | jq .
```

### Report Structure
```json
{
  "meta": {
    "timestamp": "2025-12-19T12:00:00Z",
    "tools": ["drush_pm_security", "composer_audit", "phpcs_security_linter",
              "psalm_taint", "custom_patterns", "security_review",
              "semgrep", "trivy", "gitleaks"]
  },
  "summary": {
    "critical": 0,
    "high": 2,
    "medium": 5,
    "low": 10,
    "security_score": "warning"
  },
  "issues": [
    {
      "category": "Semgrep SAST",
      "severity": "high",
      "file": "web/modules/custom/mymodule/src/Controller/MyController.php",
      "line": 42,
      "message": "SQL injection vulnerability detected",
      "owasp": "A03:2021",
      "remediation": "Use parameterized queries"
    }
  ]
}
```

### Thresholds

| Severity | Pass | Warning | Fail |
|----------|------|---------|------|
| Critical | 0 | 0 | >0 |
| High | 0 | 1-3 | >3 |
| Medium | 0 | 1-10 | >10 |
| Low | 0 | any | >20 |

---

## Why Modern Tools

### ❌ Abandoned Tools (DO NOT USE)

**pheromone/phpcs-security-audit**
- Last updated: March 2020 (abandoned)
- No PHP 8.x support
- Security rules outdated
- **Replacement:** yousha/php-security-linter

**drupal-check**
- Last updated: 2023 (abandoned)
- No longer maintained
- Superseded by PHPStan + Drupal extension

### ✅ Why These Tools?

**Semgrep**
- Actively maintained by Semgrep Inc
- 20,000+ security rules
- Multi-language support (PHP, JS, TS, React)
- Auto-updating rule sets

**Trivy**
- Most comprehensive scanner
- Scans npm, Composer, containers, IaC
- Secret detection with 800+ patterns
- Fast and accurate

**Gitleaks**
- Specialized secret detection
- Entropy analysis for custom secrets
- No git required (`--no-git` flag)
- Low false positive rate

---

## OWASP 2021 Coverage

| OWASP Category | Tools |
|----------------|-------|
| A01:2021 Broken Access Control | Security Review, Custom patterns |
| A02:2021 Cryptographic Failures | Gitleaks, Trivy secrets |
| A03:2021 Injection | Psalm taint, Semgrep, Custom patterns |
| A04:2021 Insecure Design | Semgrep, PHPMD |
| A05:2021 Security Misconfiguration | Security Review, Trivy |
| A06:2021 Vulnerable Components | Drush, Composer audit, Trivy |
| A07:2021 Authentication Failures | Security Review, Semgrep |
| A08:2021 Software/Data Integrity | Semgrep, Custom patterns |
| A09:2021 Security Logging Failures | Security Review |
| A10:2021 SSRF | Semgrep, Custom patterns |
