---
description: Run comprehensive security audit for Drupal/Next.js projects
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# Security Audit

Run a comprehensive security scan across multiple layers.

## Usage

```
/code-quality:security [project-path]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Runs multi-layer security scan
3. Reports vulnerabilities by severity (critical, high, medium, low)
4. Provides remediation guidance

## Security Layers

**Drupal (10 layers):**
- Semgrep (OWASP Top 10, Drupal-specific rules)
- Trivy (dependency scanning)
- Gitleaks (secrets detection)
- Security Review module
- Drush security advisories
- Composer audit
- Roave Security Advisories
- PHPStan security rules
- Psalm taint analysis
- PHPMD security rules

**Next.js (7 layers):**
- Semgrep (OWASP Top 10, React/Next.js rules)
- Trivy (dependency scanning)
- Gitleaks (secrets detection)
- npm audit
- Socket CLI (supply chain analysis)
- ESLint security plugins
- madge (circular dependencies)

## Detection & Execution

!cd skills/code-quality-audit && bash scripts/core/detect-project.sh

Based on detection result, executes:
- **Drupal**: `bash scripts/drupal/security-check.sh`
- **Next.js**: `bash scripts/nextjs/security-check.sh`

## Output

- JSON report: `.reports/security-report.json`
- Markdown summary: `.reports/security-summary.md`
- Grouped by severity (critical → low)

## Severity Thresholds

Default: Fails on medium+ severity

To customize, create `.code-quality.json`:
```json
{
  "thresholds": {
    "security_severity": "high"
  }
}
```

## Error Handling

Common issues:
- **"Security tool not found"**: Run `/code-quality:setup`
- **"Too many findings"**: Review `.reports/security.json` for details

See: `references/troubleshooting.md#security-scan-issues`

## Related Commands

- `/code-quality:audit` - Full audit (includes security)
- `/code-quality:setup` - Install security tools
- `/code-quality:security-debate` - Multi-perspective debate analysis of security findings (requires agent teams)
