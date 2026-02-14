---
name: guide-loader
description: Use when needing specialized guide content - loads from user's configured path or fetches from online dev-guides based on task keywords
version: 2.0.0
model: haiku
user-invocable: false
---

# Guide Loader

Load development guides into context when needed. Two sources: user's local guides path, or online dev-guides via WebFetch.

## Activation

Activate when:
- Designing or implementing features that match guide topics
- User requests a specific guide
- Invoked by other skills (guide-integrator, task-context-loader)
- "Load the ECA guide" or "What does my guide say about..."

## Workflow

### 1. Check for Local Guides Path

Read `{project_path}/project_state.md` and look for:
```markdown
**Guides Path:** {path}
```

If found, go to Step 2a (local). If not found, go to Step 2b (online).

### 2a. Load from Local Path

If specific guide requested, use that filename. Otherwise, match topic to guide:

| Topic Keywords | Guide File |
|----------------|------------|
| ECA, event, workflow, automation | eca_development_guide.md |
| field, entity, bundle, content type | drupal_fields_entities_guide.md |
| form, settings, config, admin | drupal_configuration_forms_guide.md |
| theme, CSS, SCSS, Bootstrap | bootstrap_*.md |
| SDC, component, Twig | sdc_*.md |
| Radix, subtheme | radix_*.md |
| development, workflow, process | drupal_development_guide.md |

Read `{guides_path}/{guide_file}`. If not found, fall back to Step 2b (online).

### 2b. Fetch from Online Dev-Guides

WebFetch from `https://camoa.github.io/dev-guides/` based on topic keywords:

| Topic Keywords | Dev-Guides URL |
|----------------|----------------|
| form, validation, form alter | `drupal/forms/` |
| config form, settings form | `drupal/config-forms/` |
| entity, field, content type | `drupal/entities/` |
| plugin, plugin type, annotation | `drupal/plugins/` |
| route, access, permission | `drupal/routing/` |
| service, dependency injection | `drupal/services/` |
| cache, cache tag, cache context | `drupal/caching/` |
| config, config schema | `drupal/config-management/` |
| render, render array, #theme | `drupal/render-api/` |
| security, XSS, SQL injection | `drupal/security/` |
| SDC, component, single directory | `drupal/sdc/` |
| JavaScript, behaviors, once | `drupal/js-development/` |
| views, display, filter | `drupal/views/` |
| block, block plugin | `drupal/blocks/` |
| layout builder, section | `drupal/layout-builder/` |
| migration, migrate, D7 | `drupal/migration/` |
| recipe, config action | `drupal/recipes/` |
| taxonomy, vocabulary, term | `drupal/taxonomy/` |
| media, media type, oembed | `drupal/media/` |
| image style, responsive image | `drupal/image-styles/` |
| test, PHPUnit, kernel test | `drupal/testing/` |
| JSON:API, jsonapi, REST | `drupal/jsonapi/` |
| icon, icon pack | `drupal/icon-api/` |
| ECA, event condition action | `drupal/eca/` |
| GitHub Actions, CI/CD | `drupal/github-actions/` |
| CSS, SCSS, BEM, Bootstrap | `design-systems/bootstrap/` |
| Radix, sub-theme | `design-systems/radix-sdc/` |

Steps:
1. WebFetch `https://camoa.github.io/dev-guides/{topic_url}` for the topic index
2. Identify the specific atomic guide from the index
3. WebFetch that atomic guide URL

### 3. Present Guide Content

Format as:
```
## Guide Loaded: {guide name}

### Source
{Local: path | Online: URL}

### Relevant Sections for Current Task
1. **{Section Name}** - {why relevant}
   {Key points}

### Key Patterns
- {Pattern 1}
- {Pattern 2}

### Warnings
- {Important gotcha from guide}
```

### 4. Integrate with Current Work

Based on guide content, suggest:
```
Apply to current task:
- {Specific recommendation from guide}
- {Pattern to follow}
- {Thing to avoid}

Add these to architecture/implementation? (yes/no)
```

## Stop Points

STOP and wait for user:
- If requested guide not found locally or online
- After presenting guide content (ask if need more)
