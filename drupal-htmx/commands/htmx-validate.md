---
description: Validate HTMX implementation in Drupal module against best practices
allowed-tools: Read, Glob, Grep, Task
argument-hint: <module-path>
---

# Validate HTMX Implementation

Check HTMX code for issues, best practices, and accessibility.

## Usage

`/htmx-validate <module-path>`

## Parameters

- `$1` - **Required**. Path to module (e.g., `modules/custom/my_module`)

## Steps

1. **Validate path exists**
   - If missing, prompt user for path

2. **Invoke htmx-validator agent**
   - Use Task tool with `subagent_type: "drupal-htmx:htmx-validator"`
   - Pass the module path

3. **Present results**:
   - Summary of checks
   - Issues found (critical, warnings, suggestions)
   - Passed checks
   - Recommendations

## Example

```
/htmx-validate modules/custom/my_module
```

## Agent Invocation

```
Use the Task tool to invoke the htmx-validator agent:
- subagent_type: "drupal-htmx:htmx-validator"
- prompt: "Validate HTMX implementation in [module-path]"
```

## Expected Output

```markdown
## HTMX Validation Report: my_module

### Summary
- Files checked: 4
- Issues found: 2
- Passed checks: 8

### Issues

#### Critical (Must Fix)

**src/Form/MyForm.php:67**
- Issue: Missing `onlyMainContent()` - full page HTML returned
- Fix: Add `->onlyMainContent()` to the Htmx chain
- Impact: Large response size, potential display issues

#### Warnings (Should Fix)

**src/Form/MyForm.php:89**
- Issue: No `aria-live` attribute on dynamic region
- Fix: Add `'#attributes' => ['aria-live' => 'polite']` to container
- Impact: Screen readers won't announce changes

### Suggestions

**src/Form/WizardForm.php:45**
- Suggestion: Consider using `pushUrlHeader()` for bookmarkable wizard steps
- Benefit: Users can bookmark/share specific steps

### Passed Checks
- [x] Htmx class used (not raw attributes)
- [x] Proper swap strategies
- [x] Target selectors valid
- [x] Trigger detection implemented
- [x] Progressive enhancement possible
- [x] Route configuration correct
- [x] Form works without JavaScript
- [x] No mixed AJAX/HTMX on same elements

### Recommendations
1. Fix critical issue in MyForm.php first
2. Add accessibility improvements
3. Consider URL state for wizard
```

## Validation Categories

| Category | Checks |
|----------|--------|
| Critical | Missing onlyMainContent, invalid selectors, broken swaps |
| Warnings | Missing accessibility, suboptimal patterns |
| Suggestions | Performance improvements, UX enhancements |
| Passed | Correct usage, best practices followed |
