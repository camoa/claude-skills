# HTMX Implementation Guide

Drupal 11.3+ native HTMX support reference.

## Core Architecture

### Key Files
- `core/lib/Drupal/Core/Htmx/Htmx.php` - Main API (30+ attribute methods, 11 header methods)
- `core/lib/Drupal/Core/Htmx/HtmxRequestInfoTrait.php` - Request detection (8 methods)
- `core/lib/Drupal/Core/Render/MainContent/HtmxRenderer.php` - Minimal HTML renderer
- `core/misc/htmx/htmx-assets.js` - Asset loading, settings merging
- `core/misc/htmx/htmx-behaviors.js` - Drupal behaviors integration

### Request/Response Flow
1. User interacts with HTMX element
2. JS adds `_wrapper_format`, `ajax_page_state`, triggering element
3. Server routes to controller/form, detects HTMX request
4. Controller returns render array with HTMX headers
5. HtmxRenderer creates minimal HTML response
6. JS loads new CSS/JS assets
7. HTMX swaps content
8. Drupal behaviors attach (`htmx:drupal:load`)

## The Htmx Class

### Basic Usage
```php
use Drupal\Core\Htmx\Htmx;
use Drupal\Core\Url;

$htmx = new Htmx();
$htmx->post(Url::fromRoute('my.route'))
  ->onlyMainContent()
  ->target('#result')
  ->swap('innerHTML')
  ->applyTo($element);
```

### Request Attributes

```php
$htmx->get(Url::fromRoute('my.get'));     // GET request
$htmx->post(Url::fromRoute('my.post'));   // POST request
$htmx->put(Url::fromRoute('my.put'));     // PUT request
$htmx->patch(Url::fromRoute('my.patch')); // PATCH request
$htmx->delete(Url::fromRoute('my.del'));  // DELETE request
```

### Control Attributes

```php
$htmx->target('#element-id');        // Where to swap content
$htmx->select('.content-class');     // What to extract from response
$htmx->swap('outerHTML');            // How to swap (default ignoreTitle:true)
$htmx->swap('beforeend', 'scroll:bottom'); // With modifiers
$htmx->swapOob('true');              // Mark for out-of-band swap
$htmx->swapOob('outerHTML:#other');  // OOB with selector
$htmx->trigger('click');             // Trigger event
$htmx->trigger(['load', 'revealed']); // Multiple triggers
$htmx->vals(['key' => 'value']);     // Additional values as JSON
$htmx->onlyMainContent();            // Request minimal response
```

### Response Headers

```php
$htmx->pushUrlHeader(Url::fromRoute('my.route')); // Push to history
$htmx->replaceUrlHeader($url);        // Replace current URL
$htmx->redirectHeader($url);          // Full page redirect
$htmx->refreshHeader(true);           // Force page refresh
$htmx->reswapHeader('innerHTML');     // Change swap strategy
$htmx->retargetHeader('#new-target'); // Change target
$htmx->reselectHeader('.new-select'); // Change content selector
$htmx->triggerHeader('eventName');    // Fire client event
$htmx->triggerHeader(['event' => ['data' => 'value']]); // With data
$htmx->triggerAfterSwapHeader('event'); // After swap completes
$htmx->triggerAfterSettleHeader('event'); // After settle
```

### Additional Attributes

```php
$htmx->boost(true);           // Progressive enhancement
$htmx->confirm('Are you sure?'); // Confirmation dialog
$htmx->indicator('#spinner'); // Loading indicator
$htmx->include('#other-form'); // Include additional elements
$htmx->pushUrl(true);         // Push URL attribute
$htmx->preserve();            // Keep element unchanged
$htmx->validate(true);        // Validate before submit
$htmx->on('::afterSwap', 'myHandler()'); // Event handler
```

### Applying to Elements

```php
// Apply to #attributes
$htmx->applyTo($form['element']);

// Apply to specific attribute key
$htmx->applyTo($form['element'], '#wrapper_attributes');

// Apply headers to entire form
$htmx->pushUrlHeader($url)->applyTo($form);
```

## Detecting HTMX Requests

### In Forms (HtmxRequestInfoTrait included)

```php
class MyForm extends FormBase {
  public function buildForm(array $form, FormStateInterface $form_state) {
    if ($this->isHtmxRequest()) {
      $trigger = $this->getHtmxTriggerName();
      if ($trigger === 'category') {
        // Handle category change
      }
    }
  }
}
```

### In Controllers

```php
use Drupal\Core\Htmx\HtmxRequestInfoTrait;

class MyController extends ControllerBase {
  use HtmxRequestInfoTrait;

  protected function getRequest() {
    return \Drupal::request();
  }

  public function content() {
    if ($this->isHtmxRequest()) {
      // Return partial content
    }
  }
}
```

### Available Methods

| Method | Purpose |
|--------|---------|
| `isHtmxRequest()` | TRUE if HX-Request header present |
| `isHtmxBoosted()` | TRUE if HX-Boosted header present |
| `getHtmxCurrentUrl()` | Current page URL |
| `isHtmxHistoryRestoration()` | History restore request |
| `getHtmxPrompt()` | Prompt value if set |
| `getHtmxTarget()` | Target element ID |
| `getHtmxTrigger()` | Triggering element ID |
| `getHtmxTriggerName()` | Triggering element name |

## Route Configuration

### HTMX-Only Route
```yaml
my_module.htmx_content:
  path: '/my-module/htmx-content'
  defaults:
    _controller: '\Drupal\my_module\Controller\MyController::content'
  options:
    _htmx_route: TRUE
```

### Dual-Purpose Route
```php
// Use onlyMainContent() instead - adds ?_wrapper_format=drupal_htmx
$htmx->onlyMainContent()->applyTo($element);
```

## Form Patterns

### Dependent Dropdowns
Reference: `core/modules/config/src/Form/ConfigSingleExportForm.php`

```php
public function buildForm(array $form, FormStateInterface $form_state) {
  $form_url = Url::fromRoute('<current>');

  $form['category'] = [
    '#type' => 'select',
    '#options' => $this->getCategories(),
  ];

  (new Htmx())
    ->post($form_url)
    ->onlyMainContent()
    ->select('#edit-subcategory--wrapper')
    ->target('#edit-subcategory--wrapper')
    ->swap('outerHTML')
    ->applyTo($form['category']);

  $form['subcategory'] = [
    '#type' => 'select',
    '#options' => $this->getSubcategories($form_state->getValue('category')),
  ];

  return $form;
}
```

### OOB Updates for Multiple Elements
```php
// When category changes, also clear export
$trigger = $this->getHtmxTriggerName();
if ($trigger === 'category') {
  (new Htmx())
    ->swapOob('outerHTML:[data-export-wrapper]')
    ->applyTo($form['export'], '#wrapper_attributes');
}
```

### Auto form_build_id Updates
FormBuilder automatically updates form_build_id via OOB swap during HTMX requests. No action needed.

Reference: `core/lib/Drupal/Core/Form/FormBuilder.php:782-790`

## JavaScript Integration

### Drupal Behaviors
```javascript
Drupal.behaviors.myBehavior = {
  attach(context, settings) {
    // context = HTMX-swapped element
  },
  detach(context, settings, trigger) {
    // trigger = 'unload' for HTMX removals
  }
};
```

### HTMX Events
```javascript
htmx.on('htmx:beforeRequest', (e) => console.log('Request', e.detail));
htmx.on('htmx:afterSwap', (e) => console.log('Swapped', e.detail));
htmx.on('htmx:drupal:load', (e) => console.log('Behaviors attached'));
```

### Triggering Custom Events
```php
// Server-side
$htmx->triggerHeader(['showNotification' => ['msg' => 'Saved!']]);

// Client-side
htmx.on('showNotification', (e) => alert(e.detail.msg));
```

## Best Practices

### Progressive Enhancement
- Forms should POST normally without JavaScript
- Use semantic HTML, add HTMX attributes
- Test with JavaScript disabled

### Performance
- Use `onlyMainContent()` for minimal responses
- Drupal sends only new CSS/JS (via ajax_page_state)
- Configure proper cache contexts on render arrays

### Accessibility
- Status messages auto-included via HtmxRenderer
- Add `aria-live` regions for dynamic content
- Use `Drupal.announce()` via trigger headers

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Attributes not working | Verify `core/drupal.htmx` library attached |
| Content not swapping | Check target/select selectors exist |
| JS not executing | Ensure behaviors implement `attach` |
| Form not submitting | Verify `post()` and form URL routing |
| Multiple swaps failing | Use `swapOob('true')` on response elements |
| History not updating | Use `pushUrlHeader()` |
