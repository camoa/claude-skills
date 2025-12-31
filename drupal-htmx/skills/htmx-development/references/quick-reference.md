# Quick Reference

## AJAX to HTMX Command Equivalents

| AJAX Command | HTMX Equivalent | Notes |
|--------------|-----------------|-------|
| `ReplaceCommand` | `swap('outerHTML')` | Replace entire element |
| `HtmlCommand` | `swap('innerHTML')` | Replace inner content |
| `AppendCommand` | `swap('beforeend')` | Append inside element |
| `PrependCommand` | `swap('afterbegin')` | Prepend inside element |
| `BeforeCommand` | `swap('beforebegin')` | Insert before element |
| `AfterCommand` | `swap('afterend')` | Insert after element |
| `RemoveCommand` | Empty + `swap('outerHTML')` | Remove element |
| `RedirectCommand` | `redirectHeader(Url)` | Full page redirect |
| `MessageCommand` | Auto-included | Via HtmxRenderer |
| `SettingsCommand` | Auto-merged | Via htmx-assets.js |
| Multiple commands | `swapOob()` | Out-of-band swaps |

## Htmx Class Methods

### Request Methods
| Method | Result |
|--------|--------|
| `get(Url)` | `data-hx-get` |
| `post(Url)` | `data-hx-post` |
| `put(Url)` | `data-hx-put` |
| `patch(Url)` | `data-hx-patch` |
| `delete(Url)` | `data-hx-delete` |

### Control Methods
| Method | Result | Purpose |
|--------|--------|---------|
| `target(selector)` | `data-hx-target` | Where to swap |
| `select(selector)` | `data-hx-select` | What to extract from response |
| `swap(strategy)` | `data-hx-swap` | How to swap |
| `swapOob(true\|selector)` | `data-hx-swap-oob` | Out-of-band updates |
| `trigger(event)` | `data-hx-trigger` | When to trigger |
| `vals(array)` | `data-hx-vals` | Additional values as JSON |
| `onlyMainContent()` | Adds `_wrapper_format` | Minimal response |

### Response Headers
| Method | Header | Purpose |
|--------|--------|---------|
| `pushUrlHeader(Url)` | `HX-Push-Url` | Update browser URL |
| `redirectHeader(Url)` | `HX-Redirect` | Full page redirect |
| `triggerHeader(event)` | `HX-Trigger` | Fire client event |
| `reswapHeader(strategy)` | `HX-Reswap` | Change swap strategy |
| `retargetHeader(selector)` | `HX-Retarget` | Change target |

## Swap Strategies

| Strategy | Description |
|----------|-------------|
| `innerHTML` | Replace inner content (default) |
| `outerHTML` | Replace entire element |
| `beforebegin` | Insert before element |
| `afterbegin` | Prepend inside element |
| `beforeend` | Append inside element |
| `afterend` | Insert after element |
| `delete` | Remove element |
| `none` | No swap (headers only) |

## Common Patterns

### Dependent Dropdown
```php
(new Htmx())
  ->post($form_url)
  ->onlyMainContent()
  ->select('#subcategory-wrapper')
  ->target('#subcategory-wrapper')
  ->swap('outerHTML')
  ->applyTo($form['category']);
```

### Load More / Infinite Scroll
```php
(new Htmx())
  ->get(Url::fromRoute('my.items', ['page' => $next]))
  ->trigger('revealed')  // or 'click'
  ->select('.item-list')
  ->target('#content-list')
  ->swap('beforeend')
  ->applyTo($element);
```

### Multiple Element Updates (OOB)
```php
// Primary target updates normally
// Secondary element uses OOB
(new Htmx())
  ->swapOob('outerHTML:[data-export-wrapper]')
  ->applyTo($form['export'], '#wrapper_attributes');
```

### URL History Update
```php
(new Htmx())
  ->pushUrlHeader(Url::fromRoute('my.route', $params))
  ->applyTo($form);
```

## Detection Methods (HtmxRequestInfoTrait)

Available in `FormBase` and any class using the trait:

| Method | Returns |
|--------|---------|
| `isHtmxRequest()` | TRUE if HX-Request header present |
| `getHtmxTriggerName()` | Triggering element name |
| `getHtmxTarget()` | Target element ID |
| `getHtmxCurrentUrl()` | Current page URL |

## Route Configuration

```yaml
# Always returns minimal HTML
my_module.htmx_endpoint:
  path: '/my-module/htmx-content'
  options:
    _htmx_route: TRUE
```

## JavaScript Events

| Event | When |
|-------|------|
| `htmx:drupal:load` | After swap + assets loaded |
| `htmx:drupal:unload` | Before content removal |
| `htmx:beforeRequest` | Before AJAX request |
| `htmx:afterSwap` | After content swapped |

## Decision: HTMX vs AJAX

| Use HTMX | Use AJAX |
|----------|----------|
| New features | Maintaining existing AJAX |
| Declarative HTML preferred | Complex command sequences |
| Returns HTML | Heavy JS processing |
| Progressive enhancement important | Contrib expects AJAX callbacks |
