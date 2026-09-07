---
description: Debate security audit findings with three competing subagents (Defender + Red Team + Compliance) across two rounds. Use when user says "debate security", "security from 3 perspectives", "is this vulnerability real", "security team review", "red team this", "challenge security findings", "false positive check". Best for 10+ findings where severity needs validation. Each agent runs in isolated worktree.
allowed-tools: Read, Write, Glob, Grep, WebSearch, WebFetch, Bash
argument-hint: optional|project-path
---

# Security Debate

Analyze security audit results from 3 competing perspectives. A Defender validates findings, a Red Team Attacker finds gaps, and a Compliance Checker maps to standards. A second round has each of them dispute the other two, and the synthesis reports where they disagreed and where all three agreed.

## Usage

```
/code-quality-tools:security-debate [project-path]
```

## What This Does

Dispatches 3 competing subagents that debate the results of a prior security audit, in two rounds: independent analysis, then a cross-challenge in which each reads and disputes the other two. Each writes to its own file. The lead synthesizes a final `security-debate.md` in the audit's report directory, with debated severity ratings, attack scenarios, false positives, and OWASP coverage.

## Instructions

When this command is invoked with `$ARGUMENTS`:

### Step 0 — Resolve the report directory

Reports do not live in the audited repository. Ask the suite where the last `/code-quality-tools:security` run wrote, rather than guessing a path — from the project root, or `$ARGUMENTS` if a path was given:

```bash
REPORT_DIR="$(bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/report-dir.sh" --latest)" \
  && REPORT_DIR="$(cd "$REPORT_DIR" && pwd)" && echo "$REPORT_DIR"
```

Use that value as `{report_dir}` everywhere below, including in the spawn prompts. It must be **absolute**: the analysts run in isolated worktrees, so a relative path would give each its own private directory, and neither the challenge round nor the lead would find anything to read. The `cd`/`pwd` above is what guarantees that.

A non-zero exit means no audit has ever been run here — not that one came back clean:

> No security report found: no audit has been run in this project yet.
> Run `/code-quality-tools:security` first to generate the audit report.

Stop here on a non-zero exit.

### Step 1 — Check Report Exists

Look for `{report_dir}/security-report.json`.

If not found:
> No security report found at `{report_dir}/security-report.json`.
> Run `/code-quality-tools:security` first to generate the audit report.

Stop here if not found.

### Step 2 — Check Prerequisites

Nothing beyond the report itself. This command dispatches ordinary subagents with the Agent
tool, which is always available; it needs no agent team, no experimental flag and no Task
tools.

If the Agent tool is unavailable in this session:

> Subagents are not available in this environment.
>
> **Fallback:** Your security audit results are in `{report_dir}/security-report.json`. Run `/code-quality-tools:security` for standard single-pass analysis.

Stop here if not available.

### Step 3 — Assess Report Size

Read `{report_dir}/security-report.json` and count findings.

If fewer than 10 findings:
> Found {N} findings. For small reports, single-agent analysis may be sufficient.
> Continue with the debate? (It adds most value with 10+ findings.)

Continue if user confirms or if 10+ findings.

### Step 3b — Enrich with Online Dev-Guides (Drupal only)

If the project is Drupal, WebFetch relevant security guides to provide richer context for the debate team:

1. **Always fetch:** `https://camoa.github.io/dev-guides/drupal/security/owasp-top-10-in-drupal/index.md` — OWASP mapping to Drupal
2. **If findings include XSS:** `https://camoa.github.io/dev-guides/drupal/security/xss-prevention/index.md`
3. **If findings include SQLi:** `https://camoa.github.io/dev-guides/drupal/security/sql-injection-prevention/index.md`
4. **If findings include access control:** `https://camoa.github.io/dev-guides/drupal/security/entity-access-control/index.md`
5. **If findings include CSRF:** `https://camoa.github.io/dev-guides/drupal/security/csrf-protection/index.md`
6. **If findings include input validation:** `https://camoa.github.io/dev-guides/drupal/security/input-validation-and-sanitization/index.md`

Save fetched content to `{report_dir}/security-context.md` and include its path in the dispatch prompts so the analysts can reference it.

### Step 4 — Plan the two rounds

The debate runs in two rounds, and **you sequence them** — dispatch round 2 only after all
three of round 1 have written their files. Nothing in the harness enforces this ordering.
The shared task list that once did requires the Task tools, which current models exclude by
default (v2.1.233+), so the order is yours to keep.

| Round | Work | Who | Reads |
|---|---|---|---|
| 1 | Validate findings — identify false positives, assess exploitability | Defender | the report |
| 1 | Construct attack scenarios — chain findings, find gaps the audit missed | Red Team Attacker | the report |
| 1 | Map findings to OWASP Top 10 / CWE, identify coverage gaps | Compliance Checker | the report |
| 2 | Cross-challenge — dispute severity, exploitability and priorities | all three, in parallel | their own round-1 file plus the other two |
| 3 | Synthesize the challenged assessment | you | all six files |

**Quality Gate:** Each agent must address ALL findings in the report. If an agent skips findings (e.g., Defender only validates 5 of 20 findings), note that in the synthesis and name which findings were not reviewed.

### Step 5 — Round 1: dispatch the three analysts

Dispatch all three in **one message**, so they run concurrently. Each is an ordinary
subagent: call the Agent tool with the prompt template below, `model: sonnet`, and
`isolation: "worktree"`. Do **not** pass `name` — a `name` makes the agent a teammate, which
needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and buys nothing here, because every analyst
delivers by writing a file rather than by replying.

After dispatching:

1. Tell the user: "Three analysts are working — I'll run the challenge round when they finish."
2. Do NOT analyze anything yourself. Wait for all three.
3. Confirm each file exists before continuing. An agent that returns prose but writes no file has delivered nothing, and reads exactly like one that found nothing.

**Model & monitoring.** Each prompt below pins `**Model:** sonnet`; naming the model per dispatch is how it is set. There is no global default setting — `teammateDefaultModel` was removed in Claude Code v2.1.234 and a leftover value is ignored. To force one model across every subagent, set `CLAUDE_CODE_SUBAGENT_MODEL` with `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (v2.1.257+); the second is a boolean that promotes the first above the per-dispatch value, which otherwise wins. Watch progress with `/tasks`. Do **not** run the whole debate as a background session (`claude --bg`): the analysts already run in worktree isolation, so that is a worktree-of-worktrees plus permission-auto-deny scenario that is untested.

### Step 5b — Round 2: the cross-challenge

This is the round that makes it a debate rather than three reports side by side. Dispatch all three again in one message, same models and isolation, each with this prompt:

```
You are the {role} in a security audit debate. Round 1 is finished.

YOUR OWN ROUND-1 ANALYSIS:
  {report_dir}/{your-file}.md

THE OTHER TWO ANALYSES:
  {report_dir}/{other-file-1}.md
  {report_dir}/{other-file-2}.md

YOUR MISSION:
Read all three. Then dispute them.

1. Where do you DISAGREE with the other two, and on what evidence? Name the finding.
2. Where has one of them changed your own round-1 position? Say which, and why.
3. Which severities are wrong, in either direction — overstated or understated?
4. Where do all three of you agree? Agreement across three lenses is either a real
   consensus or a shared blind spot. Say which you think it is, and why.

Disagreement is the product here. If you find nothing to dispute, say so explicitly and
explain why the other two were right. Do not manufacture a dispute, and do not stay quiet
to avoid one.

WRITE to: {report_dir}/{your-role}-challenge.md

Format:
# {Role} Challenge

## Disputed — severity or exploitability
| Finding | Their position | My position | Evidence |

## Positions I changed
## Unanimous — consensus or blind spot?
## Summary
```

Wait for all three challenge files before synthesizing.

### Step 6 — Synthesize

When all six files exist:

- Read the three round-1 analyses: `{report_dir}/defender-analysis.md`, `{report_dir}/red-team-analysis.md`, `{report_dir}/compliance-analysis.md`
- Read the three round-2 challenges: `{report_dir}/defender-challenge.md`, `{report_dir}/red-team-challenge.md`, `{report_dir}/compliance-challenge.md`
- Write `{report_dir}/security-debate.md` using the Output Format below. The Debate Log section is drawn from round 2 — where they disagreed, who moved position, and what all three agreed on.
- A missing challenge file is reported, never silently skipped: say which lens did not challenge, so a reader knows the assessment rests on two perspectives rather than three.
- Tell the user: "Security debate complete. Assessment saved to `{report_dir}/security-debate.md`"

---

## Spawn Prompts

### Analyst 1: Defender

**Model:** sonnet
**MaxTurns:** 10
**Isolation:** worktree
**Tools:** Read, Glob, Grep
**Effort:** high

```
You are the Defender for a security audit debate team.

REPORT LOCATION:
{report_dir}/security-report.json

DRUPAL SECURITY CONTEXT (if available):
{report_dir}/security-context.md

YOUR MISSION:
Validate each audit finding and identify false positives. Your lens: "Is this finding actually exploitable in context?"

For each finding:
1. Assess reachability — is user input actually connected to the vulnerable code path?
2. Check context — does the framework (Drupal/Next.js) already mitigate this?
3. Prioritize Psalm taint analysis findings over pattern-matching results
4. Classify each as: Confirmed (exploitable), Likely (plausible), Unlikely (false positive), False Positive

WRITE your analysis to:
  {report_dir}/defender-analysis.md

Use this format:

# Defender Analysis

## Methodology
{How you assessed each finding}

## Finding Validation
| # | Finding | Tool | Original Severity | Reachable? | Framework Mitigated? | Classification | Reasoning |
|---|---------|------|-------------------|------------|---------------------|----------------|-----------|

## False Positives Identified
| # | Finding | Reason | Confidence |
|---|---------|--------|------------|

## Confirmed Threats
| # | Finding | Severity | Attack Vector | Impact |
|---|---------|----------|---------------|--------|

## Summary
- Total findings reviewed: {N}
- Confirmed: {N}
- Likely: {N}
- Unlikely: {N}
- False Positive: {N}

WHEN DONE:
When the file is written, you are done. Do not message anyone — the lead reads your
file and dispatches the challenge round; there is no channel between you and the other two.
Mark your task as completed.
```

### Analyst 2: Red Team Attacker

**Model:** sonnet
**MaxTurns:** 10
**Isolation:** worktree
**Tools:** Read, Glob, Grep, WebSearch
**Effort:** high

```
You are the Red Team Attacker for a security audit debate team.

REPORT LOCATION:
{report_dir}/security-report.json

DRUPAL SECURITY CONTEXT (if available):
{report_dir}/security-context.md

YOUR MISSION:
Construct attack scenarios and find what the audit missed. Your lens: "What attack chains exist and what's missing?"

1. Chain related findings into attack scenarios (e.g., SSRF + file upload = RCE)
2. Search for exploit PoCs and CVE details for identified vulnerabilities (use WebSearch)
3. Identify gaps — what vulnerability categories are NOT in the report?
4. Prioritize Psalm taint findings for injection-based attack chains
5. Think like an attacker: what's the path of least resistance into this system?

WRITE your analysis to:
  {report_dir}/red-team-analysis.md

Use this format:

# Red Team Analysis

## Attack Scenarios
| # | Scenario | Findings Chained | Impact | Exploitability | Steps to Exploit |
|---|----------|-----------------|--------|----------------|------------------|

## Detailed Attack Chains
### Scenario {N}: {title}
- Preconditions: {what attacker needs}
- Step 1: {action} — exploits {finding}
- Step 2: {action} — leverages {finding}
- Impact: {what attacker gains}
- Real-world likelihood: High / Medium / Low

## Gaps in Audit Coverage
| # | Missing Category | Why It Matters | How to Test |
|---|-----------------|----------------|-------------|

## Known CVEs Relevant to Findings
| # | CVE | Finding | Exploit Available? | CVSS |
|---|-----|---------|-------------------|------|

## Summary
- Attack scenarios found: {N}
- Critical chains: {N}
- Audit gaps identified: {N}
- CVEs matched: {N}

WHEN DONE:
When the file is written, you are done. Do not message anyone — the lead reads your
file and dispatches the challenge round; there is no channel between you and the other two.
Mark your task as completed.
```

### Analyst 3: Compliance Checker

**Model:** sonnet
**MaxTurns:** 10
**Isolation:** worktree
**Tools:** Read, Glob, Grep, WebFetch
**Effort:** high

```
You are the Compliance Checker for a security audit debate team.

REPORT LOCATION:
{report_dir}/security-report.json

DRUPAL SECURITY CONTEXT (if available):
{report_dir}/security-context.md

YOUR MISSION:
Map findings to OWASP Top 10 and CWE standards. Your lens: "Where are we uncovered against standards?"

1. Use Semgrep output's `owasp` and `cwe` metadata fields as primary mapping source
2. Look up specific CWE definitions when mapping is ambiguous (use WebSearch)
3. Build OWASP Top 10 (2021) coverage matrix: which categories are covered, which have gaps
4. For each finding: validate or correct the CWE classification
5. Identify which OWASP categories have zero coverage — these are blind spots

WRITE your analysis to:
  {report_dir}/compliance-analysis.md

Use this format:

# Compliance Analysis

## OWASP Top 10 (2021) Coverage Matrix
| Category | ID | Findings Mapped | Coverage | Gaps | Recommendation |
|----------|----|----------------|----------|------|----------------|
| Broken Access Control | A01 | {list} | Full / Partial / None | {gaps} | {action} |
| Cryptographic Failures | A02 | {list} | Full / Partial / None | {gaps} | {action} |
| Injection | A03 | {list} | Full / Partial / None | {gaps} | {action} |
| Insecure Design | A04 | {list} | Full / Partial / None | {gaps} | {action} |
| Security Misconfiguration | A05 | {list} | Full / Partial / None | {gaps} | {action} |
| Vulnerable Components | A06 | {list} | Full / Partial / None | {gaps} | {action} |
| Auth Failures | A07 | {list} | Full / Partial / None | {gaps} | {action} |
| Data Integrity Failures | A08 | {list} | Full / Partial / None | {gaps} | {action} |
| Logging Failures | A09 | {list} | Full / Partial / None | {gaps} | {action} |
| SSRF | A10 | {list} | Full / Partial / None | {gaps} | {action} |

## CWE Mapping Corrections
| # | Finding | Original CWE | Corrected CWE | Reason |
|---|---------|-------------|---------------|--------|

## Compliance Gaps (No Coverage)
| # | Standard Category | Risk | Recommended Tool/Check |
|---|------------------|------|----------------------|

## Summary
- OWASP categories fully covered: {N}/10
- OWASP categories partially covered: {N}/10
- OWASP categories with no coverage: {N}/10
- CWE corrections made: {N}

WHEN DONE:
When the file is written, you are done. Do not message anyone — the lead reads your
file and dispatches the challenge round; there is no channel between you and the other two.
Mark your task as completed.
```

---

## Output

Writes into `{report_dir}`, the directory holding the `security-report.json` this run debates:

- `security-debate.md` — the lead's synthesis
- `defender-analysis.md`, `red-team-analysis.md`, `compliance-analysis.md` — one per analyst, round 1
- `defender-challenge.md`, `red-team-challenge.md`, `compliance-challenge.md` — one per analyst, round 2; left in place as the evidence behind the synthesis
- `security-context.md` — the dev-guides content fetched for this run, saved so the analysts can read it. `OUTPUTS.md` notes this as a write no rule covers: fetched guide content otherwise belongs in the navigator's shared store.

It does not modify `security-report.json`.

## Output Format

The lead synthesizes into `{report_dir}/security-debate.md`:

```markdown
# Security Debate Assessment

## Audit Summary
{From security-report.json: total findings, severity breakdown, tools used}

## Debated Findings
| # | Finding | Severity (Original) | Defender | Red Team | Compliance | Final Severity |
|---|---------|---------------------|----------|----------|------------|----------------|

## Attack Scenarios (Red Team)
| # | Scenario | Findings Chained | Impact | Exploitability |
|---|----------|-----------------|--------|----------------|

## False Positives Identified (Defender)
| # | Finding | Reason | Confidence |
|---|---------|--------|------------|

## OWASP Top 10 Coverage (Compliance)
| Category | Covered | Gaps | Recommendation |
|----------|---------|------|----------------|
| A01: Broken Access Control | ... | ... | ... |
| A02: Cryptographic Failures | ... | ... | ... |
| A03: Injection | ... | ... | ... |
| A04: Insecure Design | ... | ... | ... |
| A05: Security Misconfiguration | ... | ... | ... |
| A06: Vulnerable Components | ... | ... | ... |
| A07: Auth Failures | ... | ... | ... |
| A08: Data Integrity Failures | ... | ... | ... |
| A09: Logging Failures | ... | ... | ... |
| A10: SSRF | ... | ... | ... |

## Unanimous Agreements (Potential Blind Spots)
{Findings where all 3 agents agreed — flag for human review since groupthink may mask issues}

## Prioritized Remediation
| Priority | Finding | Severity | Attack Scenario | CWE | Effort |
|----------|---------|----------|----------------|-----|--------|

## Debate Log
{Key disagreements and how they resolved}
```

## Where This Fits (defense in depth)

This debate is the **whole-codebase, multi-agent OWASP** layer — it has **no native equivalent**. It sits above the native diff/in-session layers: the official **security-guidance** plugin reviews Claude's *own* edits in session (auto, no command; offered by `/code-quality-tools:setup`), native `/security-review` runs one generic, diff-scoped pass on demand, and the **Claude Security** plugin (`/plugin install claude-security@claude-plugins-official`) runs a multi-agent deep scan of a whole repository with independently reviewed findings and a SARIF log. None of the three chains findings into attack scenarios, maps OWASP/CWE coverage, or challenges severity across competing perspectives. Run those native layers to reduce what reaches a scan; run this debate to pressure-test the whole-tree findings `/code-quality-tools:security` produced.

## Related Commands

- `/code-quality-tools:security` - Run security audit (prerequisite — generates the report this command debates)
- `/code-quality-tools:audit` - Full audit (includes security)
- `/code-quality-tools:architecture-debate` - Architecture and SOLID debate (Pragmatist + Purist + Maintainer)
- `/code-quality-tools:review` - Rubric-scored code review
- native `/security-review` - generic diff-scoped vuln pass; the **security-guidance** plugin covers Claude's own in-session edits. Both complement — neither replaces — this whole-codebase debate layer.
