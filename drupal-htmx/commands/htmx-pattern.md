---
description: Get HTMX pattern recommendation for a specific use case in Drupal
allowed-tools: Read, Glob, Task
argument-hint: <use-case>
---

# Pattern Recommendation

Get the recommended HTMX pattern for a use case.

## Usage

`/htmx-pattern <use-case>`

## Parameters

- `$ARGUMENTS` - Use case description. Examples:
  - `dependent dropdown`
  - `infinite scroll`
  - `real-time validation`
  - `multi-step wizard`
  - `load more button`
  - `cascading selects`
  - `modal content`
  - `dynamic field addition`

## Steps

1. **Parse use case** from arguments

2. **Invoke htmx-recommender agent**
   - Use Task tool with `subagent_type: "drupal-htmx:htmx-recommender"`
   - Pass the use case

3. **Present recommendation**:
   - Pattern name and description
   - Code example with Htmx class
   - Key configuration options
   - Considerations and edge cases

## Example

```
/htmx-pattern dependent dropdown
```

## Agent Invocation

```
Use the Task tool to invoke the htmx-recommender agent:
- subagent_type: "drupal-htmx:htmx-recommender"
- prompt: "Recommend HTMX pattern for: [use-case]"
```

## Expected Output

```markdown
## Recommended Pattern: Dependent Dropdown

### Description
Updates a secondary select field based on the value of a primary select.
Classic use case: Category → Subcategory.

### Implementation

```php
public function buildForm(array $form, FormStateInterface $form_state) {
  $form_url = Url::fromRoute('<current>');

  $form['category'] = [
    '#type' => 'select',
    '#title' => $this->t('Category'),
    '#options' => $this->getCategories(),
  ];

  (new Htmx())
    ->post($form_url)
    ->onlyMainContent()
    ->select('#edit-subcategory--wrapper')
    ->target('#edit-subcategory--wrapper')
    ->swap('outerHTML')
    ->applyTo($form['category']);

  $category = $form_state->getValue('category');
  $form['subcategory'] = [
    '#type' => 'select',
    '#title' => $this->t('Subcategory'),
    '#options' => $category ? $this->getSubcategories($category) : [],
  ];

  return $form;
}
```

### Key Methods
- `post()` - Submit form data
- `onlyMainContent()` - Minimal response
- `select()` - Extract specific element from response
- `target()` - Where to swap
- `swap('outerHTML')` - Replace entire wrapper

### Considerations
- Wrapper ID format: `#edit-[field-name]--wrapper`
- No callback method needed - logic stays in buildForm()
- Use `getHtmxTriggerName()` for conditional logic

### Reference
- Core example: `core/modules/config/src/Form/ConfigSingleExportForm.php`
```

## Common Use Cases

| Use Case | Pattern |
|----------|---------|
| dependent dropdown | Form partial update |
| cascading selects | Chained updates with OOB |
| real-time validation | Blur trigger validation |
| load more | Append with beforeend |
| infinite scroll | Revealed trigger |
| multi-step wizard | URL-based steps |
| modal content | Target modal container |
| dynamic fields | vals() with count |
