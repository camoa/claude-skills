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

## Change-Scoped Mode (`--changed`) — SAST-only

Pass a newline-delimited file of changed paths to run a **SAST-only** scan scoped to those files:

```bash
bash scripts/drupal/security-check.sh --changed .changed-files.txt
```

**What runs:** `semgrep` + `php-security-linter` + custom grep patterns (on changed files). If `composer.json` or `composer.lock` is in the changed list, `composer audit` also runs.

**What is skipped** (whole-project layers — not file-scopable):
- `drush pm:security` — Drupal security advisories
- `Psalm taint` analysis
- `Trivy` dependency/secret scanner
- `Security Review` module
- `Gitleaks` secret detection
- `Roave Security Advisories` check

A `messages[]` entry in the report records this skip with instructions to run the full scan for complete advisory coverage.

**Empty relevant set:** if no PHP/Twig/JS files match after filtering, exits `0` with status `skipped` (no whole-tree scan).

**Report differences:** `meta.scan_type` is `security_audit_changed`; `meta.tools_run` and `meta.tools_skipped` list the active/skipped tools; `messages[]` records the advisory-layer skip note.

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

## Run in the background

To run a security scan without blocking your session, dispatch it as a background session: `claude --bg "/code-quality:security"`. It keeps running with no terminal attached — monitor it with `claude agents` and pull results with `claude logs <id>`.

## Error Handling

Common issues:
- **"Security tool not found"**: Run `/code-quality:setup`
- **"Too many findings"**: Review `.reports/security.json` for details

See: `references/troubleshooting.md#security-scan-issues`

## How This Fits — Security Layering (defense in depth)

`/code-quality:security` is the **whole-codebase / CI SAST** layer — a multi-tool scan (Semgrep, Trivy, Gitleaks, Psalm taint, Drush/Composer advisories, Roave, Socket) across the entire tree, framework-aware for Drupal/Next.js. It is one layer in Claude Code's defense-in-depth model; the earlier layers are **native** and complementary:

| Stage | Tool | Covers |
|---|---|---|
| In session — Claude's own edits | **security-guidance** plugin (auto, no command) | Common vulns in code Claude writes, fixed the same session. `/code-quality:setup` offers to install it. |
| On demand — diff | native `/security-review` | One generic, diff-scoped vuln pass on the current branch |
| On the PR | **Code Review** / `/code-review ultra` | Multi-agent correctness + security with full-codebase context; tune via `/code-quality:generate-review-md` |
| Whole-codebase / CI | **`/code-quality:security`** (this command) + the debates | Framework-aware multi-tool SAST + OWASP debate native review does not perform |

The native diff-scoped layers reduce what reaches this scan — they do **not** replace it. `/security-review` is generic and diff-only; it cannot do whole-repo Drupal/Next.js SAST, taint analysis, dependency CVEs, or multi-agent OWASP debate. Run `/code-quality:security` for the whole-tree, framework-specific coverage.

## Related Commands

- `/code-quality:audit` - Full audit (includes security)
- `/code-quality:setup` - Install security tools (also offers the in-session **security-guidance** plugin)
- `/code-quality:security-debate` - Multi-perspective debate analysis of security findings (requires agent teams)
- `/code-quality:generate-review-md` - Configure the PR-stage managed Code Review (`REVIEW.md`)
- native `/security-review` - on-demand generic diff-scoped vuln pass (complements, does not replace, this whole-codebase scan)
