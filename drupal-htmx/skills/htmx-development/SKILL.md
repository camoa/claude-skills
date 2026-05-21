---
name: htmx-development
description: Use when implementing HTMX in Drupal, migrating from AJAX to HTMX, building dynamic forms, dependent dropdowns, infinite scroll, real-time validation, or multi-step wizards. Use when user says "HTMX", "migrate AJAX", "dependent dropdown", "dynamic form", "infinite scroll", "load more", "real-time validation", "multi-step wizard", "hx-get", "hx-post", "Htmx class". Use PROACTIVELY for any Drupal 11.3+ dynamic interaction that could use HTMX instead of AJAX. MUST check HTMX patterns before implementing AJAX callbacks.
version: 1.6.0
allowed-tools: Read, Glob, Grep
user-invocable: true
---

# HTMX Development

Drupal 11.3+ HTMX implementation and AJAX migration guidance.

## When to Use

- Implementing dynamic content updates in Drupal
- Building forms with dependent fields
- Migrating existing AJAX to HTMX
- Adding infinite scroll, load more, real-time validation
- NOT for: Traditional AJAX maintenance (use `references/ajax-reference.md`)

## Decision: HTMX vs AJAX

| Choose HTMX | Choose AJAX |
|-------------|-------------|
| New features | Existing AJAX code |
| Declarative HTML preferred | Complex command sequences |
| Returns HTML fragments | Dialog commands needed |
| Progressive enhancement needed | Contrib expects AJAX |

**Hybrid OK**: Both systems coexist. Migrate incrementally.

## Quick Start

Attach HTMX behavior to a render element with the `Htmx` class:

```php
use Drupal\Core\Htmx\Htmx;
use Drupal\Core\Url;

(new Htmx())
  ->get(Url::fromRoute('my.content'))
  ->onlyMainContent()
  ->target('#result')
  ->swap('innerHTML')
  ->applyTo($build['button']);
```

The controller returns a render array (`['#markup' => '...']`); add
`_htmx_route: TRUE` to the route's `options` for an always-minimal response.
Full setup — basic usage, route configuration, dual-purpose routes — is in
`references/htmx-implementation.md`.

## Core Patterns

### Pattern Selection

| Use Case | Pattern | Key Methods |
|----------|---------|-------------|
| Dependent dropdown | Form partial update | `select()`, `target()`, `swap('outerHTML')` |
| Load more | Append content | `swap('beforeend')`, `trigger('click')` |
| Infinite scroll | Auto-load | `swap('beforeend')`, `trigger('revealed')` |
| Real-time validation | Blur check | `trigger('focusout')`, field update |
| Multi-step wizard | URL-based steps | `pushUrl()`, route parameters |
| Multiple updates | OOB swap | `swapOob('outerHTML:#selector')` |

Each pattern has full before/after code in `references/migration-patterns.md`
(7 patterns) and `references/htmx-implementation.md` (dependent dropdowns, OOB
updates, URL history).

## Htmx Class Reference

- **Request**: `get()` / `post()` / `put()` / `patch()` / `delete()` (take a `Url`)
- **Control**: `target()`, `select()`, `swap()`, `swapOob()`, `trigger()`, `vals()`, `onlyMainContent()`
- **Response headers**: `pushUrlHeader()`, `redirectHeader()`, `triggerHeader()`, `reswapHeader()`, `retargetHeader()`
- **Apply**: `applyTo($element)` or `applyTo($element, '#wrapper_attributes')`

Complete method and header tables: `references/quick-reference.md`.

## Detecting HTMX Requests

Forms include `HtmxRequestInfoTrait` automatically; controllers add it manually:

```php
if ($this->isHtmxRequest()) {
  $trigger = $this->getHtmxTriggerName();
}
```

Controller setup and the full 8-method detection API are in
`references/htmx-implementation.md`.

## Migration from AJAX

1. Identify `#ajax` properties
2. Replace with the `Htmx` class
3. Move callback logic into `buildForm()`
4. Use `getHtmxTriggerName()` for conditional logic
5. Replace `AjaxResponse` with render arrays
6. Test progressive enhancement

The FAPI quick map (`#ajax` → `Htmx` equivalents), command-level mappings, and
7 detailed before/after patterns are in `references/migration-patterns.md` and
`references/quick-reference.md`.

## Validation Checklist

When reviewing HTMX implementations:

- [ ] `Htmx` class used (not raw attributes)
- [ ] `onlyMainContent()` for minimal response
- [ ] Proper swap strategy selected
- [ ] OOB used for multiple updates
- [ ] Trigger element detection works
- [ ] Works without JavaScript (progressive)
- [ ] Accessibility: `aria-live` for dynamic regions
- [ ] URL updates for bookmarkable states

## Common Issues

| Problem | Solution |
|---------|----------|
| Content not swapping | Check `target()` selector exists |
| Wrong content extracted | Check `select()` selector |
| JS not running | Verify `htmx:drupal:load` fires |
| Form not submitting | Check `post()` and URL |
| Multiple swaps fail | Add `swapOob('true')` to elements |
| History broken | Use `pushUrlHeader()` |

Extended troubleshooting: `references/htmx-implementation.md`.

## References

### Bundled (HTMX-Specific)
- `references/quick-reference.md` — command equivalents, method/header tables
- `references/htmx-implementation.md` — full Htmx class API, detection, routes, JS
- `references/migration-patterns.md` — 7 patterns with before/after code, FAPI quick map
- `references/ajax-reference.md` — AJAX commands for understanding existing code

### Online Dev-Guides

For deeper Drupal context beyond bundled references, invoke
`/dev-guides-navigator` with keywords like "Drupal forms", "routing", "JS
development", or "render API". The navigator handles caching and disambiguation
— never fetch dev-guides URLs directly. Relevant topics: drupal/forms,
drupal/routing, drupal/js-development, drupal/render-api.

## Key Files in Drupal Core

- `core/lib/Drupal/Core/Htmx/Htmx.php` — Main API
- `core/lib/Drupal/Core/Htmx/HtmxRequestInfoTrait.php` — Request detection
- `core/lib/Drupal/Core/Render/MainContent/HtmxRenderer.php` — Response renderer
- `core/modules/config/src/Form/ConfigSingleExportForm.php` — Production example
- `core/modules/system/tests/modules/test_htmx/` — Test examples
