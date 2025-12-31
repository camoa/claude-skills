# Migration Patterns

AJAX to HTMX migration patterns with side-by-side comparisons.

## Pattern 1: Dependent Dropdown

### AJAX
```php
$form['category'] = [
  '#type' => 'select',
  '#ajax' => [
    'callback' => '::categoryCallback',
    'wrapper' => 'subcategory-wrapper',
  ],
];

$form['subcategory'] = [
  '#prefix' => '<div id="subcategory-wrapper">',
  '#suffix' => '</div>',
];

public function categoryCallback(array &$form, FormStateInterface $form_state) {
  return $form['subcategory'];
}
```

### HTMX
```php
$form['category'] = ['#type' => 'select'];

(new Htmx())
  ->post(Url::fromRoute('<current>'))
  ->onlyMainContent()
  ->select('#edit-subcategory--wrapper')
  ->target('#edit-subcategory--wrapper')
  ->swap('outerHTML')
  ->applyTo($form['category']);

$form['subcategory'] = ['#type' => 'select'];

// Check trigger in buildForm - no callback needed
$trigger = $this->getHtmxTriggerName();
if ($trigger === 'category') {
  $form['subcategory']['#options'] = $this->getSubcategories($form_state->getValue('category'));
}
```

**Key Changes:**
- No `#ajax` property → `Htmx` class
- No callback method → logic in `buildForm()`
- Wrapper ID → CSS selector
- Use `getHtmxTriggerName()` for trigger detection

Reference: `core/modules/config/src/Form/ConfigSingleExportForm.php`

---

## Pattern 2: Cascading Selects with URL Update

### AJAX
```php
$form['type']['#ajax'] = ['callback' => '::updateName', 'wrapper' => 'name-wrapper'];
$form['name']['#ajax'] = ['callback' => '::updateExport', 'wrapper' => 'export-wrapper'];

public function updateName(...) { return $form['name']; }
public function updateExport(...) { return $form['export']; }
```

### HTMX
```php
// Type updates name
(new Htmx())
  ->post($form_url)
  ->onlyMainContent()
  ->select('*:has(>select[name="name"])')
  ->target('*:has(>select[name="name"])')
  ->swap('outerHTML')
  ->applyTo($form['type']);

// Name updates export
(new Htmx())
  ->post($form_url)
  ->onlyMainContent()
  ->select('[data-export-wrapper]')
  ->target('[data-export-wrapper]')
  ->swap('outerHTML')
  ->applyTo($form['name']);

// Handle trigger and URL push
$trigger = $this->getHtmxTriggerName();
if ($trigger === 'type') {
  // Also clear export via OOB
  (new Htmx())
    ->swapOob('outerHTML:[data-export-wrapper]')
    ->applyTo($form['export'], '#wrapper_attributes');

  $pushUrl = Url::fromRoute('my.form', ['type' => $form_state->getValue('type')]);
}

if ($pushUrl) {
  (new Htmx())->pushUrlHeader($pushUrl)->applyTo($form);
}
```

**Key Changes:**
- Use `swapOob()` for multiple element updates
- Use `pushUrlHeader()` for URL management
- Route parameters enable bookmarkable URLs

---

## Pattern 3: Button-Triggered Content Load

### AJAX
```php
// Controller
public function loadContent() {
  $response = new AjaxResponse();
  $response->addCommand(new ReplaceCommand('#wrapper', $content));
  $response->addCommand(new MessageCommand('Loaded!'));
  return $response;
}

// Form
$form['button'] = [
  '#type' => 'button',
  '#ajax' => ['callback' => '::loadCallback', 'wrapper' => 'wrapper'],
];
```

### HTMX
```php
// Controller - returns render array, not AjaxResponse
public function loadContent() {
  return [
    '#theme' => 'my_content',
    '#data' => $this->getData(),
  ];
}

// Form
$form['button'] = [
  '#type' => 'html_tag',
  '#tag' => 'button',
  '#value' => t('Load'),
  '#attributes' => ['type' => 'button'],
];

(new Htmx())
  ->get(Url::fromRoute('my.load'))
  ->onlyMainContent()
  ->target('#wrapper')
  ->swap('innerHTML')
  ->applyTo($form['button']);
```

**Key Changes:**
- Controller returns render array, not `AjaxResponse`
- No `MessageCommand` → auto-included by HtmxRenderer
- `select()` filters response, `target()` specifies destination

---

## Pattern 4: Multi-Step Wizard

### AJAX
```php
$form['next'] = [
  '#type' => 'submit',
  '#submit' => ['::nextStep'],
  '#ajax' => ['callback' => '::stepCallback', 'wrapper' => 'form-wrapper'],
];

public function nextStep(...) {
  $form_state->set('step', $step + 1);
  $form_state->setRebuild();
}
public function stepCallback(...) { return $form; }
```

### HTMX
```php
public function buildForm(..., $step = 1) {
  $nextUrl = Url::fromRoute('my.wizard', ['step' => $step + 1]);

  $form['next'] = ['#type' => 'button', '#value' => t('Next')];

  (new Htmx())
    ->post($nextUrl)
    ->onlyMainContent()
    ->target('#wizard-form')
    ->swap('outerHTML')
    ->pushUrl($nextUrl)
    ->applyTo($form['next']);

  $form['#attributes']['id'] = 'wizard-form';
  return $form;
}
```

**Key Changes:**
- Step is route parameter, not form state
- Each step has own URL (bookmarkable, back button works)
- No submit handlers for navigation

---

## Pattern 5: Real-time Validation

### AJAX
```php
$form['email'] = [
  '#type' => 'email',
  '#ajax' => [
    'callback' => '::validateEmail',
    'wrapper' => 'email-validation',
    'event' => 'focusout',
    'progress' => ['type' => 'none'],
  ],
];

public function validateEmail(...) {
  // Build and return validation message
  return $form['email_validation'];
}
```

### HTMX
```php
$form['email'] = ['#type' => 'email'];

(new Htmx())
  ->post(Url::fromRoute('<current>'))
  ->onlyMainContent()
  ->trigger('focusout')
  ->select('#email-validation')
  ->target('#email-validation')
  ->swap('outerHTML')
  ->applyTo($form['email']);

// In buildForm
$trigger = $this->getHtmxTriggerName();
if ($trigger === 'email') {
  $email = $form_state->getValue('email');
  $form['email_validation']['#markup'] = $this->emailExists($email)
    ? '<span class="error">Taken</span>'
    : '<span class="success">Available</span>';
}
```

---

## Pattern 6: Infinite Scroll / Load More

### AJAX
```php
$form['load_more'] = [
  '#ajax' => ['callback' => '::loadMore', 'wrapper' => 'list', 'method' => 'append'],
];
```

### HTMX
```php
// Click trigger
(new Htmx())
  ->get(Url::fromRoute('my.items', ['page' => $nextPage]))
  ->onlyMainContent()
  ->select('.item-list')
  ->target('#content-list')
  ->swap('beforeend')
  ->applyTo($form['load_more']);

// Scroll trigger (sentinel at bottom)
(new Htmx())
  ->get(Url::fromRoute('my.items', ['page' => $nextPage]))
  ->trigger('revealed')
  ->select('.item-list')
  ->target('#content-list')
  ->swap('beforeend')
  ->applyTo($form['sentinel']);
```

---

## Pattern 7: Dynamic Field Addition

### AJAX
```php
$form['add_item'] = [
  '#type' => 'submit',
  '#submit' => ['::addItem'],
  '#ajax' => ['callback' => '::itemsCallback', 'wrapper' => 'items-wrapper'],
];

public function addItem(...) {
  $form_state->set('item_count', $count + 1);
  $form_state->setRebuild();
}
```

### HTMX
```php
$item_count = $form_state->getValue('item_count', 1);
$form['item_count'] = ['#type' => 'hidden', '#value' => $item_count];

$form['add_item'] = ['#type' => 'button', '#value' => t('Add Item')];

(new Htmx())
  ->post(Url::fromRoute('<current>'))
  ->onlyMainContent()
  ->vals(['item_count' => $item_count + 1])
  ->select('#items-wrapper')
  ->target('#items-wrapper')
  ->swap('outerHTML')
  ->applyTo($form['add_item']);
```

**Key Changes:**
- Use `vals()` to send incremented count
- Hidden field tracks count instead of form state
- No submit handler needed

---

## JavaScript Migration

### Event Mapping

| AJAX Hook | HTMX Event |
|-----------|------------|
| `beforeSerialize` | `htmx:configRequest` |
| `beforeSubmit` | `htmx:beforeRequest` |
| `success` | `htmx:afterSwap` |
| `error` | `htmx:responseError` |
| After behaviors | `htmx:drupal:load` |
| Before removal | `htmx:drupal:unload` |

### Custom AJAX Command → HTMX Trigger

**AJAX:**
```php
$response->addCommand(new NotificationCommand('Hello!'));

// JS
Drupal.AjaxCommands.prototype.showNotification = function(ajax, response) {
  alert(response.message);
};
```

**HTMX:**
```php
(new Htmx())
  ->triggerHeader(['showNotification' => ['message' => 'Hello!']])
  ->applyTo($build);

// JS
htmx.on('showNotification', (e) => alert(e.detail.message));
```

---

## When NOT to Migrate

Keep AJAX for:
- Complex command sequences
- `CssCommand`, `InvokeCommand` for jQuery methods
- `OpenModalDialogCommand`, `CloseDialogCommand`
- `DataCommand` for jQuery data API
- Contrib modules expecting AJAX callbacks

### Hybrid Approach

Both systems coexist. AJAX can insert HTMX-enabled content:

```php
public function ajaxCallback(...) {
  $build = ['#type' => 'container'];

  $build['htmx_button'] = ['#type' => 'button', '#value' => t('Refresh')];

  (new Htmx())
    ->get(Url::fromRoute('my.refresh'))
    ->target('#wrapper')
    ->applyTo($build['htmx_button']);

  return $build;
}
```

`Drupal.behaviors.htmx` ensures HTMX processes content inserted by AJAX.

---

## Migration Checklist

- [ ] Identify all `#ajax` properties
- [ ] Replace with `Htmx` class configuration
- [ ] Convert callbacks to `buildForm()` logic
- [ ] Replace `AjaxResponse` with render arrays
- [ ] Update routes with `_htmx_route: TRUE` if needed
- [ ] Migrate JS event handlers to HTMX events
- [ ] Test behaviors attach/detach
- [ ] Test browser history (back/forward)
- [ ] Verify accessibility
- [ ] Test with JavaScript disabled
