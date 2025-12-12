# SOLID Principles for Drupal

Architecture principles enforced during Phase 2 design.

## Quick Reference

| Principle | Rule | Drupal Application |
|-----------|------|-------------------|
| **S** - Single Responsibility | One class = one job | Services do one thing, plugins handle single operations |
| **O** - Open/Closed | Extend, don't modify | Use hooks, events, plugins for extension |
| **L** - Liskov Substitution | Subtypes are substitutable | Interface contracts must be honored |
| **I** - Interface Segregation | Lean interfaces | Targeted plugin types, not mega-interfaces |
| **D** - Dependency Inversion | Depend on abstractions | Inject via services.yml, never `\Drupal::service()` |

## Single Responsibility (S)

Each class/service has ONE job.

| Good | Bad |
|------|-----|
| `TokenGenerator` generates tokens | `AuthService` that generates, validates, AND logs |
| `EmailSender` sends emails | `UserManager` that sends emails, creates users, AND validates |
| `PriceCalculator` calculates prices | `OrderService` that calculates, persists, AND notifies |

**Enforcement**: During `/design`, verify each service has single, clear purpose.

## Open/Closed (O)

Open for extension, closed for modification.

**Drupal patterns**:
- Hooks allow extending without modifying core
- Events enable custom reactions
- Plugin systems add functionality without touching base classes

**Enforcement**: Identify extension points (hooks, events, plugins) during design.

## Liskov Substitution (L)

Any implementation must honor its interface contract.

**Drupal patterns**:
- `EntityInterface` implementations work wherever entities expected
- Custom plugins work wherever plugin type expected
- Service replacements honor original interface

**Enforcement**: Define interfaces before implementations.

## Interface Segregation (I)

Clients shouldn't depend on methods they don't use.

| Good | Bad |
|------|-----|
| `TokenGeneratorInterface` with `generate()` | `AuthInterface` with 20 unrelated methods |
| Targeted plugin types | One mega-plugin that does everything |
| Focused service interfaces | Kitchen-sink service interfaces |

**Enforcement**: Keep interfaces lean and focused.

## Dependency Inversion (D)

Depend on abstractions, not concretions.

| Good | Bad |
|------|-----|
| Inject via `services.yml` | Call `\Drupal::service()` in class |
| Type-hint interfaces | Type-hint concrete classes |
| Constructor injection | Static method calls |

**Enforcement**: All dependencies must be injected, never hardcoded.

## Architecture Phase Checklist

Before completing `/design`, verify:

- [ ] Each service has single responsibility
- [ ] Extension points identified (hooks, events, plugins)
- [ ] Interfaces defined for services
- [ ] Dependencies will be injected via services.yml
- [ ] No static `\Drupal::` calls planned in services

## Common Violations

| Violation | Detection | Fix |
|-----------|-----------|-----|
| God class | Service does 5+ unrelated things | Split into focused services |
| Hidden dependency | `\Drupal::service()` in constructor | Inject via services.yml |
| Tight coupling | Direct class instantiation | Use dependency injection |
| Interface bloat | Interface has 10+ methods | Split into focused interfaces |
