---
description: Validate plugin structure, frontmatter, and best practices
allowed-tools: Read, Glob, Grep
argument-hint: [plugin-path]
---

# Validate Plugin

Validate a plugin's structure and components against best practices.

## Steps

1. Determine plugin path: use `$1` if provided, otherwise detect from current directory
2. Find `.claude-plugin/plugin.json` to confirm it's a plugin root
3. Run all validation checks below
4. Report results as a structured checklist

## Validation Checks

### Plugin Structure
- [ ] `.claude-plugin/plugin.json` exists and is valid JSON
- [ ] `name` field present in plugin.json
- [ ] `version` follows semver
- [ ] `description` present and not placeholder text
- [ ] README.md exists at plugin root
- [ ] CHANGELOG.md exists at plugin root

### Skills (for each skill in `skills/*/`)
- [ ] `SKILL.md` exists with valid YAML frontmatter
- [ ] Frontmatter has `name` (hyphen-case, max 64 chars)
- [ ] Frontmatter has `description` (starts with "Use when" or three-part structure, max 1024 chars)
- [ ] Description includes WHAT it does AND WHEN to use it (trigger conditions)
- [ ] Description uses third person (no "you")
- [ ] No XML angle brackets (< >) in frontmatter (security restriction)
- [ ] `compatibility` field valid if present (1-500 chars)
- [ ] Body is instructions, not documentation (imperative voice)
- [ ] Body under 500 lines
- [ ] Body includes examples section with user scenarios (warning if missing)
- [ ] Body includes troubleshooting/error handling section (warning if missing)
- [ ] Referenced files in `references/` exist
- [ ] Referenced scripts in `scripts/` exist
- [ ] No README.md inside skill directories (belongs at plugin root)

### Commands (for each `commands/*.md`)
- [ ] Valid YAML frontmatter
- [ ] `description` field present
- [ ] `allowed-tools` field present
- [ ] No inline code with backtick+exclamation or backtick+at-sign that could trigger execution

### Agents (for each `agents/*.md`)
- [ ] Valid YAML frontmatter
- [ ] `name` field present
- [ ] `description` field present (includes delegation triggers)
- [ ] `tools` field present
- [ ] `model` field present (haiku, sonnet, opus, or inherit)

### Hooks (`hooks/hooks.json`)
- [ ] Valid JSON structure
- [ ] Each event name is a recognized event
- [ ] Each hook entry has `type` (command, prompt, or agent) and matching field
- [ ] Command hooks reference executable files
- [ ] Timeouts are reasonable (< 120s for sync hooks)

### Best Practices (warnings, not errors)
- [ ] Skills use progressive disclosure (references for details)
- [ ] Skills include scope boundaries / negative triggers in description if broad
- [ ] Agents specify `model:` for cost optimization
- [ ] Skills consider `model:` field
- [ ] Hook scripts are executable (chmod +x)
- [ ] Skills cross-checked against `references/03-skills/anthropic-skill-standards.md`

## Output Format

```
## Plugin Validation: {name} v{version}

### Errors (must fix)
- ...

### Warnings (should fix)
- ...

### Info
- {n} skills, {n} commands, {n} agents, hooks: {yes/no}, MCP: {yes/no}

### Result: PASS / FAIL
```

## Arguments

- `$1`: Path to plugin directory (optional, defaults to current directory)
