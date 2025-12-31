---
description: Guide migration of a specific AJAX pattern to HTMX with step-by-step instructions
allowed-tools: Read, Edit, Glob, Grep
argument-hint: <file-path> [pattern-type]
---

# Migrate AJAX to HTMX

Guided migration of an AJAX pattern to HTMX.

## Usage

`/htmx-migrate <file-path> [pattern-type]`

## Parameters

- `$1` - **Required**. File path containing AJAX pattern
- `$2` - Pattern type (optional). Auto-detected if not provided.
  - `dropdown` - Dependent dropdown
  - `cascade` - Cascading selects
  - `button` - Button-triggered content
  - `wizard` - Multi-step form
  - `validation` - Real-time validation
  - `loadmore` - Load more / infinite scroll
  - `fields` - Dynamic field addition

## Steps

1. **Read the file** to understand current AJAX implementation

2. **Identify pattern type**:
   - If provided, use specified type
   - Otherwise, analyze code to determine pattern

3. **Show current implementation**:
   - Highlight the AJAX-specific code
   - Explain what it does

4. **Show HTMX equivalent**:
   - Reference `references/migration-patterns.md`
   - Present the converted code

5. **Guide migration**:
   - Step 1: Remove `#ajax` property
   - Step 2: Add `Htmx` class configuration
   - Step 3: Move callback logic to `buildForm()` (if applicable)
   - Step 4: Add trigger detection with `getHtmxTriggerName()`
   - Step 5: Update route if needed

6. **Verify changes**:
   - Run `/htmx-validate` on the file

## Example

```
/htmx-migrate modules/custom/my_module/src/Form/MyForm.php dropdown
```

## Migration Workflow

```markdown
## Migrating: MyForm.php

### Current AJAX Pattern
```php
$form['category'] = [
  '#type' => 'select',
  '#ajax' => [
    'callback' => '::categoryCallback',
    'wrapper' => 'subcategory-wrapper',
  ],
];
```

### HTMX Equivalent
```php
$form['category'] = ['#type' => 'select'];

(new Htmx())
  ->post(Url::fromRoute('<current>'))
  ->onlyMainContent()
  ->select('#edit-subcategory--wrapper')
  ->target('#edit-subcategory--wrapper')
  ->swap('outerHTML')
  ->applyTo($form['category']);
```

### Migration Steps
1. [ ] Remove `#ajax` from `$form['category']`
2. [ ] Add `use Drupal\Core\Htmx\Htmx;`
3. [ ] Add Htmx configuration after element
4. [ ] Move callback logic to buildForm()
5. [ ] Delete unused callback method

### Ready to Apply?
```

## Notes

- Always backup before migrating
- Test without JavaScript after migration
- Run `/htmx-validate` to check result
