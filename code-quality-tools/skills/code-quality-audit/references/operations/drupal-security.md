# Drupal Security Audit

Comprehensive security audit for Drupal projects with 10 security layers.

> **Online Dev-Guides:** For Drupal security patterns, OWASP Top 10 mapping, access control, XSS/CSRF/SQLi prevention, and input validation beyond tool scanning, see https://camoa.github.io/dev-guides/drupal/security/ (20 guides covering access system architecture, authentication, entity access control, route access checks, input validation, and more).

## Contents

- [Overview](#overview)
- [Security Layers](#security-layers)
- [Installation](#installation)
- [Usage](#usage)
- [Why Modern Tools](#why-modern-tools)

---

## Overview

When user says "check security", "find vulnerabilities", "security audit", "OWASP check":

Run `scripts/drupal/security-check.sh` which performs a comprehensive 10-layer security audit.

**Security Coverage:** 90% (expanded from 85% in v1.8.0)

---

## Security Layers

The audit performs 10 complementary security checks:

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
- **Status:** ✅ 3.1.8.6 released 2026-08-17; repository not archived (checked 2026-08-28)
- **Installation:** `ddev composer require --dev yousha/php-security-linter:^3.1`

### 4. Psalm Taint Analysis
- **Type:** Dataflow analysis
- **Coverage:** XSS, SQLi detection (OWASP A03:2021)
- **Status:** ✅ Active (recommended but optional)
- **Installation:** `ddev composer require --dev vimeo/psalm:^6.0`

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
- **Command (default, working tree):** `gitleaks dir . --redact --report-format json --report-path <report> --no-banner`
- **Command (history or a commit range):** `gitleaks git . --log-opts="--full-history --text --no-textconv -p -U0 <range|--all>" --redact --report-format json --report-path <report> --no-banner`
- `--redact` masks matched values in the report. Without it the report file holds every discovered secret in plaintext.
- `gitleaks detect --no-git` is the legacy 8.x spelling of `gitleaks dir`: it reads the working tree and nothing else. A credential committed in one release and gitignored in the next is invisible to it. Do not use it.
- `--text --no-textconv` are not optional on a history pass. `gitleaks git` drives `git log -p`, and a `-diff` or `binary` attribute in `.gitattributes` makes git print no content lines, so the pass reads zero bytes and reports a clean history.

#### Choosing the ground the scan covers

The scan says which ground it covered on a `[SCOPE]` line, and records the same values in `security-report.json`. The default is the working tree, because full-history discovery is not affordable on a repository that ever committed `vendor/`: measured at 2,368 commits and 224.84 MiB of history, a full pass ran for many minutes at several hundred percent CPU and was killed at ten.

| Variable | Values | What it does |
|----------|--------|--------------|
| `CQT_SECRET_SCAN` | `tree` (default), `diff`, `history` | The ground. `tree` is the working tree, seconds. `diff` is a bounded commit range, the CI answer. `history` is every commit reachable from every ref, and is the only pass that finds a secret that was committed and later removed. |
| `CQT_SECRET_SCAN_BASE` | a git ref | `diff` mode base. Unset, it is derived from the first resolvable upstream ref; if none resolves the scan is refused and recorded as a skip rather than silently widened. |
| `CQT_SECRET_SCAN_LOG_OPTS` | a string | Passed to `gitleaks --log-opts` for a `history` or `diff` pass. No quote characters: gitleaks word-splits this value before handing it to `git log`, so quoting is lost and a quoted pathspec silently scans nothing. Ranges and unquoted pathspecs work. |
| `CQT_SECRET_SCAN_ALLOWLIST` | `vendored` | Apply the shipped vendored-path allowlist (`templates/gitleaks-vendored-allowlist.toml`) so vendored findings do not drown the report. It suppresses findings, so it is opt-in and the run prints a `[FILTER]` line naming the config whenever one is in force. It does not make a history pass faster: every blob is still read. |
| `CQT_SECRET_SCAN_ALLOWLIST_FILE` | a path | Use this gitleaks config instead of the shipped one. |
| `CQT_SECRET_SCAN_TIMEOUT` | seconds (default `300`) | Budget for any one pass, enforced with `timeout(1)` rather than gitleaks' own `--timeout`, because gitleaks given its own timeout writes a well-formed EMPTY report and exits 1, which a reader cannot tell from a clean tree. On a machine without `timeout(1)` there is no budget and the scope line says so. |

```bash
# CI: scope to what this branch added.
CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE=origin/main bash scripts/drupal/security-check.sh

# Before a release, or when investigating: all of history, with a 30-minute budget.
CQT_SECRET_SCAN=history CQT_SECRET_SCAN_TIMEOUT=1800 \
  CQT_SECRET_SCAN_ALLOWLIST=vendored bash scripts/drupal/security-check.sh
```

### 10. Roave Security Advisories
- **Type:** Composer prevention layer
- **Coverage:** Blocks installation of packages with known vulnerabilities
- **Status:** ✅ Actively maintained
- **Installation:** `ddev composer require --dev roave/security-advisories:dev-master`
- **How it works:** Prevents `composer require` of vulnerable packages at install time
- **Note:** This is a prevention tool, not a scanner - it works during package installation

---

## Installation

### Required Tools
```bash
# PHP Security Linter
ddev composer require --dev yousha/php-security-linter:^3.1
```

### Recommended Tools
```bash
# Psalm (for taint analysis)
ddev composer require --dev vimeo/psalm:^6.0

# Roave Security Advisories (prevents vulnerable package installation)
ddev composer require --dev roave/security-advisories:dev-master

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
# Run all 10 security layers. Run it on the HOST, from the project you are auditing:
# the script is the driver and proxies each tool through `ddev exec` itself. Wrapping it
# in `ddev exec` puts a host path in front of a container that has no such path.
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/security-check.sh"

# View report
cat "$(bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/report-dir.sh" --latest)/security-report.json" | jq .
```

### Report Structure
```json
{
  "meta": {
    "timestamp": "2025-12-19T12:00:00Z",
    "tools": ["drush_pm_security", "composer_audit", "phpcs_security_linter",
              "psalm_taint", "custom_patterns", "security_review",
              "semgrep", "trivy", "gitleaks", "roave"]
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

### ❌ Tools This Skill Does Not Install

Neither of these is a judgement about how the project is run. Each is a fact you can
check, which is the reason the wording is what it is: `abandoned` is a Composer field,
Packagist has no `deprecated` flag, and in PHP `deprecated` marks a symbol rather than a
package. Both facts below were read on 2026-08-28.

**pheromone/phpcs-security-audit**
- Latest release 2.0.1, 2019-08-05 — seven years, no release since
- Not marked abandoned on Packagist (checked 2026-08-28); the age is the fact, not a flag
- Declares `php >=5.4` and its sniffs predate PHP 8
- **Replacement:** `yousha/php-security-linter`, 3.1.8.6 released 2026-08-17

**mglaman/drupal-check**
- Latest release 1.5.0, 2024-08-14
- Not marked abandoned on Packagist and not archived on GitHub (checked 2026-08-28)
- The blocker is its constraint, not its health: 1.5.0 declares
  `mglaman/phpstan-drupal ^1.0.0` and no direct `phpstan/phpstan`. PHPStan 1.x arrives
  transitively through phpstan-drupal 1.x, which requires `phpstan/phpstan ^1.12`. This
  skill installs the PHPStan 2.x stack, so the two cannot resolve in one project
- **Replacement:** `phpstan/phpstan-deprecation-rules` with `mglaman/phpstan-drupal` 2.x

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
