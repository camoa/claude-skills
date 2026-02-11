---
description: Debate security audit findings with competing agent team (Defender + Red Team + Compliance)
allowed-tools: Read, Write, Glob, Grep, WebSearch, WebFetch
argument-hint: optional|project-path
---

# Security Debate

Analyze security audit results from 3 competing perspectives using an agent team. A Defender validates findings, a Red Team Attacker finds gaps, and a Compliance Checker maps to standards. They debate severity and produce a challenged assessment.

## Usage

```
/code-quality:security-debate [project-path]
```

## What This Does

Spawns a 3-teammate agent team that debates the results of a prior security audit. Each teammate writes their analysis to a separate file. The lead synthesizes a final `.reports/security-debate.md` with debated severity ratings, attack scenarios, false positives, and OWASP coverage.

## Instructions

When this command is invoked with `$ARGUMENTS`:

### Step 1 — Check Report Exists

Look for `.reports/security-report.json` in the project root (or `$ARGUMENTS` path if provided).

If not found:
> No security report found at `.reports/security-report.json`.
> Run `/code-quality:security` first to generate the audit report.

Stop here if not found.

### Step 2 — Check Prerequisites

Verify agent teams are available. If not:

> Agent teams require the experimental flag:
> ```json
> // Add to ~/.claude/settings.json
> { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
> ```
> Or: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
>
> **Fallback:** Your security audit results are in `.reports/security-report.json`. Run `/code-quality:security` for standard single-pass analysis.

Stop here if not available.

### Step 3 — Assess Report Size

Read `.reports/security-report.json` and count findings.

If fewer than 10 findings:
> Found {N} findings. For small reports, single-agent analysis may be sufficient.
> Continue with agent team debate? (The team adds most value with 10+ findings.)

Continue if user confirms or if 10+ findings.

### Step 4 — Create Shared Task List

Create a team and these tasks:

| # | Task | Assign to | Depends on |
|---|------|-----------|------------|
| 1 | Validate findings — identify false positives, assess exploitability | Defender | — |
| 2 | Construct attack scenarios — chain findings, find gaps audit missed | Red Team Attacker | — |
| 3 | Map findings to OWASP Top 10 / CWE standards, identify coverage gaps | Compliance Checker | — |
| 4 | Cross-challenge — debate severity, exploitability, priorities | All three | 1, 2, 3 |
| 5 | Synthesize challenged security assessment | Lead | 4 |

### Step 5 — Spawn Teammates

Spawn 3 teammates using the prompt templates below. After spawning:

1. Tell the user: "Team spawned. Teammates are working — I'll synthesize when they finish."
2. If running inside tmux, teammates appear in split panes (visible output). Otherwise they run in-process (background).
3. Do NOT perform analysis yourself — wait for all teammates to complete before proceeding.

### Step 6 — Synthesize

When all teammates finish:

- Read `.reports/defender-analysis.md`, `.reports/red-team-analysis.md`, `.reports/compliance-analysis.md`
- Write `.reports/security-debate.md` using the Output Format below
- Tell the user: "Security debate complete. Assessment saved to `.reports/security-debate.md`"

---

## Spawn Prompts

### Teammate 1: Defender

**Model:** sonnet

```
You are the Defender for a security audit debate team.

REPORT LOCATION:
{project_path}/.reports/security-report.json

YOUR MISSION:
Validate each audit finding and identify false positives. Your lens: "Is this finding actually exploitable in context?"

For each finding:
1. Assess reachability — is user input actually connected to the vulnerable code path?
2. Check context — does the framework (Drupal/Next.js) already mitigate this?
3. Prioritize Psalm taint analysis findings over pattern-matching results
4. Classify each as: Confirmed (exploitable), Likely (plausible), Unlikely (false positive), False Positive

WRITE your analysis to:
  {project_path}/.reports/defender-analysis.md

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
Message the other teammates: "Defender analysis complete. Review defender-analysis.md"
Mark your task as completed.
```

### Teammate 2: Red Team Attacker

**Model:** sonnet

```
You are the Red Team Attacker for a security audit debate team.

REPORT LOCATION:
{project_path}/.reports/security-report.json

YOUR MISSION:
Construct attack scenarios and find what the audit missed. Your lens: "What attack chains exist and what's missing?"

1. Chain related findings into attack scenarios (e.g., SSRF + file upload = RCE)
2. Search for exploit PoCs and CVE details for identified vulnerabilities (use WebSearch)
3. Identify gaps — what vulnerability categories are NOT in the report?
4. Prioritize Psalm taint findings for injection-based attack chains
5. Think like an attacker: what's the path of least resistance into this system?

WRITE your analysis to:
  {project_path}/.reports/red-team-analysis.md

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
Message the other teammates: "Red Team analysis complete. Review red-team-analysis.md"
Mark your task as completed.
```

### Teammate 3: Compliance Checker

**Model:** sonnet

```
You are the Compliance Checker for a security audit debate team.

REPORT LOCATION:
{project_path}/.reports/security-report.json

YOUR MISSION:
Map findings to OWASP Top 10 and CWE standards. Your lens: "Where are we uncovered against standards?"

1. Use Semgrep output's `owasp` and `cwe` metadata fields as primary mapping source
2. Look up specific CWE definitions when mapping is ambiguous (use WebSearch)
3. Build OWASP Top 10 (2021) coverage matrix: which categories are covered, which have gaps
4. For each finding: validate or correct the CWE classification
5. Identify which OWASP categories have zero coverage — these are blind spots

WRITE your analysis to:
  {project_path}/.reports/compliance-analysis.md

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
Message the other teammates: "Compliance analysis complete. Review compliance-analysis.md"
Mark your task as completed.
```

---

## Output Format

The lead synthesizes into `.reports/security-debate.md`:

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

## Related Commands

- `/code-quality:security` - Run security audit (prerequisite — generates the report this command debates)
- `/code-quality:audit` - Full audit (includes security)
