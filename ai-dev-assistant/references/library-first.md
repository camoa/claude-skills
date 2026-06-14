# Library-First and CLI-First Development

Architecture principles enforced during Phase 2 design. These are stack-neutral. The framework-specific instantiation lives in the phase recipes (design architecture recipe), which reference the dev-guides knowledge guides.

## Library-First Principle

Build functionality as reusable logic units (services or libraries) BEFORE adding any UI.

### The Pattern

```
1. Service / library unit
   ↓ Business logic, testable, reusable
2. UI layer (form, view, controller)
   ↓ Uses the service, handles presentation only
3. Routing / entry point
   ↓ Exposes the UI
```

### Why Library-First?

| Benefit | Explanation |
|---------|-------------|
| Testable | Logic units can be tested in isolation |
| Reusable | Multiple UIs can use the same logic |
| Maintainable | Business logic separate from presentation |
| CLI-ready | A command-line entry point can use the same logic |

### Enforcement

During `/design`, verify:

- [ ] Logic unit designed BEFORE the UI layer
- [ ] Logic unit usable without any UI
- [ ] Business logic in the logic unit, NOT in the UI layer
- [ ] UI only handles display, validation, and routing to the logic unit

### Anti-Patterns

| Bad | Good |
|-----|------|
| Business logic in a form submit handler | Form calls a service method |
| Controller does calculations | Controller calls a service |
| Data queries in the UI layer | A service handles data access |

## CLI-First Principle

Every feature should be reachable from a command-line entry point, not only the UI.

### The Pattern

```
1. Service / library unit (business logic)
   ↓
2. Command-line entry point
   ↓ Exposes the logic via CLI
3. UI layer
   ↓ Also uses the same logic
```

### Why CLI-First?

| Benefit | Use Case |
|---------|----------|
| Automation | Scheduled tasks |
| Scripting | Batch operations |
| CI/CD | Automated deployments |
| Testing | Quick manual verification |
| Performance | No browser overhead |

### Enforcement

During `/design`, verify:

- [ ] A command-line entry point is planned alongside any admin UI
- [ ] The command uses the SAME logic unit as the UI
- [ ] No UI-only features (everything is reachable from the CLI)

## Design Phase Checklist

Before completing `/design`:

### Library-First
- [ ] Logic units defined for all business logic
- [ ] Logic units have interfaces
- [ ] UI layers only orchestrate, they don't contain logic
- [ ] Dependencies injected into the logic units

### CLI-First
- [ ] A command-line entry point is planned for each major feature
- [ ] Commands use the same logic units as the UI
- [ ] Command arguments and options documented
- [ ] No feature is UI-only

## Common Violations

| Violation | Detection | Fix |
|-----------|-----------|-----|
| Logic in the UI | A submit handler has calculations | Move it to a logic unit |
| UI-only feature | No command-line entry point exists | Add one |
| Data access in the UI | Direct queries in a form | Create a data service |
| No logic layer | The UI does everything | Extract a logic unit first |
