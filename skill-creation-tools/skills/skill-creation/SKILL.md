---
name: skill-creation
description: Use when creating, validating, or packaging Claude Code skills - provides six-step workflow, progressive disclosure, and reference-first philosophy.
version: 1.1.0
---

# Skill Creation

Follow this workflow when creating Claude Code skills.

## Critical Understanding

**SKILL.md files are INSTRUCTIONS for Claude, not documentation about the skill.**

When creating any SKILL.md (including for users of this skill), write imperatives telling Claude what to do, not explanations of what the skill is. The difference:

| Documentation (WRONG) | Instructions (CORRECT) |
|----------------------|------------------------|
| "This skill helps with PDF processing" | "Process PDF files using this workflow" |
| "Skills are model-invoked resources" | "When triggered, execute these steps" |
| "The description field is important" | "Write the description starting with 'Use when...'" |

## Workflow

### Step 1. Gather Concrete Examples

Before writing anything, collect specific usage scenarios:

1. Ask: "What would a user say that should trigger this skill?"
2. List 3-5 concrete examples with expected inputs and outputs
3. Identify trigger words and symptoms

### Step 2. Plan Resources

For each example, determine:
- Scripts needed for repeated execution
- References to load on demand
- Assets for output (templates, images)

### Step 3. Initialize

Run the initialization script:
```bash
python scripts/init_skill.py <skill-name> --path <output-dir>
```

Or create manually:
```bash
mkdir -p my-skill/{scripts,references,assets}
touch my-skill/SKILL.md
```

### Step 4. Write the SKILL.md

Write instructions following these rules:

1. **Imperative voice**: "Run this", "Check that", "If X, do Y"
2. **Action-oriented**: Tell Claude what to do, not what the skill is
3. **Under 500 lines**: Move details to references/
4. **Reference, don't reproduce**: Point to files, don't copy code

Structure the content as:
```markdown
---
name: skill-name
description: Use when [triggers] - [what it does, third person]
version: 1.0.0
---

# Skill Name

[1-2 sentence instruction for Claude]

## When to Use
- [Trigger 1]
- [Trigger 2]
- NOT for: [anti-pattern]

## Workflow
[Step-by-step instructions]

## Quick Reference
[Table of common operations]

## See Also
- references/details.md
- scripts/helper.py
```

See `references/writing-skillmd.md` for detailed voice/style guidance.

### Step 5. Validate and Package

Run validation:
```bash
python scripts/validate_skill.py <skill-path>
```

Package for distribution:
```bash
python scripts/package_skill.py <skill-path>
```

### Step 6. Iterate

Test on real tasks. Note struggles. Update. Re-test.

## The Description Field

Write the description using this formula:
```
Use when [specific triggers] - [what it does, third person]
```

Checklist:
- Starts with "Use when..."
- Third person (not "you should")
- Includes specific symptoms/triggers
- Includes relevant keywords
- Under 1024 characters (ideal: 200-500)

See `references/description-patterns.md` for templates by skill type.

## Component Placement

| Content Type | Location |
|--------------|----------|
| Core workflow instructions | SKILL.md body |
| Detailed reference (>100 lines) | references/{topic}.md |
| Reusable, tested code | scripts/{name}.py |
| Templates, images for output | assets/{name}/ |
| Everything else | DON'T INCLUDE |

## Quick Validation

```bash
# Check frontmatter
head -20 SKILL.md

# Count lines (target: <500)
wc -l SKILL.md

# Find broken references
grep -o 'references/[^)]*' SKILL.md | while read f; do [ -f "$f" ] || echo "Missing: $f"; done
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Writing documentation instead of instructions | Rewrite in imperative voice: "Do X", not "X is..." |
| Copying code that exists elsewhere | Reference file paths instead |
| Description too vague | Add specific triggers and keywords |
| SKILL.md over 500 lines | Split into references/ |
| Untested scripts | Run scripts before packaging |

## Decision Frameworks

Before creating a skill, verify it's the right approach:

| Instead of Skill | Use When |
|------------------|----------|
| Slash command | User must trigger explicitly |
| MCP server | External API/service integration |
| Agent definition | Complex autonomous multi-step work |
| CLAUDE.md | Project-specific context |

**The 5-10 Rule**: Done 5+ times? Will do 10+ more? Create a skill.

See `references/decision-frameworks.md` for complete decision trees.

## References

### Foundational
- `references/what-are-skills.md` - Definitions and characteristics
- `references/core-philosophy.md` - Iron laws and content strategy
- `references/decision-frameworks.md` - All decision trees

### Creation Process
- `references/creation-approaches.md` - Manual vs automated vs hybrid
- `references/writing-skillmd.md` - Voice, style, structure guidelines
- `references/reference-dont-reproduce.md` - Code example strategy

### Components & Quality
- `references/description-patterns.md` - Templates by skill type
- `references/bundled-resources.md` - Scripts, references, assets
- `references/anti-patterns.md` - Common mistakes to avoid
- `references/testing.md` - TDD approach and validation
- `references/quick-reference.md` - Templates and size guidelines

## Scripts

- `scripts/init_skill.py` - Initialize new skill directory
- `scripts/validate_skill.py` - Validate skill before packaging
- `scripts/package_skill.py` - Package skill for distribution
