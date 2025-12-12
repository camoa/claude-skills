# Security Checklist for Drupal

Security practices verified during `/validate` and `/complete` commands.

## Quick Reference

| Area | Rule | How |
|------|------|-----|
| Input | Always validate | Form API, constraints |
| Output | Always escape | Twig auto, `Html::escape()` |
| Database | Never raw SQL | Entity Query API, Database API |
| Access | Always check | Permissions, access handlers |
| CSRF | Always protect | Form API tokens |

## Input Validation

### Form API (Preferred)

```php
$form['email'] = [
  '#type' => 'email',
  '#title' => $this->t('Email'),
  '#required' => TRUE,
  '#maxlength' => 254,
];
```

### Built-in Constraints

| Constraint | Use For |
|------------|---------|
| `#required` | Mandatory fields |
| `#maxlength` | String length limits |
| `#min` / `#max` | Numeric ranges |
| `#pattern` | Regex validation |

### Custom Validation

```php
public function validateForm(array &$form, FormStateInterface $form_state): void {
  $value = $form_state->getValue('field');
  if (!$this->isValid($value)) {
    $form_state->setErrorByName('field', $this->t('Invalid value.'));
  }
}
```

### Checklist
- [ ] All user input goes through Form API
- [ ] Required fields marked `#required`
- [ ] Length limits set via `#maxlength`
- [ ] Custom validators for business rules

## Output Sanitization

### Twig (Auto-Escaped)

```twig
{# Safe - auto-escaped #}
{{ user_input }}

{# Dangerous - only when you KNOW it's safe HTML #}
{{ trusted_html|raw }}
```

### PHP Code

| Method | Use For |
|--------|---------|
| `Html::escape($string)` | Plain text in HTML |
| `Xss::filter($html)` | User HTML with allowed tags |
| `UrlHelper::stripDangerousProtocols($url)` | URLs |

### Checklist
- [ ] Twig templates use `{{ }}` (not `|raw`)
- [ ] `|raw` only for known-safe HTML
- [ ] PHP output uses `Html::escape()` or `Xss::filter()`
- [ ] URLs sanitized before output

## Database Security

### Entity Query API (Preferred)

```php
$results = $this->entityTypeManager
  ->getStorage('node')
  ->getQuery()
  ->accessCheck(TRUE)
  ->condition('type', 'article')
  ->condition('status', 1)
  ->execute();
```

### Database API with Placeholders

```php
$result = $this->database->select('my_table', 't')
  ->fields('t', ['id', 'name'])
  ->condition('status', $status)  // Safe - parameterized
  ->execute();
```

### NEVER Do This

```php
// DANGEROUS - SQL injection vulnerability
$query = "SELECT * FROM users WHERE name = '$userInput'";
$this->database->query($query);
```

### Checklist
- [ ] Entity Query API used for entity operations
- [ ] Database API with placeholders for custom queries
- [ ] No string concatenation in queries
- [ ] `accessCheck(TRUE)` on entity queries

## CSRF Protection

### Forms (Automatic)

Form API automatically adds CSRF tokens. No action needed for standard forms.

### Links with Side Effects

```php
$url = Url::fromRoute('my_module.delete', ['id' => $id])
  ->setOption('csrf', TRUE);
```

### AJAX Requests

```php
// In routing.yml
my_module.ajax:
  path: '/ajax/endpoint'
  defaults:
    _controller: '\Drupal\my_module\Controller\AjaxController::handle'
  requirements:
    _csrf_token: 'TRUE'
```

### Checklist
- [ ] State-changing links use CSRF tokens
- [ ] AJAX endpoints verify CSRF
- [ ] No GET requests that change state

## Access Control

### Route-Level

```yaml
# my_module.routing.yml
my_module.admin:
  path: '/admin/my-module'
  defaults:
    _controller: '\Drupal\my_module\Controller\AdminController::page'
  requirements:
    _permission: 'administer my_module'
```

### Entity Access

```php
// In entity class
public function access($operation, AccountInterface $account = NULL, $return_as_object = FALSE) {
  // Custom access logic
}
```

### Programmatic Check

```php
if ($this->currentUser->hasPermission('administer my_module')) {
  // Allowed
}
```

### Checklist
- [ ] All routes have access requirements
- [ ] Permissions defined in `*.permissions.yml`
- [ ] Entity access handlers implemented
- [ ] Programmatic checks use `hasPermission()`

## Security Review Checklist

Before `/complete`:

```markdown
## Security Verification

### Input
- [ ] All input validated via Form API
- [ ] Custom validation for business rules
- [ ] File uploads restricted by type/size

### Output
- [ ] No unescaped user content
- [ ] `|raw` only for trusted HTML
- [ ] URLs sanitized

### Database
- [ ] No raw SQL with user input
- [ ] Entity queries use accessCheck(TRUE)
- [ ] Placeholders used in all queries

### Access
- [ ] Routes have permission requirements
- [ ] Entity access enforced
- [ ] Admin pages protected

### CSRF
- [ ] Forms use Form API (automatic)
- [ ] State-changing links have tokens
```
