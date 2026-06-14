# TDD Workflow

Test-Driven Development principles enforced during Phase 3 implementation. The Red-Green-Refactor cycle and the test tiers below are stack-neutral. The concrete test runner, directory layout, and base classes for a given stack live in the phase recipes (implement standards-and-tests recipe), which reference the dev-guides knowledge guides.

## The Non-Negotiable Rule

**Tests MUST precede implementation. No exceptions.**

Before writing ANY implementation code, ask: "Is there a failing test for this?"

## Red-Green-Refactor Cycle

| Phase | Action | Checkpoint |
|-------|--------|------------|
| **RED** | Write failing test | Test MUST fail. If it passes, the test is wrong. |
| **GREEN** | Write minimal code to pass | Only enough to pass. No extras. |
| **REFACTOR** | Improve code quality | Tests must stay green. |

## When to Apply TDD

| Component | TDD Required | Test Tier |
|-----------|--------------|-----------|
| Logic units with business rules | **YES - Always** | Unit or Integration |
| Validation logic | **YES** | Unit |
| Pluggable behaviors (actions, conditions) | **YES** | Integration |
| Lifecycle hooks and event handlers | **YES** | Integration |
| Access-control logic | **YES** | Integration |
| Simple getters and setters | Optional | Unit |
| Presentation templates | No | End-to-end |

## Test Tiers

| Tier | Use For | Isolation |
|------|---------|-----------|
| Unit | Pure logic, no platform bootstrap | Full (dependencies mocked) |
| Integration | Logic against real dependencies (data store, container) | Partial (real wiring) |
| End-to-end | Full request through the running system | None (full bootstrap) |

## Integration Over Mocks

Prefer integration tests with real dependencies over unit tests with heavy mocking:
- Use the actual data store, cache, and object wiring where practical.
- Mock only external APIs and third-party services.
- A real dependency-injection container catches wiring bugs that mocks hide.

## Enforcement Checkpoints

During `/implement`, verify at each step:

1. **Before coding**: "What test verifies this works?"
2. **Write test**: Confirm it fails (RED)
3. **Write code**: Minimal implementation only
4. **Run test**: Confirm it passes (GREEN)
5. **Refactor**: Only if tests stay green

## Red Flags to Intercept

| Developer Says | Response |
|----------------|----------|
| "Let me just add this feature..." | "Stop. Is there a test?" |
| "I'll add tests later..." | "Tests first. What behavior are we testing?" |
| "This is too simple for tests..." | "Simple now, complex later. Test it." |
| "Let me implement multiple things..." | "One test, one feature at a time." |

## User-Controlled Testing

- Claude suggests test commands but does NOT auto-run them.
- The user executes the tests.
- The user reports results back to Claude.
- Claude responds based on pass or fail.
