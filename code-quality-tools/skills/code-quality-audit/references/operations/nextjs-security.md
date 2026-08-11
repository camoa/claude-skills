# Next.js Security Audit

Comprehensive security audit for Next.js projects with 7 security layers (NEW in v1.8.0, Socket added in v2.0.0).

## Contents

- [Overview](#overview)
- [Security Layers](#security-layers)
- [Installation](#installation)
- [Usage](#usage)

---

## Overview

When user says "check security", "find vulnerabilities", "security audit", "OWASP check" in a Next.js project:

Run `scripts/nextjs/security-check.sh` which performs a comprehensive 7-layer security audit.

**Security Coverage:** 85% (Socket added in v2.0.0)

---

## Security Layers

The audit performs 7 complementary security checks:

### 1. npm audit
- **Type:** Package vulnerability scanner
- **Coverage:** npm dependencies (OWASP A06:2021)
- **Status:** Built-in (npm 6+)
- **Command:** `npm audit --json`

### 2. ESLint Security Plugins
- **Type:** Security linting
- **Coverage:** Common JavaScript vulnerabilities
- **Plugins:**
  - `eslint-plugin-security` - Security-focused ESLint rules
  - `eslint-plugin-no-secrets` - Secret detection in code
- **Installation:** `npm install -D eslint-plugin-security eslint-plugin-no-secrets`

### 3. Semgrep SAST
- **Type:** Multi-language static analysis
- **Coverage:** 20,000+ security rules for React, JS, TS
- **Status:** ✅ Actively maintained
- **Command:** `semgrep scan --config=auto`
- **Focuses on:**
  - React XSS patterns
  - SQL injection in API routes
  - Insecure data handling
  - SSRF vulnerabilities

### 4. Trivy Scanner
- **Type:** Dependency/container/secret scanner
- **Coverage:**
  - npm package vulnerabilities
  - Secret detection (API keys, tokens)
  - Container/IaC misconfigurations
- **Status:** ✅ Actively maintained
- **Command:** `trivy fs --scanners vuln,secret`

### 5. Gitleaks
- **Type:** Secret detection
- **Coverage:** 800+ patterns, entropy analysis
- **Status:** ✅ Actively maintained
- **Command (default, working tree):** `gitleaks dir . --redact --report-format json --report-path <report> --no-banner`
- **Command (history or a commit range):** `gitleaks git . --log-opts="--full-history --text --no-textconv -p -U0 <range|--all>" --redact --report-format json --report-path <report> --no-banner`
- `--redact` masks matched values in the report. Without it the report file holds every discovered secret in plaintext.
- `gitleaks detect --no-git` is the legacy 8.x spelling of `gitleaks dir`: it reads the working tree and nothing else. A credential committed in one release and gitignored in the next is invisible to it. Do not use it.
- `--text --no-textconv` are not optional on a history pass. `gitleaks git` drives `git log -p`, and a `-diff` or `binary` attribute in `.gitattributes` makes git print no content lines, so the pass reads zero bytes and reports a clean history.

#### Choosing the ground the scan covers

The scan says which ground it covered on a `[SCOPE]` line, and records the same values in `security-report.json`. The default is the working tree, because full-history discovery is not affordable on a large repository: measured at 2,368 commits and 224.84 MiB of history, a full pass ran for many minutes at several hundred percent CPU and was killed at ten.

| Variable | Values | What it does |
|----------|--------|--------------|
| `CQT_SECRET_SCAN` | `tree` (default), `diff`, `history` | The ground. `tree` is the working tree, seconds. `diff` is a bounded commit range, the CI answer. `history` is every commit reachable from every ref, and is the only pass that finds a secret that was committed and later removed. |
| `CQT_SECRET_SCAN_BASE` | a git ref | `diff` mode base. Unset, it is derived from the first resolvable upstream ref; if none resolves the scan is refused and recorded as a skip rather than silently widened. |
| `CQT_SECRET_SCAN_LOG_OPTS` | a string | Passed to `gitleaks --log-opts` for a `history` or `diff` pass. No quote characters: gitleaks word-splits this value before handing it to `git log`, so quoting is lost and a quoted pathspec silently scans nothing. Ranges and unquoted pathspecs work. |
| `CQT_SECRET_SCAN_ALLOWLIST` | `vendored` | Apply the shipped vendored-path allowlist (`templates/gitleaks-vendored-allowlist.toml`) so findings under `node_modules/` and friends do not drown the report. It suppresses findings, so it is opt-in and the run prints a `[FILTER]` line naming the config whenever one is in force. It does not make a history pass faster: every blob is still read. |
| `CQT_SECRET_SCAN_ALLOWLIST_FILE` | a path | Use this gitleaks config instead of the shipped one. |
| `CQT_SECRET_SCAN_TIMEOUT` | seconds (default `300`) | Budget for any one pass, enforced with `timeout(1)` rather than gitleaks' own `--timeout`, because gitleaks given its own timeout writes a well-formed EMPTY report and exits 1, which a reader cannot tell from a clean tree. On a machine without `timeout(1)` there is no budget and the scope line says so. |

```bash
# CI: scope to what this branch added.
CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE=origin/main bash scripts/nextjs/security-check.sh

# Before a release, or when investigating: all of history, with a 30-minute budget.
CQT_SECRET_SCAN=history CQT_SECRET_SCAN_TIMEOUT=1800 \
  CQT_SECRET_SCAN_ALLOWLIST=vendored bash scripts/nextjs/security-check.sh
```

### 6. Custom React/Next.js Patterns
- **Type:** Regex-based detection
- **Patterns:**
  - **XSS Risk:** `dangerouslySetInnerHTML` usage
  - **Code Injection:** `eval()` usage
  - **XSS via Navigation:** `window.location.href` assignments with user input

### 7. Socket CLI
- **Type:** Supply chain attack detection
- **Coverage:** Detects malicious packages, typosquatting, install scripts
- **Status:** ✅ Actively maintained
- **Installation:** `npm install -D @socketsecurity/cli`
- **Command:** `npx socket-npm audit`
- **Focus Areas:**
  - Suspicious install scripts
  - Network access in dependencies
  - Filesystem access patterns
  - Hidden code obfuscation

---

## Installation

### Required Tools
```bash
# ESLint security plugins
npm install -D eslint-plugin-security eslint-plugin-no-secrets
```

### Recommended Tools
```bash
# Socket CLI (supply chain security)
npm install -D @socketsecurity/cli

# Semgrep
pip3 install semgrep

# Trivy
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Gitleaks
curl -sfL https://raw.githubusercontent.com/gitleaks/gitleaks/master/scripts/install.sh | sh -s -- -b /usr/local/bin
```

Or use `scripts/core/install-tools.sh` which installs all tools automatically.

---

## Usage

### Full Security Audit
```bash
# Run all 7 security layers
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/security-check.sh"

# View report
cat "$(bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/report-dir.sh" --latest)/security-report.json" | jq .
```

### Report Structure
```json
{
  "meta": {
    "timestamp": "2025-12-19T12:00:00Z",
    "project_type": "nextjs",
    "tools": ["npm_audit", "eslint_security", "semgrep", "trivy", "gitleaks", "custom_patterns", "socket"]
  },
  "summary": {
    "critical": 0,
    "high": 1,
    "medium": 3,
    "low": 5,
    "security_score": "warning"
  },
  "issues": [
    {
      "category": "Semgrep SAST",
      "severity": "high",
      "file": "src/app/api/users/route.ts",
      "line": 15,
      "message": "Potential SQL injection in database query",
      "owasp": "A03:2021",
      "remediation": "Use parameterized queries or ORM methods"
    },
    {
      "category": "Custom React Patterns",
      "severity": "medium",
      "file": "src/components/Content.tsx",
      "line": 42,
      "message": "dangerouslySetInnerHTML detected - XSS risk",
      "owasp": "A03:2021",
      "remediation": "Sanitize HTML with DOMPurify or avoid dangerouslySetInnerHTML"
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

## ESLint Security Configuration

Add to `.eslintrc.json` or `eslint.config.js`:

```javascript
// ESLint v9+ flat config
import security from 'eslint-plugin-security';
import noSecrets from 'eslint-plugin-no-secrets';

export default [
  {
    plugins: {
      security,
      'no-secrets': noSecrets
    },
    rules: {
      'security/detect-object-injection': 'warn',
      'security/detect-non-literal-regexp': 'warn',
      'security/detect-unsafe-regex': 'error',
      'security/detect-buffer-noassert': 'error',
      'security/detect-eval-with-expression': 'error',
      'security/detect-no-csrf-before-method-override': 'error',
      'security/detect-possible-timing-attacks': 'warn',
      'no-secrets/no-secrets': 'error'
    }
  }
];
```

---

## OWASP 2021 Coverage

| OWASP Category | Tools |
|----------------|-------|
| A01:2021 Broken Access Control | ESLint security, Semgrep |
| A02:2021 Cryptographic Failures | Gitleaks, Trivy secrets |
| A03:2021 Injection | Semgrep, Custom patterns |
| A04:2021 Insecure Design | Semgrep |
| A05:2021 Security Misconfiguration | Trivy, npm audit |
| A06:2021 Vulnerable Components | npm audit, Trivy |
| A07:2021 Authentication Failures | Semgrep |
| A08:2021 Software/Data Integrity | Semgrep |
| A09:2021 Security Logging Failures | Custom patterns |
| A10:2021 SSRF | Semgrep |

---

## Common Issues Detected

### dangerouslySetInnerHTML XSS
```tsx
// ❌ Dangerous
<div dangerouslySetInnerHTML={{ __html: userContent }} />

// ✅ Safe
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(userContent) }} />
```

### eval() Usage
```javascript
// ❌ Never use eval with user input
eval(userInput);

// ✅ Use safe alternatives
const result = JSON.parse(userInput);
```

### Window Navigation XSS
```javascript
// ❌ Dangerous
window.location.href = userInput;

// ✅ Safe - validate first
const url = new URL(userInput, window.location.origin);
if (url.origin === window.location.origin) {
  window.location.href = url.href;
}
```
