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

Two scopes in use:

**Plugin-scoped** (`hooks/hooks.json` — session-global, always on when plugin enabled):
- **PreCompact** — `hooks/pre-compact.sh` — Preserves audit context before conversation compaction

**Skill-scoped** (declared in `skills/code-quality-audit/SKILL.md` frontmatter — active only while the skill is loaded):
- **FileChanged** — `hooks/lint-changed.sh` — Watch-mode linting on linter-config edits. Matcher enumerates literal filenames (per Hooks Reference, FileChanged matcher values are literal filenames, NOT globs): `composer.json`, `package.json`, `phpstan.neon`, `phpstan.neon.dist`, `psalm.xml`, `eslint.config.js`, `eslint.config.mjs`, `.eslintrc.json`, `tsconfig.json`. Source-file watching requires populating `watchPaths` dynamically. Force-disable: `CLAUDE_CODE_QUALITY_WATCH=0`.
- **PermissionDenied** — returns `{retry: true}` scoped to `Read|Grep|Glob` only. Prevents audit flows from stalling on auto-mode classifier denials for read-only tools.

Reason for the split: audit-contextual hooks belong to the skill (noise when they fire across unrelated conversations). Session-global concerns (compaction) stay at plugin scope.

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
            "command": "curl -fsS -X POST \"$SLACK_WEBHOOK\" -d '{\"text\":\"Code quality audit failed in CI\"}'"
          }
        ]
      }
    ]
  }
}
```

Users can add this to their project's `.claude/hooks.json` (not this plugin's hooks.json) to receive failure alerts when `/code-quality:audit` or `/code-quality:security` exits with errors in CI.

## Recurring Checks with /loop

Users can run quality checks on a schedule during long coding sessions using Claude Code's built-in `/loop` skill:

```
/loop 30m /code-quality:lint
/loop 1h /code-quality:security
/loop 20m /code-quality:solid src/
```

Session-scoped — checks stop when the session exits. 3-day auto-expiry prevents forgotten loops. Up to 50 concurrent tasks.

For CI-based recurring checks, use GitHub Actions or GitLab CI instead of `/loop`.

## Online Dev-Guides
For Drupal-specific patterns when explaining violations or suggesting fixes, fetch the guide index:
- **Index:** `https://camoa.github.io/dev-guides/llms.txt`
- WebFetch the index to discover available topics, then fetch specific topic pages
- Likely relevant topics: solid-principles, dry-principles, security, testing, tdd, js-development, github-actions

## General
- Reference files instead of reproducing content
- Current state only — no historical narratives
- Scripts handle Drupal (DDEV) and Next.js (npm) detection
