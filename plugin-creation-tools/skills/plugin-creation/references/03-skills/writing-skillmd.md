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
name: processing-pdfs
description: Extracts text and tables from PDF files, fills forms. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
---
```

| Field | Required | Constraints |
|-------|----------|-------------|
| `name` | Yes | Lowercase, numbers, hyphens only. Max 64 chars. No "anthropic" or "claude". |
| `description` | Yes | Max 1024 chars. Must include WHAT and WHEN. Third person only. |
| `allowed-tools` | No | Restricts available tools when skill active |
| `license` | No | License for the skill |
| `metadata` | No | Custom key-value pairs |

**Do not add other fields.** Only these are recognized.

### Naming Convention

**Prefer gerund form** (verb + -ing) for skill names:

| Good (Gerund) | Acceptable | Avoid |
|---------------|------------|-------|
| `processing-pdfs` | `pdf-processing` | `pdf-helper` |
| `analyzing-code` | `code-analyzer` | `utils` |
| `managing-git` | `git-manager` | `tools` |

Reserved words not allowed: `anthropic`, `claude`

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

## Reference File Guidelines

### Table of Contents for Long Files

For reference files longer than 100 lines, add a table of contents:

```markdown
# API Reference

## Contents
- Authentication and setup
- Core methods (create, read, update, delete)
- Advanced features (batch operations, webhooks)
- Error handling patterns
- Code examples

## Authentication and setup
...
```

### One Level Deep Only

**Avoid nested references.** All reference files should link directly from SKILL.md.

```
Bad (nested):
  SKILL.md → advanced.md → details.md → actual-info.md

Good (flat):
  SKILL.md → advanced.md
  SKILL.md → details.md
  SKILL.md → actual-info.md
```

### Avoid Time-Sensitive Information

Don't include dates or temporal references that will become outdated:

```markdown
# Bad
If you're doing this before August 2025, use the old API.

# Good
## Current method
Use the v2 API endpoint.

## Legacy patterns (deprecated)
<details>
<summary>v1 API (no longer supported)</summary>
...
</details>
```

## Testing Skills

### Test with Multiple Models

Skills behave differently across models. Test with:

| Model | Check For |
|-------|-----------|
| Claude Haiku | Does the skill provide enough guidance? |
| Claude Sonnet | Is the skill clear and efficient? |
| Claude Opus | Does the skill avoid over-explaining? |

### Create Evaluations

Build at least 3 test scenarios before finalizing:

```json
{
  "skills": ["pdf-processing"],
  "query": "Extract text from this PDF and save to output.txt",
  "files": ["test-files/document.pdf"],
  "expected_behavior": [
    "Reads the PDF using appropriate library",
    "Extracts text from all pages",
    "Saves to output.txt"
  ]
}
```

## Checklist Before Completion

### Core Quality
- [ ] Under 500 lines
- [ ] Imperative/third person voice
- [ ] Clear structure with headers
- [ ] One excellent example per pattern
- [ ] References linked, not duplicated
- [ ] No unnecessary content
- [ ] No time-sensitive information
- [ ] Consistent terminology throughout

### Frontmatter
- [ ] Name uses gerund form (preferred)
- [ ] Name is lowercase, hyphens only
- [ ] Description is third person
- [ ] Description includes WHAT and WHEN
- [ ] Description under 1024 chars

### References
- [ ] All references one level deep
- [ ] Files >100 lines have table of contents
- [ ] Progressive disclosure used appropriately

### Testing
- [ ] Tested with Haiku, Sonnet, Opus
- [ ] At least 3 evaluation scenarios
- [ ] Real usage scenarios tested
