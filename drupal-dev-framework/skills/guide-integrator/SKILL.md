---
name: guide-integrator
description: Use when designing features - loads plugin methodology refs, fetches online dev-guides for Drupal domain knowledge, and optionally loads user's custom guides
version: 3.0.0
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

## Online Dev-Guides (Drupal Domain)

Decision guides at `https://camoa.github.io/dev-guides/`. WebFetch the topic index, then fetch the specific atomic guide needed.

| Keywords Detected | Topic URL |
|-------------------|-----------|
| "form", "validation", "form alter" | `drupal/forms/` |
| "config form", "settings form", "ConfigFormBase" | `drupal/config-forms/` |
| "entity", "field", "content type", "bundle" | `drupal/entities/` |
| "plugin", "plugin type", "annotation", "attribute" | `drupal/plugins/` |
| "route", "access check", "permission", "controller" | `drupal/routing/` |
| "service", "dependency injection", "container" | `drupal/services/` |
| "cache", "cache tag", "cache context", "max-age" | `drupal/caching/` |
| "config", "config schema", "config entity" | `drupal/config-management/` |
| "render", "render array", "#theme", "lazy builder" | `drupal/render-api/` |
| "security", "XSS", "SQL injection", "CSRF" | `drupal/security/` |
| "SDC", "component", "single directory" | `drupal/sdc/` |
| "JavaScript", "behaviors", "once", "library" | `drupal/js-development/` |
| "view", "views", "display", "filter" | `drupal/views/` |
| "block", "block plugin", "block type" | `drupal/blocks/` |
| "layout builder", "section", "inline block" | `drupal/layout-builder/` |
| "migration", "migrate", "D7 to D11" | `drupal/migration/` |
| "recipe", "config action" | `drupal/recipes/` |
| "taxonomy", "vocabulary", "term" | `drupal/taxonomy/` |
| "media", "media type", "oembed" | `drupal/media/` |
| "image style", "responsive image" | `drupal/image-styles/` |
| "test", "PHPUnit", "kernel test" | `drupal/testing/` |
| "JSON:API", "jsonapi", "REST" | `drupal/jsonapi/` |
| "icon", "icon pack", "icon API" | `drupal/icon-api/` |
| "ECA", "event condition action" | `drupal/eca/` |
| "GitHub Actions", "CI/CD" | `drupal/github-actions/` |
| "CSS", "SCSS", "BEM", "Bootstrap" | `design-systems/bootstrap/` |
| "Radix", "sub-theme" | `design-systems/radix-sdc/` |

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

### 2. Fetch Online Dev-Guides (Drupal Domain)

For Drupal-specific architecture decisions:
1. Match task keywords to the Online Dev-Guides table
2. WebFetch `https://camoa.github.io/dev-guides/{topic_url}` for the topic index
3. Identify the specific atomic guide from the index
4. WebFetch that atomic guide for the decision pattern

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
