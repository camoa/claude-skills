---
description: Analyze Drupal module for AJAX patterns and identify HTMX migration candidates
allowed-tools: Read, Glob, Grep, Task
argument-hint: <module-path>
---

# Analyze AJAX Patterns

Scan a Drupal module for AJAX usage and generate a migration report.

## Usage

`/htmx-analyze <module-path>`

## Parameters

- `$1` - **Required**. Path to module (e.g., `modules/custom/my_module`)

## Steps

1. **Validate path exists**
   - If missing, prompt user for path

2. **Invoke ajax-analyzer agent**
   - Use Task tool with `subagent_type: "drupal-htmx:ajax-analyzer"`
   - Pass the module path

3. **Present results**
   - Show summary of patterns found
   - List migration candidates by complexity
   - Suggest next steps

## Example

```
/htmx-analyze modules/custom/my_module
```

## Agent Invocation

```
Use the Task tool to invoke the ajax-analyzer agent:
- subagent_type: "drupal-htmx:ajax-analyzer"
- prompt: "Analyze [module-path] for AJAX patterns and generate migration report"
```

## Expected Output

```markdown
## AJAX Analysis Report: my_module

### Summary
- Files with AJAX: 3
- Total patterns: 5
- Simple: 3
- Medium: 1
- Complex: 1

### Migration Candidates

#### Simple (Start Here)
1. `src/Form/MyForm.php:45` - Dependent dropdown
2. `src/Form/MyForm.php:89` - Real-time validation
3. `src/Controller/MyController.php:123` - Content load button

#### Medium
1. `src/Form/WizardForm.php:67` - Multi-step with URL

#### Complex (Evaluate)
1. `src/Controller/DialogController.php:34` - Modal dialog

### Next Steps
- Run `/htmx-migrate src/Form/MyForm.php` for guided migration
```
