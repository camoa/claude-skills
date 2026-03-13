---
description: Run complete code quality and security audit for Drupal/Next.js projects. Use when user says "full audit", "check everything", "code quality report", "run all checks", "audit this project", "pre-merge check", "quality gate". Runs lint + security + SOLID + DRY + coverage, then synthesizes findings into prioritized action plan with cross-tool correlation.
allowed-tools: Read, Bash, Grep, Glob, Write
argument-hint: optional|project-path
---

# Code Quality Audit

Run a comprehensive code quality and security audit on your project.

## Usage

```
/code-quality:audit [project-path]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Runs full audit suite (all 22 operations)
3. Generates reports in `.reports/` directory
4. Displays summary in chat

## Detection & Execution

!cd skills/code-quality-audit && bash scripts/core/detect-project.sh

Based on detection result, executes:
- **Drupal**: `bash scripts/core/full-audit.sh` (via DDEV)
- **Next.js**: `bash scripts/core/full-audit.sh` (via npm/yarn)

## Output

- JSON reports: `.reports/*.json`
- Markdown summary: `.reports/audit-summary.md`
- Chat summary with key findings

## Error Handling

If audit fails, see:
- Error messages with recovery guidance
- Troubleshooting: `references/troubleshooting.md`

## Step 5 — Synthesize Findings

After all tools complete, correlate findings across tools:

1. **Group by location** — Multiple tools flagging the same file/function = hot spot
2. **Cross-category risk** — Security issue + missing tests + SOLID violation = compounding risk
3. **Prioritize** — Rank by compound severity, not individual tool severity
4. **Action plan** — Top 5 fixes that resolve the most findings

Write synthesis to `.reports/audit-synthesis.md`:

```markdown
# Audit Synthesis

## Hot Spots (multiple tools flagged)
| # | File:Line | Tools | Categories | Compound Severity |
|---|-----------|-------|------------|-------------------|

## Cross-Category Risks
| # | Location | Security Issue | Quality Issue | Combined Risk |
|---|----------|---------------|---------------|---------------|

## Prioritized Action Plan
| # | Fix | Resolves Findings | Impact | Effort |
|---|-----|-------------------|--------|--------|
| 1 | {highest compound impact} | {list tool findings resolved} | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |

## Coverage Gaps
Tools that couldn't run or had no findings — may indicate missing config, not clean code.
| Tool | Status | Action Needed |
|------|--------|--------------|

## Summary
- Total findings: {N} across {N} tools
- Hot spots: {N} locations flagged by 2+ tools
- Cross-category risks: {N}
- Top fix resolves: {N} findings
```

## Related Commands

- `/code-quality:review` - Rubric-scored code review (/50 scale)
- `/code-quality:coverage` - Test coverage only
- `/code-quality:security` - Security audit only
- `/code-quality:security-debate` - Debate security findings with 3-agent team
- `/code-quality:architecture-debate` - Debate architecture with 3-agent team
- `/code-quality:lint` - Linting check only
