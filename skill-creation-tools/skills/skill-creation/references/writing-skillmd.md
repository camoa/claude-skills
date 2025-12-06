# Writing Effective SKILL.md

Detailed guidance on voice, style, structure, and word count for SKILL.md files.

## The Critical Distinction

**SKILL.md files are INSTRUCTIONS for Claude, not documentation about the skill.**

This is the most common mistake. When Claude reads a SKILL.md, it needs to know what to DO, not what the skill IS.

| Documentation (WRONG) | Instructions (CORRECT) |
|----------------------|------------------------|
| "This skill processes PDFs" | "Process PDFs using this workflow" |
| "Skills extend Claude's capabilities" | "When triggered, follow these steps" |
| "The form filling feature supports..." | "To fill forms, run scripts/fill_form.py" |
| "What Are Skills?" | "## Workflow" |
| "Guide for creating skills" | "Follow this workflow to create a skill" |

**Test your SKILL.md**: Read each sentence and ask "Does this tell Claude what to DO?" If it explains what something IS, rewrite it.

## Voice and Style

| Do | Don't |
|----|-------|
| "To create a document, use..." | "You should create a document by..." |
| "Extract text with pdfplumber" | "If you need to extract text, you can..." |
| Third person descriptions | First/second person instructions |
| Imperative/infinitive form | Narrative storytelling |

### Examples

**Good (imperative, third person):**
```markdown
## Creating Documents
To create a new document, initialize a Document object and add paragraphs.
Run scripts/create_doc.py for templated creation.
```

**Bad (second person, narrative):**
```markdown
## Creating Documents
When you want to create a document, you should first think about what you need.
If you're making a report, you might want to start with a template...
```

## Recommended Structure

```markdown
---
name: skill-name
description: Use when [triggers] - [what it does]
---

# Skill Name

## Overview
[1-2 sentence purpose statement]

## When to Use
- [Specific trigger 1]
- [Specific trigger 2]
- NOT for: [anti-patterns]

## Core Pattern
[Essential technique or workflow]

## Quick Reference
| Operation | Command/Code |
|-----------|--------------|
| ... | ... |

## Implementation
[Step-by-step with examples]

## Common Mistakes
| Mistake | Fix |
|---------|-----|
| ... | ... |

## See Also
- references/detailed-guide.md
- scripts/helper.py
```

## Word Count Targets

| Skill Type | Target | When |
|------------|--------|------|
| Getting-started | <150 words | Loads every conversation |
| Frequently-loaded | <200 words | Used often |
| Standard skills | <500 words | Normal usage |
| Complex reference | <5000 words | Use progressive disclosure |

### Why These Limits?

- **<150 words**: Skills that load in every conversation (like `using-superpowers`) must be minimal
- **<200 words**: Frequently triggered skills should minimize context impact
- **<500 words**: Standard skills balance completeness with efficiency
- **<5000 words**: Complex skills MUST use progressive disclosure (references/)

## Line Count Target

**Keep SKILL.md under 500 lines.** If approaching this limit:
1. Move detailed content to `references/`
2. Link from SKILL.md: "See references/topic.md for..."
3. Keep only essential workflow in SKILL.md

## Frontmatter Requirements

```yaml
---
name: skill-name-with-hyphens
description: Use when [specific triggers] - [what it does, third person]
---
```

| Field | Required | Constraints |
|-------|----------|-------------|
| `name` | Yes | Lowercase, numbers, hyphens only. Max 64 chars |
| `description` | Yes | Max 1024 chars. Must include WHAT and WHEN |
| `allowed-tools` | No | Restricts available tools when skill active |
| `license` | No | License for the skill |
| `metadata` | No | Custom key-value pairs |

**Do not add other fields.** Only these are recognized.

## Section Guidelines

### Overview
- 1-2 sentences maximum
- State the purpose clearly
- No background or history

### When to Use
- Bullet list of specific triggers
- Include "NOT for:" anti-patterns
- Match the description field

### Core Pattern
- The essential technique or workflow
- Scannable format (bullets, tables)
- One excellent example if needed

### Quick Reference
- Table format preferred
- Most common operations only
- Commands, not explanations

### Implementation
- Step-by-step when needed
- Reference files, don't reproduce
- Brief examples (5-15 lines max)

### Common Mistakes
- Table format: Mistake | Fix
- Real issues, not hypothetical
- Brief, actionable fixes

### See Also
- Link to references/ files
- Link to scripts/
- No external links unless critical

## Progressive Disclosure Patterns

### Pattern 1: Hub with References
```markdown
## PDF Processing

Quick start: `python scripts/process.py input.pdf`

For advanced features:
- **Form filling**: See references/forms.md
- **Merging**: See references/merge.md
- **OCR**: See references/ocr.md
```

### Pattern 2: Conditional Loading
```markdown
## Document Editing

For simple edits, modify content directly.

**For tracked changes**: See references/tracked-changes.md
**For complex formatting**: See references/formatting.md
```

### Pattern 3: Domain Organization
```
skill/
├── SKILL.md (overview + navigation)
└── references/
    ├── finance.md    # Load for finance questions
    ├── sales.md      # Load for sales questions
    └── support.md    # Load for support questions
```

## Checklist Before Completion

- [ ] Under 500 lines
- [ ] Imperative/third person voice
- [ ] Clear structure with headers
- [ ] One excellent example per pattern
- [ ] References linked, not duplicated
- [ ] No unnecessary content
