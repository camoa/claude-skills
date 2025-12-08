# Bundled Resources Guide

When to use scripts, references, and assets in skills.

## Component Overview

| Component | Purpose | Loaded Into Context? |
|-----------|---------|---------------------|
| **SKILL.md** | Core instructions, workflows | Yes, when triggered |
| **scripts/** | Executable code for deterministic tasks | No (executed directly) |
| **references/** | Documentation Claude reads as needed | Yes, on demand |
| **assets/** | Files used in output (templates, images) | No (used in output) |

## Scripts (`scripts/`)

Executable code for tasks requiring deterministic reliability.

### When to Include
- Same code being rewritten repeatedly
- Deterministic reliability needed
- Complex operations better as tested, versioned code

### Key Benefit
Scripts can be **executed without loading into context** - massive token savings.

### Examples
```
scripts/
├── rotate_pdf.py      # PDF rotation utility
├── fill_form.py       # Form field filling
├── validate.sh        # Validation script
└── bulk_process.py    # Batch operations
```

### Best Practices
- Test scripts by actually running them
- Include shebang (`#!/usr/bin/env python3`)
- Document dependencies at top of file
- Handle errors with meaningful messages
- Scripts may still need reading for patching

## References (`references/`)

Documentation loaded into context **as needed**.

### When to Include
- Detailed documentation too long for SKILL.md
- Domain-specific details (only load when relevant)
- Schemas, API docs, company policies
- Detailed workflow guides

### Key Benefit
Keeps SKILL.md lean; loaded **only when Claude determines it's needed**.

### Examples
```
references/
├── api-reference.md   # Full API documentation
├── field-types.md     # Supported types and formats
├── troubleshooting.md # Common issues and solutions
└── advanced.md        # Advanced techniques
```

### Best Practices
- Keep references **one level deep** (no nested references)
- Include table of contents for files >100 lines
- Link from SKILL.md: "See references/file.md for..."
- For files >10k words, include grep patterns in SKILL.md
- Info lives in SKILL.md OR references, not both

## Assets (`assets/`)

Files **NOT loaded into context** but used in output.

### When to Include
- Templates that get copied/modified
- Images, logos, icons
- Boilerplate code projects
- Fonts, sample documents

### Key Benefit
Separates output resources from documentation; Claude uses files **without reading them**.

### Examples
```
assets/
├── templates/
│   ├── report.docx
│   └── presentation.pptx
├── logos/
│   └── company-logo.png
└── boilerplate/
    └── react-component/
```

## Decision Tree

```
Is this content...

├─ Core workflow Claude must know?
│  └─ SKILL.md body
│
├─ Detailed reference loaded on demand?
│  └─ references/{topic}.md
│
├─ Reusable, tested code?
│  └─ scripts/{name}.py
│
├─ File used in output (template, image)?
│  └─ assets/{name}/
│
└─ None of the above?
   └─ DON'T INCLUDE IT
```

## Progressive Disclosure

| Level | Content | When Loaded |
|-------|---------|-------------|
| 1 | Metadata (name + description) ~100 tokens | Always |
| 2 | SKILL.md body <5k tokens | When triggered |
| 3 | Bundled resources (unlimited) | On demand |

**Key rule**: Keep SKILL.md under 500 lines. Split into references/ if larger.

## What NOT to Include

| Don't Include | Why |
|---------------|-----|
| README.md | Use SKILL.md instead |
| INSTALLATION_GUIDE.md | Not for AI execution |
| CHANGELOG.md | Historical clutter |
| Duplicate information | Violates DRY |
| User-facing docs | Skills are for AI |
