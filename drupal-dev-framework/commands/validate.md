---
description: Validate implementation against architecture and standards
allowed-tools: Read, Glob, Grep, Task
argument-hint: [component-or-file]
---

# Validate

Validate implementation against architecture and coding standards.

## Usage

```
/drupal-dev-framework:validate                    # Validate all
/drupal-dev-framework:validate service            # Validate component
/drupal-dev-framework:validate src/MyService.php  # Validate file
```

## What This Does

1. Invokes `architecture-validator` agent
2. Invokes `code-pattern-checker` skill
3. Checks against documented architecture
4. Validates coding standards
5. Reports issues or approves

## Validation Checks

### Architecture Validation
- Pattern matches architecture document
- Dependencies match documented services
- Interface matches specification
- No undocumented components

### Code Standards
- Drupal coding standards (PSR-12)
- SOLID principles
- DRY principle
- Security best practices
- CSS standards (if frontend)

## Output Format

```markdown
## Validation: {component/file}

### Overall Status: PASS / ISSUES FOUND

### Architecture Check
| Aspect | Expected | Actual | Status |
|--------|----------|--------|--------|
| Pattern | ConfigFormBase | ConfigFormBase | ✓ |
| Dependencies | config.factory | config.factory | ✓ |

### Code Standards
- [x] Drupal coding standards
- [x] SOLID principles
- [ ] DRY - duplicate logic found

### Security
- [x] No SQL injection
- [x] Output escaped
- [x] Access checks present

### Issues Found
1. **DRY violation**: Lines 45-52 duplicate lines 78-85
   - Recommendation: Extract to private method

### Approved for: Commit / Needs fixes
```

## When to Use

- Before completing a task
- Before committing code
- After significant changes
- During code review prep

## Related Commands

- `/drupal-dev-framework:complete` - After validation passes
- `/drupal-dev-framework:implement` - Return to implementation

## Integration

Works with:
- `superpowers:verification-before-completion`
- `superpowers:code-reviewer`
