---
description: Run comprehensive security audit for Drupal/Next.js projects. Use when user says "security audit", "check vulnerabilities", "OWASP check", "is this secure", "find security issues", "Semgrep scan", "Trivy scan", "Gitleaks check". Runs 10 Drupal layers or 7 Next.js layers. For multi-perspective analysis, use /code-quality:security-debate after this.
allowed-tools: Read, Bash, Grep, Glob
argument-hint: "[--json] [project-path]"
---

# Security Audit

Run a comprehensive security scan across multiple layers.

> **Reading strategy:** This is **Type B** work — read full source and config files; do NOT grep-first. Security audits especially must follow inheritance, decorators, and config-wired hooks. See `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`.

## Usage

```
/code-quality:security [project-path]           # writes .reports/security-*.md + chat summary
/code-quality:security --json [project-path]    # CI mode — single stable JSON on stdout
```

## CI Mode (--json)

When invoked with `--json`, emit schema `v1.0` JSON on stdout. Each finding includes `layer`, `rule_id`, `severity`, optional `owasp` / `cwe`, file:line, message, fix, and `confidence`. `summary` aggregates counts per severity and lists layers that ran vs. were skipped.

Gate on `.summary.critical` + `.summary.high`:

```bash
result=$(/code-quality:security --json)
CRIT=$(echo "$result" | jq '.summary.critical')
HIGH=$(echo "$result" | jq '.summary.high')
if [ "$CRIT" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
  echo "$result" | jq '.findings[] | select(.severity == "critical" or .severity == "high")'
  exit 1
fi
```

Schema: `skills/code-quality-audit/references/json-schemas.md`.

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

Use `${CLAUDE_PLUGIN_ROOT}` to reach the scripts regardless of cwd:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/detect-project.sh"
```

Based on detection result, execute:
- **Drupal**: `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/security-check.sh"`
- **Next.js**: `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/security-check.sh"`

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
