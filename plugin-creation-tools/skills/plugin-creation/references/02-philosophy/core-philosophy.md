# Core Philosophy

Unified philosophy combining Anthropic's skill-creator principles with the guide-framework-maintainer approach.

## The Iron Laws

1. **Claude is already very smart** - Only add context Claude doesn't already have
2. **Reference, don't reproduce** - Point to source files, don't copy implementations
3. **Decision-focused, not tutorial-focused** - "When to use X vs Y" not "How to install X"
4. **One excellent example beats many mediocre ones** - Quality over quantity
5. **Context window is a public good** - Every token must justify its cost
6. **Documentation reflects current truth** - Docs describe what IS, not how we got here

## Content Strategy

| PRESERVE | REMOVE |
|----------|--------|
| Decision criteria ("when to use X vs Y") | Step-by-step tutorials |
| Performance guidelines with thresholds | Verbose installation instructions |
| When-to-use scenarios | Historical explanations |
| Integration patterns | Version change narratives |
| Brief code snippets for pattern recognition | Redundant code blocks |
| File path references to implementations | Full code reproductions |

## Degrees of Freedom

Match specificity to task fragility:

| Freedom Level | When to Use | How to Document |
|---------------|-------------|-----------------|
| **High** | Multiple approaches valid, context-dependent | Text-based instructions, heuristics |
| **Medium** | Preferred pattern exists, some variation OK | Pseudocode or scripts with parameters |
| **Low** | Operations fragile, consistency critical | Specific scripts, exact sequences |

Think of Claude as exploring a path: a narrow bridge with cliffs needs specific guardrails (low freedom), while an open field allows many routes (high freedom).

### Examples by Freedom Level

**High Freedom** (guidelines only):
```markdown
## Writing Style
Use clear, concise language. Prefer active voice.
Adapt tone to the audience and context.
```

**Medium Freedom** (pattern with flexibility):
```markdown
## API Integration Pattern
1. Authenticate with token
2. Make request with appropriate method
3. Handle response/errors

See scripts/api_template.py for base implementation.
Customize headers and endpoints as needed.
```

**Low Freedom** (exact script):
```markdown
## PDF Form Filling
Run exactly:
python scripts/fill_form.py --input form.pdf --data fields.json --output filled.pdf

Do not modify the script without testing.
```

## The DRY Principle

- Information lives in ONE place only
- SKILL.md OR references, never both
- Cross-reference between files, don't duplicate
- If it's in official docs, link to it

### Applying DRY

| Situation | Action |
|-----------|--------|
| Same info needed in SKILL.md and reference | Put in one place, link from other |
| Official docs cover the topic | Link to docs, add only unique context |
| Multiple skills need same info | Create shared reference, link from both |
| Code exists in codebase | Reference file path, don't copy |

## Challenge Every Token

Before including content, ask:

1. **Does Claude already know this?** → Remove if yes
2. **Can I reference instead of reproduce?** → Reference if possible
3. **Is this decision-focused or tutorial-focused?** → Keep only decisions
4. **Is one example enough?** → Remove extras
5. **Does this justify its token cost?** → Remove if doubtful

## Lean Documentation

Documentation must reflect the current state of the system, not its history.

### Principles

- **Replace, don't append**: When content is superseded, remove the old version entirely. Do not keep both old and new alongside each other.
- **Delete irrelevant content**: Every doc edit is an opportunity to prune. If surrounding content no longer applies, remove it during the same edit.
- **Current state only**: Document what the system does now. No historical narratives about how it evolved, no version migration stories, no changelogs embedded in reference docs.
- **No "Previously..." or "In v1.x..." language**: If a reader needs history, that belongs in git history or a dedicated changelog file, not in reference documentation.

### Applying Lean Documentation

| Situation | Action |
|-----------|--------|
| New version replaces old behavior | Rewrite the section to describe current behavior only |
| Feature removed | Delete the section entirely |
| Two docs describe the same thing differently | Pick the correct one, delete the other |
| Doc mentions old versions for context | Remove version references, describe current state |
| Section is half-outdated | Rewrite fully or delete, never leave partial truths |

### Why This Matters

Stale documentation is worse than no documentation. It teaches Claude wrong patterns, wastes context tokens on irrelevant history, and creates confusion about what is actually true. Keeping docs lean and current is not just style preference; it directly impacts Claude's ability to help effectively.

## Summary

The core philosophy is: **Minimum viable context for maximum effectiveness**.

Skills succeed when they provide only what Claude needs, exactly when Claude needs it, in the most token-efficient form possible.
