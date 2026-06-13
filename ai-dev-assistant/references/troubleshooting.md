# Troubleshooting

Symptom-first triage for framework + Claude Code platform issues.

## Framework state diagnostics

Use these when framework behavior is unexpected:

| Symptom | First check |
|---------|-------------|
| `/next` picks the wrong task | `/ai-dev-assistant:status` (tree view + active task) and `~/.claude/ai-dev-assistant/sessions/<workspace_hash>.json` |
| Hardened gate appears to skip | `/ai-dev-assistant:audit-status <task>` — lists fired and unaudited gates per task |
| Playbook citation fails | `/ai-dev-assistant:playbook-active` (subscribed sets, local playbook, recent conflicts) |
| Phase artifact missing fields after upgrade | `/ai-dev-assistant:upgrade-project` (active project only — backfills + journal-resumable) |
| `/research` epic gate didn't fire | `_pre-analysis.json` in task folder; if absent for a v3.x task, it's grandfathered (pre-v4.0.0) |
| Coverage-mapping gate keeps failing | `scripts/coverage-mapping-check.sh <task_folder>` — verbose output shows per-question matching |

## Claude Code platform diagnostics

For platform-level issues (CLAUDE.md ignored, hooks not firing, MCP not connecting, settings not taking effect, plugin/skill not loaded), see the upstream **Debug Your Config** guide:

- `/context` — what content is currently in context
- `/memory` — loaded CLAUDE.md / AGENTS.md files
- `/doctor` — installation, plugin load errors, environment issues
- `/hooks` — registered hooks and their sources (per-event, per-matcher)
- `/mcp` — MCP server connection state
- `/skills` — loaded skills and their source plugin
- `/permissions` — current permission ruleset (allow/deny/ask)
- `/status` — session info (model, working directory, settings paths loaded)

Upstream guide: `https://code.claude.com/docs/en/configuration/debug-your-config`. The auto-mode classifier has its own dedicated reference (`Auto Mode Config`); enterprise rollout has `Admin Setup`. None of those live in the `camoa/dev-guides` corpus — `dev-guides-navigator` only routes to project guides, not Claude Code platform docs.

## Reading-strategy reminder

Before debugging framework code, treat the work as **Type B** (audit / review / architecture analysis): read full source and config files, do not grep-first. Inherited methods, annotations, and config-wired classes are invisible to a grep-first pass. See `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`.
