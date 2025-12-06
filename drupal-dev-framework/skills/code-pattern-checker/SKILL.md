---
name: code-pattern-checker
description: Use before committing code - validates Drupal coding standards, SOLID/DRY principles, security practices, and CSS standards
version: 1.0.0
---

# Code Pattern Checker

Validate code against Drupal standards and best practices before commit.

## Triggers

- Before committing code
- After implementation, before task completion
- `/drupal-dev-framework:validate` command
- User says "Check my code"

## Validation Categories

### 1. Drupal Coding Standards

**PHP Standards:**
- [ ] PSR-12 / Drupal coding standards
- [ ] Proper docblocks on classes and methods
- [ ] Type hints on parameters and returns
- [ ] No deprecated function usage

**Naming Conventions:**
- [ ] Classes: PascalCase
- [ ] Methods: camelCase
- [ ] Constants: UPPER_SNAKE_CASE
- [ ] Files match class names

### 2. SOLID Principles

- [ ] **S**ingle Responsibility - Each class has one job
- [ ] **O**pen/Closed - Extend, don't modify
- [ ] **L**iskov Substitution - Subtypes are substitutable
- [ ] **I**nterface Segregation - Specific interfaces
- [ ] **D**ependency Inversion - Depend on abstractions

### 3. DRY Principle

- [ ] No duplicated logic
- [ ] Shared code extracted to services/traits
- [ ] Base classes used appropriately
- [ ] No copy-paste code blocks

### 4. Security (OWASP)

- [ ] No SQL injection vulnerabilities (use query builder)
- [ ] No XSS vulnerabilities (use Twig, sanitize output)
- [ ] CSRF protection on forms (form tokens)
- [ ] Access checks on routes and operations
- [ ] No sensitive data in logs
- [ ] Input validation

### 5. CSS/SCSS Standards

If frontend code is included:
- [ ] Mobile-first approach
- [ ] No `!important` usage
- [ ] No `@extend` in SCSS
- [ ] Bootstrap classes used where applicable
- [ ] BEM naming convention
- [ ] Variables for colors/spacing

### 6. Performance

- [ ] No N+1 query problems
- [ ] Appropriate caching
- [ ] Lazy loading where beneficial
- [ ] No heavy operations in loops

## Output Format

```markdown
## Code Pattern Check: {component/file}

### Status: PASS / ISSUES FOUND

### Drupal Standards
- [x] PSR-12 compliance
- [ ] Missing docblock on `methodName()`
- [x] Proper type hints

### SOLID Principles
- [x] Single Responsibility
- [x] Open/Closed
- [x] Dependency Inversion

### DRY Check
- [ ] Duplicate logic found in lines 45-52 and 78-85

### Security
- [x] No SQL injection risks
- [x] Output properly escaped
- [ ] Missing access check on route

### CSS Standards (if applicable)
- [x] Mobile-first
- [x] No !important

### Issues to Fix
1. Add docblock to `processData()` method
2. Extract duplicate logic to shared method
3. Add access check to admin route

### Approved for Commit: YES / NO
```

## Automated Checks

Suggest running:
```bash
# PHP CodeSniffer
vendor/bin/phpcs --standard=Drupal,DrupalPractice src/

# PHPStan
vendor/bin/phpstan analyze src/
```

## Human Control Points

- User reviews findings
- User decides which issues to fix
- User approves for commit
