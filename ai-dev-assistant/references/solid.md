# SOLID Principles

Architecture principles enforced during Phase 2 design. These are stack-neutral. The framework-specific instantiation lives in the phase recipes (design architecture recipe), which reference the dev-guides knowledge guides.

## Quick Reference

| Principle | Rule | Application |
|-----------|------|-------------|
| **S** - Single Responsibility | One unit = one job | A class or module does one thing |
| **O** - Open/Closed | Extend, don't modify | Add behavior through extension points, not edits to existing code |
| **L** - Liskov Substitution | Subtypes are substitutable | Implementations honor their interface contracts |
| **I** - Interface Segregation | Lean interfaces | Targeted, focused interfaces, not mega-interfaces |
| **D** - Dependency Inversion | Depend on abstractions | Inject dependencies, depend on interfaces, not concretions |

## Single Responsibility (S)

Each class or module has ONE job.

| Good | Bad |
|------|-----|
| `TokenGenerator` generates tokens | `AuthService` that generates, validates, AND logs |
| `EmailSender` sends emails | `UserManager` that sends emails, creates users, AND validates |
| `PriceCalculator` calculates prices | `OrderService` that calculates, persists, AND notifies |

**Enforcement**: During `/design`, verify each unit has a single, clear purpose.

## Open/Closed (O)

Open for extension, closed for modification.

- Use the platform's extension points (events, listeners, plugin or strategy patterns) to add behavior.
- Adding a feature should not require editing existing, working code.

**Enforcement**: Identify extension points during design.

## Liskov Substitution (L)

Any implementation must honor its interface contract.

- Any implementation of an interface works wherever that interface is expected.
- A replacement honors the original contract (same pre and post conditions).

**Enforcement**: Define interfaces before implementations.

## Interface Segregation (I)

Clients shouldn't depend on methods they don't use.

| Good | Bad |
|------|-----|
| `TokenGeneratorInterface` with `generate()` | `AuthInterface` with 20 unrelated methods |
| Targeted, focused interfaces | One mega-interface that does everything |
| Cohesive contracts | Kitchen-sink contracts |

**Enforcement**: Keep interfaces lean and focused.

## Dependency Inversion (D)

Depend on abstractions, not concretions.

| Good | Bad |
|------|-----|
| Inject dependencies | Reach out to a global service locator inside a class |
| Type-hint interfaces | Type-hint concrete classes |
| Constructor injection | Static method calls |

**Enforcement**: All dependencies must be injected, never hardcoded.

## Architecture Phase Checklist

Before completing `/design`, verify:

- [ ] Each unit has a single responsibility
- [ ] Extension points identified
- [ ] Interfaces defined for the units that need them
- [ ] Dependencies will be injected
- [ ] No hidden global lookups planned inside units

## Common Violations

| Violation | Detection | Fix |
|-----------|-----------|-----|
| God class | A unit does 5+ unrelated things | Split into focused units |
| Hidden dependency | Global lookup inside a constructor | Inject the dependency |
| Tight coupling | Direct instantiation of concretions | Use dependency injection |
| Interface bloat | An interface has 10+ methods | Split into focused interfaces |
