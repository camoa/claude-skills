---
description: "Validate implementation against architecture and standards. Trigger: 'check code', 'verify implementation', 'run validation', 'does this follow architecture'. Use proactively during Phase 3."
allowed-tools: Read, Glob, Grep, Task
context: fork
argument-hint: "[component-or-file]"
---

# Validate

Validate implementation against architecture and coding standards.

> **Note (v3.13.0+):** this is the **architecture-fit** validator — it checks whether code matches the task's architecture.md decisions. For granular **quality gates** (TDD discipline, SOLID, DRY, security, visual regression, etc.), use the `/validate:*` family introduced in v3.13.0: `/validate:tdd`, `/validate:solid`, `/validate:dry`, `/validate:security`, `/validate:guides`, `/validate:visual-regression`, `/validate:visual-parity`, `/validate:all`. The two are complementary: `/validate` asks "does the code match the design?"; `/validate:*` asks "does the code meet quality bars?".

## Usage

```
/ai-dev-assistant:validate                    # Validate all
/ai-dev-assistant:validate service            # Validate component
/ai-dev-assistant:validate src/MyService.php  # Validate file
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
- Coding standards *(Drupal: PSR-12)*
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

- `/ai-dev-assistant:complete` - After validation passes
- `/ai-dev-assistant:implement` - Return to implementation

## Integration

Works with:
- `superpowers:verification-before-completion`
- `superpowers:code-reviewer`
