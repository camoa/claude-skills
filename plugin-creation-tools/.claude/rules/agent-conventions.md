---
paths:
  - "agents/**"
---

# Agent Conventions (this plugin)

## Required Frontmatter
- `name` — kebab-case.
- `description` — opens with imperative identity + delegation triggers ("Use proactively…", "Use when user mentions…"). Must include keywords users would actually say.
- `tools` — minimum needed. Read-only agents (`plugin-structure-auditor`, `skill-quality-reviewer`) restrict to `Read, Glob, Grep` (`+Bash` for the auditor).
- `model` — `sonnet` for the audit agents; `haiku` would under-reason on cross-component findings.

## Optional Frontmatter
- `maxTurns` — bounded for cost. Auditor uses 20 (multi-file traversal); reviewer uses 15 (per-skill loops). Don't raise without a justified reason.
- `disallowedTools` — explicitly block `Edit`, `Write` on review-only agents to prevent accidental writes through the Task tool.

## Body
- One agent = one responsibility. The audit agent does NOT do skill-quality review, and vice versa.
- Output format must be deterministic (fits in a single response — see auditor's "do not split across turns" rule).
- Score on evidence cited from the files, not vibes.
- Do NOT duplicate `/plugin-creation-tools:validate` checks — those are owned by the validator. Agents own structural / qualitative judgment that the validator can't make.

## Behavior Notes
- Plugin-packaged agents have `hooks`, `mcpServers`, `permissionMode` silently ignored for security. Don't author those fields here.
- For agents users may launch as the main session via `--agent` (rare in this plugin), frontmatter `hooks` and inline `mcpServers` now fire as of Claude Code v2.1.117+ — but this plugin's agents are spawn-only, so it doesn't apply.
