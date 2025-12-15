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
| Files | Whitelist extensions | `file_validate_extensions`, private:// |
| Secrets | Never in config | `$settings` in settings.php |
| Logging | Never sensitive data | No passwords, keys, PII |
| Caching | Context sensitive data | Cache contexts, tags |
| Serialization | Never unserialize user data | JSON instead |

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

## File Upload Security

### Restrict File Types

```php
$form['document'] = [
  '#type' => 'managed_file',
  '#title' => $this->t('Document'),
  '#upload_validators' => [
    'file_validate_extensions' => ['pdf doc docx'],
    'file_validate_size' => [10 * 1024 * 1024], // 10MB
  ],
  '#upload_location' => 'private://documents/',
];
```

### Private vs Public Files

| Location | When to Use |
|----------|-------------|
| `public://` | Files that can be accessed by anyone |
| `private://` | Files that need access control |

### Checklist
- [ ] File extensions explicitly whitelisted (never blacklist)
- [ ] File size limits set
- [ ] Sensitive files use `private://` stream
- [ ] No executable extensions allowed (.php, .phar, .sh)
- [ ] MIME type validation for critical uploads

## Sensitive Data Exposure

### Never Log Sensitive Data

```php
// BAD: Logging passwords
$this->logger->debug('Login attempt: @user/@pass', [
  '@user' => $username,
  '@pass' => $password,  // NEVER
]);

// GOOD: Log only what's needed
$this->logger->info('Login attempt for user: @user', ['@user' => $username]);
```

### Never Expose in Errors

```php
// BAD: Exposing internal details
throw new \Exception("Database error: $sql");

// GOOD: Generic message, detailed logging
$this->logger->error('Database error: @sql', ['@sql' => $sql]);
throw new \Exception($this->t('An error occurred. Please try again.'));
```

### Checklist
- [ ] No passwords in logs
- [ ] No API keys in logs or output
- [ ] No full SQL queries in user-facing errors
- [ ] No stack traces in production
- [ ] Sensitive config uses `$settings` not config API

## Caching Sensitive Content

### Per-User Content

```php
$build['#cache'] = [
  'contexts' => ['user'],  // Varies by user
  'tags' => ['user:' . $this->currentUser->id()],
];
```

### Uncacheable Content

```php
// Disable caching for sensitive data
$build['#cache']['max-age'] = 0;
```

### Checklist
- [ ] Personal data blocks have user cache context
- [ ] Sensitive data not cached or properly tagged
- [ ] Session-specific content uncached or contextualized
- [ ] No sensitive data in page cache

## Object Injection Prevention

### Never Unserialize User Input

```php
// DANGEROUS: Object injection vulnerability
$data = unserialize($userInput);

// SAFE: Use JSON
$data = json_decode($userInput, TRUE);

// SAFE: If serialization needed, use allowed_classes
$data = unserialize($input, ['allowed_classes' => [AllowedClass::class]]);
```

### Checklist
- [ ] No `unserialize()` on user input
- [ ] JSON preferred over PHP serialization
- [ ] If serialization required, `allowed_classes` specified

## Third-Party API Security

### Store Credentials Securely

```php
// In settings.php (not config)
$settings['my_module']['api_key'] = 'secret_key';

// In code
$apiKey = Settings::get('my_module')['api_key'];
```

### Validate Responses

```php
$response = $this->httpClient->get($apiUrl);
$data = json_decode($response->getBody(), TRUE);

// Validate structure before use
if (!isset($data['expected_field'])) {
  throw new \RuntimeException('Invalid API response');
}
```

### Checklist
- [ ] API keys in `$settings`, not config
- [ ] HTTPS for all external requests
- [ ] API responses validated before use
- [ ] Timeouts configured for external requests
- [ ] Failed requests logged (without sensitive data)

## Session Security

### Session Handling

Drupal handles sessions securely by default. Custom session handling:

```php
// Regenerate session after privilege change
$this->sessionManager->regenerate();

// Destroy session on logout
$this->sessionManager->destroy();
```

### Checklist
- [ ] Session regenerated after login/privilege change
- [ ] Session destroyed on logout
- [ ] No custom session handling without security review
- [ ] Session cookies use secure flags (Drupal default)

## Security Review Checklist

Before `/complete`:

```markdown
## Security Verification

### Input
- [ ] All input validated via Form API
- [ ] Custom validation for business rules
- [ ] File uploads restricted by type/size
- [ ] No executable file extensions allowed

### Output
- [ ] No unescaped user content
- [ ] `|raw` only for trusted HTML
- [ ] URLs sanitized
- [ ] Error messages don't expose internals

### Database
- [ ] No raw SQL with user input
- [ ] Entity queries use accessCheck(TRUE)
- [ ] Placeholders used in all queries

### Access
- [ ] Routes have permission requirements
- [ ] Entity access enforced
- [ ] Admin pages protected
- [ ] Private files use private:// stream

### CSRF
- [ ] Forms use Form API (automatic)
- [ ] State-changing links have tokens

### Data Protection
- [ ] No sensitive data in logs
- [ ] API keys in $settings, not config
- [ ] Sensitive content properly cached/uncached
- [ ] No unserialize() on user data
```
