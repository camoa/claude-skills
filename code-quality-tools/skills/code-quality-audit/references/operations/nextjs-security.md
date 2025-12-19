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
- **Command:** `gitleaks detect --no-git`

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
bash skills/code-quality-audit/scripts/nextjs/security-check.sh

# View report
cat .reports/security-report.json | jq .
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
