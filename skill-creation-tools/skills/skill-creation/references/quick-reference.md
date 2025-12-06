# Quick Reference

Templates, commands, and size guidelines for rapid skill development.

## SKILL.md Template

```yaml
---
name: my-skill-name
description: Use when [specific triggers] - [what it does, third person]. Keywords: [relevant terms]
version: 1.0.0
---

# My Skill Name

## Overview
[1-2 sentence purpose]

## When to Use
- [Trigger 1]
- [Trigger 2]
- NOT for: [anti-pattern]

## Core Pattern
[Essential workflow - keep brief]

## Quick Reference
| Operation | How |
|-----------|-----|
| ... | ... |

## Implementation
[Step-by-step with brief examples]

## Common Mistakes
| Mistake | Fix |
|---------|-----|
| ... | ... |

## See Also
- references/details.md
- scripts/helper.py
```

## Description Templates

### Technique Skill
```
Use when [symptom] or [situation] - [action verb] [problem] by [technique], providing [benefit]
```
**Example**: "Use when tests have race conditions or timing dependencies - eliminates flaky tests by replacing timeouts with condition polling"

### Reference Skill
```
Comprehensive [topic] with support for [features]. Use when Claude needs [task] for: (1) [Use case], (2) [Use case], (3) [Use case]
```
**Example**: "Comprehensive document creation with support for tracked changes. Use when Claude needs to work with .docx files for: (1) Creating documents, (2) Editing content, (3) Working with tracked changes"

### Discipline Skill
```
Use when [trigger situation] - requires [action] before [completing action]. [Key constraint or rule]
```
**Example**: "Use when about to claim work is complete - requires running verification commands before making success claims. Evidence before assertions."

### Toolkit Skill
```
[What it does] with [key features]. Use when [specific request pattern] like "[example user request]"
```
**Example**: "PDF form filling with field extraction and validation. Use when users request filling PDF forms like 'fill out this application form'"

## Validation Commands

```bash
# Check frontmatter format
head -20 SKILL.md

# Count lines (target: <500)
wc -l SKILL.md

# Find broken references
grep -o 'references/[^)]*' SKILL.md | while read f; do
  [ -f "$f" ] || echo "Missing: $f"
done

# Find broken script references
grep -o 'scripts/[^)]*' SKILL.md | while read f; do
  [ -f "$f" ] || echo "Missing: $f"
done

# Test scripts run without errors
for script in scripts/*.py; do
  python "$script" --help 2>/dev/null || echo "Check: $script"
done

# Run skill validator
python scripts/validate_skill.py .
```

## Size Guidelines

| Component | Target | Maximum |
|-----------|--------|---------|
| Description | 200-500 chars | 1024 chars |
| SKILL.md body | <500 lines | 5000 words |
| Individual reference | <1000 lines | 10k words |
| Code examples | 5-15 lines | 50 lines |
| Total skill files | <50 files | No hard limit |

## Frontmatter Constraints

| Field | Required | Format |
|-------|----------|--------|
| `name` | Yes | Lowercase letters, numbers, hyphens only. Max 64 chars. No "anthropic" or "claude" |
| `description` | Yes | Max 1024 chars. No XML tags. Must include WHAT and WHEN |
| `version` | No | Semantic versioning (e.g., 1.0.0) |
| `dependencies` | No | List of required packages (e.g., python>=3.8, pandas>=1.5.0) |
| `license` | No | License name or file reference |
| `allowed-tools` | No | Array of tool names |
| `metadata` | No | Key-value pairs |

## Directory Structure

```
my-skill/
├── SKILL.md              # Required
├── scripts/              # Optional - executable code
│   └── helper.py
├── references/           # Optional - detailed docs
│   └── details.md
└── assets/               # Optional - templates, images
    └── template.docx
```

## Component Decision Quick Reference

| Content Type | Put In |
|--------------|--------|
| Core workflow | SKILL.md |
| Detailed docs (>100 lines) | references/ |
| Reusable code | scripts/ |
| Templates, images | assets/ |
| Everything else | Don't include |

## Common Patterns

### Progressive Disclosure
```markdown
## Feature Overview
Basic usage: `command --simple`

For advanced options: See references/advanced.md
```

### Domain Split
```
references/
├── aws.md      # AWS-specific
├── gcp.md      # GCP-specific
└── azure.md    # Azure-specific
```

### Conditional Detail
```markdown
## Editing
For simple edits, modify directly.

**Complex formatting**: See references/formatting.md
**Tracked changes**: See references/tracked-changes.md
```

## Skill Lifecycle Commands

```bash
# Initialize new skill
python scripts/init_skill.py my-skill --path ./skills

# Validate skill
python scripts/validate_skill.py ./my-skill

# Package for distribution
python scripts/package_skill.py ./my-skill

# Package to specific output
python scripts/package_skill.py ./my-skill ./dist
```
