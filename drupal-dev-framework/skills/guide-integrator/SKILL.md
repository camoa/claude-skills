---
name: guide-integrator
description: Use when designing features - loads plugin methodology refs, fetches online dev-guides for Drupal domain knowledge, and optionally loads user's custom guides
version: 3.1.0
user-invocable: false
---

# Guide Integrator

Load development references and integrate into architecture documents. Three sources: plugin methodology refs, online dev-guides, and user's custom guides.

## Built-in References (Methodology)

| Topic | Reference File |
|-------|----------------|
| Test-Driven Development | `references/tdd-workflow.md` |
| SOLID Principles | `references/solid-drupal.md` |
| DRY Patterns | `references/dry-patterns.md` |
| Library-First/CLI-First | `references/library-first.md` |
| Quality Gates | `references/quality-gates.md` |
| Purposeful Code | `references/purposeful-code.md` |

## Online Dev-Guides

For Drupal domain knowledge beyond bundled references, fetch the guide index:

**Index:** `https://camoa.github.io/dev-guides/llms.txt`

Likely relevant topics: forms, config-forms, entities, plugins, routing, services, caching, config-management, render-api, security, sdc, js-development, views, blocks, layout-builder, media, migration, recipes, taxonomy, jsonapi, image-styles, icon-api, eca, github-actions, ai-content, custom-field, klaro, testing, tdd, solid-principles, dry-principles

Usage: WebFetch the index to discover available topics, then fetch specific topic pages for decision guides, patterns, and best practices.

## Activation

Activate when:
- Designing features that match reference topics
- User mentions specific patterns (TDD, SOLID, DRY)
- Architecture drafting for any feature
- Auto-triggered by `architecture-drafter` agent

## Auto-Load Rules

### Plugin References (Methodology)

Loaded from plugin's `references/` folder:

| Keywords Detected | Reference to Load |
|-------------------|-------------------|
| "test", "TDD", "unit test", "kernel test" | `references/tdd-workflow.md` |
| "service", "dependency", "inject", "SOLID" | `references/solid-drupal.md` |
| "duplicate", "reuse", "DRY", "extract" | `references/dry-patterns.md` |
| "form", "drush", "command", "service first" | `references/library-first.md` |
| "complete", "done", "quality", "gate" | `references/quality-gates.md` |

### User's Custom Guides (Optional)

If user has configured a `guides_path` in `project_state.md`, search the configured path for relevant files based on keywords in filenames.

## Workflow

### 1. Load Plugin References (Methodology)

Based on detected keywords in the task:
1. Identify which methodology references apply (see Auto-Load Rules)
2. Read each applicable reference file
3. Extract patterns relevant to current task

### 2. Fetch Online Dev-Guides

For Drupal-specific architecture decisions:
1. WebFetch `https://camoa.github.io/dev-guides/llms.txt` to discover available topics
2. Match task keywords against the topic list and the likely relevant topics hint
3. WebFetch the relevant topic page for the decision guide index
4. WebFetch specific atomic guides for patterns and best practices

Only fetch topics relevant to the current task — not all topics.

### 3. Check for Custom Guides (Optional)

Read `{project_path}/project_state.md` and look for `**Guides Path:** {path}`.

If configured: Glob `{guides_path}/*.md`, match filenames to task keywords, load matches.
If not configured: continue with plugin refs and dev-guides only.

### 4. Extract Applicable Patterns

From all loaded sources, identify:
- Patterns that apply to current feature
- Checklists to follow
- Warnings or anti-patterns
- Recommended approaches

### 5. Add to Architecture

Use `Edit` to add references section to architecture file:

```markdown
## Development References

### Plugin References (Methodology)
| Reference | Key Patterns |
|-----------|--------------|
| solid-drupal.md | Single responsibility, DI |
| library-first.md | Service → Form → Route |
| tdd-workflow.md | Red-Green-Refactor |

### Dev-Guides Applied (Drupal Domain)
| Topic | Key Decisions |
|-------|--------------|
| drupal/forms/ | ConfigFormBase vs FormBase |
| drupal/entities/ | Content entity vs config entity |

### Custom Guides Applied (if any)
| Guide | Relevant Sections |
|-------|-------------------|
| {user_guide}.md | {sections} |

### Enforcement Points
| Phase | Principle | Source |
|-------|-----------|--------|
| Design | Library-First | references/library-first.md |
| Design | SOLID | references/solid-drupal.md |
| Design | Drupal patterns | dev-guides (online) |
| Implement | TDD | references/tdd-workflow.md |
| Implement | DRY | references/dry-patterns.md |
| Complete | Quality Gates | references/quality-gates.md |
| Complete | Security | dev-guides drupal/security/ |
```

### 6. Summarize

Tell user what was integrated from each source: plugin methodology, dev-guides topics, and custom guides.

## Reference Locations

| Type | Location |
|------|----------|
| Plugin references (methodology) | `{plugin_path}/references/*.md` |
| Dev-guides (Drupal domain) | `https://camoa.github.io/dev-guides/` |
| Custom guides | User-configured `guides_path` |

## Stop Points

STOP and ask user:
- If multiple custom guides could apply (ask which to prioritize)
- If custom guide path is configured but no files found
- Before adding patterns that conflict with existing architecture
