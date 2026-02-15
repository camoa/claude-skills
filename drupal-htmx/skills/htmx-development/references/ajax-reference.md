# AJAX Reference

Drupal AJAX system reference for understanding existing patterns before migration.

> **Online Dev-Guides:** For comprehensive Drupal AJAX architecture, security patterns, and JS integration beyond this migration-focused reference, see https://camoa.github.io/dev-guides/drupal/forms/ajax-architecture/ and https://camoa.github.io/dev-guides/drupal/js-development/ajax-integration/.

## AJAX Configuration

### Form Element AJAX Settings

```php
$form['element'] = [
  '#type' => 'select',
  '#ajax' => [
    'callback' => '::ajaxCallback',      // Required: PHP callback
    'wrapper' => 'target-wrapper',        // Target element ID
    'method' => 'replaceWith',            // jQuery method
    'effect' => 'fade',                   // Animation
    'event' => 'change',                  // Trigger event
    'progress' => [
      'type' => 'throbber',               // throbber, bar, fullscreen
      'message' => t('Loading...'),
    ],
  ],
];
```

### Common #ajax Properties

| Property | Purpose | Values |
|----------|---------|--------|
| `callback` | PHP method | `'::method'` or `[class, 'method']` |
| `wrapper` | Target ID | HTML ID without `#` |
| `method` | Insert method | `replaceWith`, `html`, `append`, `prepend`, `before`, `after` |
| `event` | Trigger event | `change`, `click`, `keyup`, `focusout` |
| `effect` | Animation | `fade`, `slide`, `none` |
| `progress` | Indicator | `['type' => 'throbber']` |

## AJAX Commands

### Content Manipulation

| Command | Purpose | HTMX Equivalent |
|---------|---------|-----------------|
| `ReplaceCommand('#sel', $content)` | Replace element | `swap('outerHTML')` |
| `HtmlCommand('#sel', $content)` | Replace inner HTML | `swap('innerHTML')` |
| `AppendCommand('#sel', $content)` | Append inside | `swap('beforeend')` |
| `PrependCommand('#sel', $content)` | Prepend inside | `swap('afterbegin')` |
| `BeforeCommand('#sel', $content)` | Insert before | `swap('beforebegin')` |
| `AfterCommand('#sel', $content)` | Insert after | `swap('afterend')` |
| `RemoveCommand('#sel')` | Remove element | Empty + `swap('outerHTML')` |
| `InsertCommand('#sel', $content)` | Generic insert | Various swaps |

### CSS and Styling

| Command | Purpose | Notes |
|---------|---------|-------|
| `CssCommand('#sel', ['prop' => 'val'])` | Set CSS | No direct HTMX equivalent |
| `AddCssCommand($library)` | Add CSS | Auto-handled by HTMX |
| `InvokeCommand('#sel', 'method', $args)` | jQuery method | Use JS events |

### Dialog Commands

| Command | Purpose |
|---------|---------|
| `OpenModalDialogCommand($title, $content, $opts)` | Open modal |
| `OpenDialogCommand('#sel', $title, $content)` | Open dialog |
| `OpenOffCanvasDialogCommand($title, $content)` | Slide-in panel |
| `CloseModalDialogCommand()` | Close modal |
| `CloseDialogCommand('#sel')` | Close specific dialog |
| `SetDialogOptionCommand('#sel', 'option', $val)` | Modify dialog |
| `SetDialogTitleCommand('#sel', $title)` | Update title |

### Feedback Commands

| Command | Purpose | HTMX Equivalent |
|---------|---------|-----------------|
| `MessageCommand($msg, null, ['type' => 'status'])` | Status message | Auto-included |
| `AnnounceCommand($text, 'polite')` | Screen reader | `triggerHeader()` + JS |
| `AlertCommand($msg)` | Browser alert | `triggerHeader()` + JS |
| `ScrollTopCommand('#sel')` | Scroll to element | CSS/JS |

### Navigation Commands

| Command | Purpose | HTMX Equivalent |
|---------|---------|-----------------|
| `RedirectCommand($url)` | Redirect | `redirectHeader(Url)` |

### State Commands

| Command | Purpose |
|---------|---------|
| `ChangedCommand('#el', '#asterisk')` | Mark changed |
| `UpdateBuildIdCommand($old, $new)` | Update form token |
| `RestripeCommand('#table')` | Re-stripe table |
| `SettingsCommand($settings, true)` | Update drupalSettings |
| `FocusFirstCommand('#wrapper')` | Focus first tabbable |

## Callback Patterns

### Return Render Array
```php
public function callback(array &$form, FormStateInterface $form_state) {
  return $form['subcategory'];
}
```

### Return AjaxResponse
```php
public function callback(array &$form, FormStateInterface $form_state) {
  $response = new AjaxResponse();
  $response->addCommand(new ReplaceCommand('#target', $content));
  $response->addCommand(new MessageCommand('Updated!'));
  return $response;
}
```

### Handling Errors
```php
public function callback(array &$form, FormStateInterface $form_state) {
  if ($form_state->hasAnyErrors()) {
    return $form; // Return entire form to show errors
  }
  return $form['result'];
}
```

## Security

### CSRF Protection
Drupal automatically handles AJAX CSRF via `X-Drupal-Ajax-Token` header.

### Route-Level Access
```yaml
my_module.ajax:
  path: '/ajax/endpoint'
  requirements:
    _permission: 'access content'
    _csrf_token: 'TRUE'
```

### Callback Access Check
```php
public function callback(...) {
  if (!$this->currentUser->hasPermission('edit content')) {
    $response = new AjaxResponse();
    $response->addCommand(new AlertCommand('Access denied'));
    return $response;
  }
}
```

### Input Sanitization
```php
$sanitized = Html::escape($form_state->getValue('field'));
```

## JavaScript API

### Creating AJAX Instance
```javascript
var ajax = Drupal.ajax({
  url: '/my/endpoint',
  event: 'click',
  selector: '#button',
  wrapper: 'result',
  submit: { extraKey: 'value' },
});
ajax.execute();
```

### Lifecycle Hooks
```javascript
var ajax = Drupal.ajax['element-id'];
ajax.beforeSerialize = function(element, options) { /* ... */ };
ajax.beforeSubmit = function(formValues, element, options) { /* ... */ };
ajax.success = function(response, status) { /* ... */ };
ajax.error = function(xhr, uri, message) { /* ... */ };
```

### Custom Command Handler
```javascript
Drupal.AjaxCommands.prototype.myCommand = function(ajax, response, status) {
  // response contains data from command's render() method
  console.log(response.data);
};
```

## Detecting AJAX Requests

### In Controller
```php
if ($request->isXmlHttpRequest()) {
  return new AjaxResponse();
}
```

### Using AjaxHelperTrait
```php
use Drupal\Core\Ajax\AjaxHelperTrait;

class MyController extends ControllerBase {
  use AjaxHelperTrait;

  public function content() {
    if ($this->isAjax()) {
      return new AjaxResponse();
    }
  }
}
```

## Common Patterns to Migrate

### Pattern Recognition

| If You See | It's | Migration |
|------------|------|-----------|
| `'#ajax' => [...]` | Form AJAX | Use `Htmx` class |
| `new AjaxResponse()` | Command response | Return render array |
| `::callback` method | AJAX callback | Logic in `buildForm()` |
| `ReplaceCommand` | Content replace | `swap('outerHTML')` |
| `HtmlCommand` | Inner HTML | `swap('innerHTML')` |
| `AppendCommand` | Append | `swap('beforeend')` |
| `MessageCommand` | Status message | Auto-included |
| `'wrapper' => 'id'` | Target ID | `target('#id')` |
| `'event' => 'change'` | Trigger | Default for select |
| `'event' => 'focusout'` | Blur trigger | `trigger('focusout')` |

### Complexity Assessment

| Pattern | Complexity | Notes |
|---------|------------|-------|
| Single element update | Simple | Direct conversion |
| Dependent dropdowns | Simple | Use `select()` + `target()` |
| Multiple element updates | Medium | Use `swapOob()` |
| Custom commands | Medium | Use `triggerHeader()` + JS |
| Dialog integration | Complex | May keep AJAX |
| Heavy JS processing | Complex | Evaluate case-by-case |
