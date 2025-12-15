# Purposeful Code

Ensures code is intentional, comprehensible, and not over-engineered. Verified during `/validate` and `/complete` commands.

## Philosophy

**Good code is purposeful code.** Every line should:
- Serve a clear function
- Be understood by the developer who wrote it
- Use real, existing APIs
- Avoid unnecessary defensive patterns

This guidance applies regardless of how code is written - whether by hand, with AI assistance, or generated. The measure is the same: does the developer understand it, and is it necessary?

## Quick Reference

| Area | Good | Bad |
|------|------|-----|
| Error handling | Catch specific errors you can recover from | Wrap everything in try-catch |
| Null checks | Check when value might actually be null | Check injected services for null |
| Comments | Explain "why" | Describe "what" code does |
| APIs | Use documented Drupal APIs | Call non-existent methods |

## Unnecessary Try-Catch Blocks

### When Try-Catch is Appropriate

```php
// GOOD: Handling external service failures
try {
  $response = $this->httpClient->get($url);
}
catch (RequestException $e) {
  $this->logger->error('API request failed: @message', ['@message' => $e->getMessage()]);
  return NULL;
}
```

### When Try-Catch is Unnecessary

```php
// BAD: Drupal handles entity save failures
try {
  $node->save();
}
catch (\Exception $e) {
  // Entity save failures are framework-level - let them bubble
}

// BAD: Swallowing errors hides bugs
try {
  $this->processData($data);
}
catch (\Exception $e) {
  // Silently failing means bugs go unnoticed
}
```

### Checklist
- [ ] Try-catch only wraps operations that can genuinely fail
- [ ] Caught exceptions are specific, not `\Exception`
- [ ] Catch blocks actually handle the error (log, recover, rethrow)
- [ ] No empty catch blocks

## Unnecessary Defensive Checks

### Service Injection

Drupal's dependency injection guarantees services are valid when injected.

```php
// BAD: Services are never null after injection
public function process(): void {
  if ($this->entityTypeManager === NULL) {  // Never happens
    return;
  }
  // ...
}

// GOOD: Trust the container
public function process(): void {
  $storage = $this->entityTypeManager->getStorage('node');
  // ...
}
```

### Entity Type Manager Returns

```php
// BAD: Over-defensive
$storage = $this->entityTypeManager->getStorage('node');
if ($storage === NULL) {  // getStorage() throws, never returns null
  return;
}

// GOOD: Let errors surface during development
$storage = $this->entityTypeManager->getStorage('node');
```

### When Null Checks ARE Appropriate

```php
// GOOD: Entity loads can return NULL
$node = $this->entityTypeManager->getStorage('node')->load($nid);
if ($node === NULL) {
  throw new NotFoundHttpException();
}

// GOOD: Optional dependencies
if ($this->optionalService !== NULL) {
  $this->optionalService->process();
}
```

### Checklist
- [ ] No null checks on required injected services
- [ ] Null checks only for genuinely nullable values (entity loads, optional deps)
- [ ] No defensive checks for impossible states

## API Validity

### Hallucinated APIs

Code that calls non-existent methods or uses non-existent hooks.

```php
// BAD: Method doesn't exist
$node->getNonExistentMethod();

// BAD: Hook doesn't exist
function my_module_nonexistent_hook() { }

// BAD: Service doesn't exist
$container->get('imaginary.service');
```

### How to Verify

1. **Methods**: Check interface or class definition
2. **Hooks**: Check `*.api.php` files or core documentation
3. **Services**: Check `*.services.yml` files
4. **Permissions**: Check `*.permissions.yml` files
5. **Routes**: Check `*.routing.yml` files

### Common Hallucination Patterns

| What's Called | Reality |
|---------------|---------|
| `$node->getAuthorId()` | Use `$node->getOwnerId()` |
| `$entity->getLabel()` | Use `$entity->label()` |
| `hook_node_create_alter()` | Hook doesn't exist |
| `\Drupal::service('entity.manager')` | Removed in Drupal 9, use `entity_type.manager` |

### Checklist
- [ ] All method calls verified against actual interfaces
- [ ] All hooks verified against `*.api.php` documentation
- [ ] All services verified against `*.services.yml`
- [ ] No deprecated APIs (check drupal.org)

## Comment Quality

### Good Comments

```php
// GOOD: Explains why, not what
// We disable caching here because this block shows user-specific data
// that changes based on their subscription status.
$build['#cache']['max-age'] = 0;

// GOOD: Documents non-obvious business rule
// Orders over $1000 require manager approval per company policy
if ($order->getTotal() > 1000) {
  $order->set('requires_approval', TRUE);
}
```

### Bad Comments

```php
// BAD: Describes what code obviously does
// Set the title to the node title
$build['#title'] = $node->getTitle();

// BAD: Reads like an instruction/prompt
// Now we need to loop through the items and process each one
foreach ($items as $item) {
  $this->processItem($item);
}

// BAD: LLM prompt artifact
// This function handles the user authentication logic
public function authenticate(string $username, string $password): bool {
```

### Instruction-Style Comments (Red Flag)

These patterns suggest code was generated without full understanding:

| Pattern | Example |
|---------|---------|
| "Now we..." | `// Now we need to validate the data` |
| "Let's..." | `// Let's check if the user exists` |
| "First/Then/Next..." | `// First, get the entity` |
| "This handles..." | `// This handles the form submission` |
| "We will..." | `// We will iterate through the results` |

### Checklist
- [ ] Comments explain reasoning, not obvious behavior
- [ ] No instruction-style language ("now we", "let's")
- [ ] No comments that duplicate what code clearly shows
- [ ] Comments kept up-to-date when code changes

## Developer Comprehension

### The Test

Can the developer answer these questions about any code block?

1. **What** does this code do? (should be obvious from reading)
2. **Why** does this code exist? (business requirement or technical necessity)
3. **What happens** if this fails? (error handling strategy)
4. **What are the inputs and outputs?** (data flow)

### Signs of Low Comprehension

| Sign | What It Means |
|------|---------------|
| Cannot explain purpose | Code may be unnecessary or misunderstood |
| Cannot predict behavior | Debugging will be difficult |
| Cannot identify edge cases | Testing will be incomplete |
| "It just works" | Time bomb waiting for failure |

### Checklist
- [ ] Developer can explain purpose of each function
- [ ] Developer can predict output for given inputs
- [ ] Developer knows what errors could occur
- [ ] Developer knows why specific patterns were chosen

## Validation Process

During `/validate`, check for:

1. **Try-catch audit**: Are all try-catch blocks necessary?
2. **Null check audit**: Are all null checks for actually nullable values?
3. **API verification**: Do all method/hook/service calls exist?
4. **Comment review**: Do comments explain "why"?
5. **Comprehension check**: Can developer explain each component?

### Blocking Issues
- Calls to non-existent APIs
- Invalid hook implementations
- Instruction-style comments indicating lack of understanding
- Developer cannot explain what code does

### Warning Issues
- Unnecessary try-catch (not swallowing errors)
- Over-defensive null checks
- Comments describing obvious behavior
