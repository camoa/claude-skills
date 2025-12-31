# Skill Anti-Patterns

Common mistakes when creating skills and how to avoid them.

## The #1 Anti-Pattern: Documentation Instead of Instructions

**SKILL.md must be INSTRUCTIONS for Claude, not documentation about the skill.**

| Documentation (WRONG) | Instructions (CORRECT) |
|----------------------|------------------------|
| "This skill helps with PDF processing" | "Process PDF files using this workflow" |
| "What Are Skills?" | "## Workflow" |
| "Skills extend Claude's capabilities" | "When triggered, execute these steps" |
| "Guide for creating effective skills" | "Follow this workflow to create a skill" |

**How to detect**: Read each sentence. If it explains what something IS rather than what to DO, rewrite it.

## Content Anti-Patterns

| Pattern | Problem | Solution |
|---------|---------|----------|
| **Code reproduction** | Copying code that exists in codebase | Reference file paths: `src/module.py:45` |
| Narrative examples | "In session 2025-10-03..." | Use generic, reusable examples |
| Multi-language dilution | Same example in 5 languages | One excellent example in most relevant language |
| "Just in case" content | Hypothetical scenarios | Include only needed content |
| Tutorial-style | Step-by-step installation guides | Decision-focused: "when to use X vs Y" |
| Historical explanations | "This evolved from..." | Current state only |

## Structure Anti-Patterns

| Pattern | Problem | Solution |
|---------|---------|----------|
| Monolithic SKILL.md | 2000+ lines | Split into references/ |
| Duplicate information | Same content multiple places | Single source of truth |
| Deeply nested references | SKILL.md → file1 → file2 | Keep one level deep |
| Missing resources | References to nonexistent files | Validate before packaging |
| Auxiliary files | README.md, CHANGELOG.md | Remove - use SKILL.md only |

## Description Anti-Patterns

| Pattern | Problem | Solution |
|---------|---------|----------|
| Vague triggers | "Helps with documents" | Specific: "Use when working with .docx files" |
| First person | "You should use this when..." | Third person: "Use when..." |
| Missing keywords | No searchable terms | Include error messages, symptoms |
| Too long | 2000 character description | Under 1024, ideal 200-500 |
| No triggers | Just describes what skill does | Start with "Use when..." |

## Rationalization Red Flags

Watch for these when testing - they indicate skill needs strengthening:

| Rationalization | Counter |
|-----------------|---------|
| "This is just a simple case" | Simple cases are when discipline matters most |
| "I can check quickly first" | Skill defines the checking process |
| "Let me gather info first" | Skill tells HOW to gather info |
| "The skill is overkill" | If skill exists for task, use it |
| "I remember this skill" | Skills evolve - run current version |
| "This doesn't count as a task" | If taking action, check for skills |

## The Reference-First Rule

Before including any code, ask: **"Can I reference existing code instead?"**

| Situation | Action |
|-----------|--------|
| Pattern exists in core/contrib | Reference the file path |
| Official docs have examples | Link to docs |
| Pattern needs illustration | Brief snippet (5-15 lines) + file reference |
| No existing example | Create minimal, tested example |

## What NOT to Include

> **Attribution**: The plugin vs skill level distinction is based on best practices from Anthropic's `skill-creator` skill (document-skills@anthropic-agent-skills).

**Critical distinction: Plugin level vs Skill level**

### ❌ NEVER in Skills (skills/skill-name/)

Skills should ONLY contain essential files for AI execution:

| Don't Include | Why |
|---------------|-----|
| README.md | Use SKILL.md instead - README is for humans, SKILL.md is for AI |
| INSTALLATION_GUIDE.md | Not needed for AI execution |
| CHANGELOG.md | Historical clutter - skills version with their plugin |
| QUICK_REFERENCE.md | Put in SKILL.md or references/ |
| User-facing documentation | Skills are for AI, not humans |
| LICENSE files | License belongs at plugin root |

**Bad (skill has human docs):**
```
skills/my-skill/
├── SKILL.md
├── README.md       ❌ NO - redundant with SKILL.md
├── CHANGELOG.md    ❌ NO - skills version with plugin
└── LICENSE         ❌ NO - belongs at plugin root
```

**Good (skill has only AI files):**
```
skills/my-skill/
├── SKILL.md        ✅ AI instructions
├── scripts/        ✅ Bundled resources
├── references/     ✅ Loaded as needed
└── assets/         ✅ Used in output
```

### ✅ Required at Plugin Level (plugin root)

Plugins (the overall package) SHOULD have human-facing documentation:

```
my-plugin/
├── README.md           ✅ User-facing docs, GitHub visibility
├── CHANGELOG.md        ✅ Version history, marketplace updates
├── LICENSE             ✅ Legal clarity
├── .claude-plugin/
│   └── plugin.json
└── skills/
    └── my-skill/
        └── SKILL.md    ✅ AI instructions only
```

**Why the distinction?**
- **Plugin README/CHANGELOG**: For humans (GitHub visitors, marketplace users)
- **Skill SKILL.md**: For AI agents only (no human-facing fluff)

The skill is Claude's "onboarding guide" - it should contain ONLY what Claude needs to execute the task, nothing more.
