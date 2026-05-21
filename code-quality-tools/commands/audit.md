---
description: Run complete code quality and security audit for Drupal/Next.js projects. Use when user says "full audit", "check everything", "code quality report", "run all checks", "audit this project", "pre-merge check", "quality gate". Runs lint + security + SOLID + DRY + coverage, then synthesizes findings into prioritized action plan with cross-tool correlation.
allowed-tools: Read, Bash, Grep, Glob, Write
argument-hint: "[--json] [project-path]"
---

# Code Quality Audit

Run a comprehensive code quality and security audit on your project.

> **Reading strategy:** This is **Type B** work (audit / review / architecture analysis) — read full source and config files; do NOT grep-first. Inherited methods, annotations, and config-wired classes are invisible to a grep-first pass. See `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`.

## Usage

```
/code-quality:audit [project-path]           # interactive, writes .reports/*.md + chat summary
/code-quality:audit --json [project-path]    # CI mode — emits a single stable JSON document on stdout
```

## CI Mode (--json)

When invoked with `--json`, emit a single stable JSON document on stdout (schema `v1.0`) and suppress the chat summary. The document envelope:

```json
{
  "schema_version": "1.0",
  "command": "audit",
  "project_type": "drupal|nextjs|unknown",
  "timestamp": "ISO-8601",
  "target": "path",
  "status": "pass|warning|fail",
  "summary": { "overall": "...", "coverage": "...", "solid": "...", "dry": "...", "security": "..." },
  "findings": [ ... ],
  "metrics": { ... }
}
```

Gate a pipeline on overall status:

```bash
result=$(/code-quality:audit --json "$TARGET")
echo "$result" | jq -e '.status != "fail"' >/dev/null || { echo "$result" | jq; exit 1; }
```

Full schema + field definitions: `${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/references/json-schemas.md`.

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Runs full audit suite (all 22 operations)
3. Generates reports in `.reports/` directory
4. Displays summary in chat

## Adaptive Depth

Audit depth scales with the session's effort level — at `low`, run a fast lint pass; at `medium`, lint + coverage + SOLID/DRY; at `high` (the effective default), the full audit; at `xhigh`/`max`, the full audit followed by an offer to run `/code-quality:security-debate`. An unset or unrecognized level falls back to the full audit — depth never silently drops below `high` because the level could not be read. The full ladder lives in the `code-quality-audit` skill's "Adaptive Audit Depth" section. (Pilot, v3.5.0 — wired into the audit flow only.)

## Detection & Execution

Use `${CLAUDE_PLUGIN_ROOT}` (Claude Code exposes this) to reach the scripts regardless of the user's current working directory:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/detect-project.sh"
```

Based on detection result, execute:
- **Drupal**: `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/full-audit.sh"` (via DDEV)
- **Next.js**: same script (routes by detected type)

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

## Schedule this

For recurring sweeps (daily, weekly, hourly security watch), pick a surface based on what the audit needs:

- **Desktop Scheduled Task** (primary) — access to DDEV, composer cache, uncommitted work. See `${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/references/desktop-sweep-template.md`.
- **Cloud Routine** (fallback) — machine-off reliability, GitHub event triggers. See `${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/references/cloud-routine-sweep.md`.
- `/loop` — in-session polling only.

Surface comparison and decision tree: `${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/references/scheduled-sweeps.md`.

## Wire to CI

For CI-triggered pre-merge audits (fire from GitHub Actions / GitLab CI on PR labels or merge-ready signal), use a Cloud Routine with an API trigger. Full `curl` + workflow snippets + bearer-token lifecycle in `${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/references/premerge-gate-routine.md`.

Two complementary gates: run the cheap local `/code-quality:audit --json` on every push; reserve the verified-findings cloud review for release branches via the headless `claude ultrareview --json` subcommand (exit-code contract + gating snippet in `commands/ultrareview.md` → "CI / Headless Mode").

## Autonomous remediation with `/goal`

After an audit produces a findings list, the built-in `/goal` command turns fix-verify-fix into an autonomous loop — Claude keeps working turn after turn until a fresh evaluator model confirms the condition from the transcript:

```
/goal every critical and high finding in .reports/audit-synthesis.md is resolved,
verified by re-running /code-quality:audit --json and confirming zero findings
with severity high or critical — or stop after 15 turns
```

The condition must name a **transcript-checkable end state** — the evaluator does not run tools itself, it reads what Claude surfaced. Pair it with `--json` so the proof is a machine-checkable document, not a prose claim. Bound the loop with an explicit `stop after N turns` clause.

`/goal` requires an accepted workspace-trust dialog and is unavailable when `disableAllHooks` or `allowManagedHooksOnly` is set. It is an interactive / headless-`-p` convenience — **not** a CI gate. For CI, use the non-interactive gates instead: `/code-quality:audit --json` per push and `claude ultrareview --json` on release branches.

## Related Commands

- `/code-quality:review` - Rubric-scored code review (/50 scale)
- `/code-quality:ultrareview` - Cloud multi-agent deep review (pre-merge, paid after free quota)
- `/code-quality:coverage` - Test coverage only
- `/code-quality:security` - Security audit only
- `/code-quality:security-debate` - Debate security findings with 3-agent team
- `/code-quality:architecture-debate` - Debate architecture with 3-agent team
- `/code-quality:lint` - Linting check only
