---
paths:
  - "skills/**"
---

# Skill Conventions (this plugin)

## Required Frontmatter
- `name` — kebab-case, max 64 chars, no `claude` / `anthropic`.
- `description` — starts with "Use when…", third person, includes WHAT and WHEN, ≤ 1,536 chars.
- `version` — semver, kept in sync with `.claude-plugin/plugin.json` and the marketplace entry.

## Description Discipline
- **Preserve** any `PROACTIVELY` / `MUST` / `NEVER` imperatives across revisions.
- **Preserve** the `` !`command` `` dynamic-context injection (this plugin uses `` !`ls .claude-plugin/ 2>/dev/null` ``).
- Include synonym coverage for every trigger phrase users might say.

## Body
- Imperative voice — instructions for Claude, not documentation about the skill.
- Under 500 lines (soft cap). If approaching, move detail into `references/`.
- Include both an `Examples` section (worked user scenarios) and a `Troubleshooting` section.
- Use progressive disclosure — link to `references/` rather than reproducing content.

## References
- Live in `references/<NN>-<topic>/` directories.
- One level deep — references must link directly from SKILL.md, not from each other.
- Files >100 lines should have a table of contents.
- Current state only — no historical narratives, no version migration stories.

## Drift Watchlist
The hook event count, hook handler types, plugin component types, reserved marketplace names, and skill-description budget numbers must stay in sync between SKILL.md, `commands/validate.md`, and the relevant references. See `../../CLAUDE.md` "Drift to Watch".
