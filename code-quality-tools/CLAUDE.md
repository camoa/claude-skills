# Code Quality Tools - Plugin Conventions

## Capabilities

- **Automated audits** — 22 operations across Drupal (10 security layers) and Next.js (7 security layers)
- **Code review** — Rubric-scored assessment with quality gate (/50 scale, PASS/FAIL)
- **Security debate** — 3-agent team: Defender + Red Team + Compliance (isolated worktrees)
- **Architecture debate** — 3-agent team: Pragmatist + Purist + Maintainer (isolated worktrees)
- **Cross-audit synthesis** — Correlate findings across tools into prioritized action plan

## Skills
- Frontmatter must include: name, description, version, model, allowed-tools, user-invocable
- Description starts with "Use when..." and includes multiple trigger phrases covering synonyms
- Description must be pushy — include "Use proactively" and enforcement where appropriate
- Body uses imperative voice — instructions, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` when command accepts arguments
- Restrict `allowed-tools` to minimum needed
- Commands wrap existing scripts — no logic duplication
- Agent team commands include `maxTurns` (cost control) and `isolation: worktree` (independence)
- Agent team commands orchestrate debate workflows with quality gate enforcement

## Agent Frontmatter Limitations
Agent spawn prompts in this plugin document `effort`, `model`, `maxTurns`, and `isolation` as intent markers inside Markdown. These are NOT evaluated as YAML frontmatter — they are instructions to Claude on how to configure the spawned agent. The actual agent launch mechanism (TeamCreate/TaskCreate) is what enforces model routing and isolation. Do not add `hooks`, `mcpServers`, or `permissionMode` to agent spawn prompt blocks — those fields are not processed in the agent spawning context and will be silently ignored.

## Hooks
The plugin registers one hook in `hooks/hooks.json`:
- **PreCompact** — `hooks/pre-compact.sh` — Preserves audit context before conversation compaction

### StopFailure Hook (CI pipelines)
For users running audits in CI, the `StopFailure` hook event fires when a Claude Code session exits with a non-zero status. This is useful for error alerting. Example pattern to document for CI-integrated projects:

```json
{
  "hooks": {
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST $SLACK_WEBHOOK -d '{\"text\":\"Code quality audit failed in CI\"}'"
          }
        ]
      }
    ]
  }
}
```

Users can add this to their project's `.claude/hooks.json` (not this plugin's hooks.json) to receive failure alerts when `/code-quality:audit` or `/code-quality:security` exits with errors in CI.

## Online Dev-Guides
For Drupal-specific patterns when explaining violations or suggesting fixes, fetch the guide index:
- **Index:** `https://camoa.github.io/dev-guides/llms.txt`
- WebFetch the index to discover available topics, then fetch specific topic pages
- Likely relevant topics: solid-principles, dry-principles, security, testing, tdd, js-development, github-actions

## General
- Reference files instead of reproducing content
- Current state only — no historical narratives
- Scripts handle Drupal (DDEV) and Next.js (npm) detection
