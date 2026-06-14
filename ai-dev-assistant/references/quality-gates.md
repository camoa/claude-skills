# Quality Gates

Checkpoints enforced during `/complete` and `/validate` commands. The five gate concepts are stack-neutral. The concrete linter and test execution is the domain of the code-quality-tools plugin; this reference defines the concepts and checklists, not the commands.

## Gate Overview

| Gate | When | What | Blocker? |
|------|------|------|----------|
| **Gate 1** | Pre-commit | Code standards | Yes |
| **Gate 2** | Before complete | Tests pass | Yes |
| **Gate 3** | Before complete | Architecture compliance | Yes |
| **Gate 4** | Before complete | Security review | Yes |
| **Gate 5** | Before complete | Code purposefulness | Yes |

## Gate 1: Code Standards

Before committing code, the codebase passes its standards and static-analysis checks. The concrete linters and how they are run belong to the code-quality-tools plugin.

### Checklist
- [ ] Coding-standard checks pass
- [ ] Static analysis passes
- [ ] No linting rules disabled without a documented reason

## Gate 2: Tests Pass

Before marking task complete:

| Check | Verification |
|-------|--------------|
| Unit tests | All pass |
| Integration tests | All pass |
| End-to-end tests | All pass (if applicable) |
| New code coverage | Tests exist for new code |

### Checklist
- [ ] All existing tests pass
- [ ] New code has test coverage
- [ ] No skipped tests without a documented reason
- [ ] Test names describe behavior

## Gate 3: Architecture Compliance

Before completing task:

| Check | Reference |
|-------|-----------|
| SOLID principles | `references/solid.md` |
| DRY patterns | `references/dry-patterns.md` |
| Library-First | `references/library-first.md` |
| TDD followed | `references/tdd-workflow.md` |

### Checklist
- [ ] Units have a single responsibility
- [ ] Dependencies injected (no hidden global lookups)
- [ ] No duplicate code blocks
- [ ] Logic units built before UI
- [ ] Tests written before implementation

## Gate 4: Security

Before deployment, the relevant security concepts are satisfied:

| Area | Check |
|------|-------|
| Input | Validated |
| Output | Escaped or encoded for its context |
| Database | Parameterized queries, no raw concatenation of user input |
| Access | Permissions checked on every entry point |
| CSRF | State-changing requests carry a token |
| Files | Upload types restricted, sensitive files kept private |
| Secrets | Credentials held outside exportable config |
| Logging | No sensitive data in logs |
| Caching | Sensitive content is contextualized correctly |
| Deserialization | No deserialization of untrusted input |

### Checklist
- [ ] All user input validated
- [ ] All output properly escaped or encoded
- [ ] No raw queries built from user input
- [ ] Access checks on all entry points
- [ ] CSRF protection on state-changing operations
- [ ] File uploads restrict allowed types
- [ ] Sensitive files are not publicly served
- [ ] Credentials and secrets kept out of exportable config
- [ ] No passwords or PII in logs
- [ ] No deserialization of untrusted data

## Gate 5: Code Purposefulness

Ensures code is intentional, comprehensible, and not over-engineered.

| Area | Check |
|------|-------|
| Necessity | Every code block serves a clear purpose |
| Complexity | No unnecessary defensive patterns |
| API validity | All called methods and extension points actually exist |
| Comments | Explain "why", not "what" |
| Comprehension | Developer can explain any block |

### Checklist
- [ ] No unnecessary try-catch (the platform handles most errors)
- [ ] No defensive null-checks for values that can't be null
- [ ] All extension-point names are valid
- [ ] All method and dependency calls reference real APIs
- [ ] Comments explain reasoning, not obvious behavior
- [ ] No "instruction-style" comments (LLM prompt artifacts)
- [ ] Developer can explain the purpose of each component

### Red Flags
| Pattern | Problem |
|---------|---------|
| Try-catch around everything | Swallowing errors hides bugs |
| Null checks on injected dependencies | They are never null after injection |
| Comments like "// Handle the case where..." for impossible cases | Over-defensive, bloated code |
| Calls to methods that do not exist | Hallucinated API |
| Comments describing what code does line-by-line | Prompt artifacts or lack of understanding |

**Reference**: `references/purposeful-code.md` for detailed guidance.

## Enforcement Points

| Command | Gates Checked |
|---------|---------------|
| `/validate` | All gates |
| `/complete` | Gate 2, 3, 4, 5 (user confirms Gate 1) |

## Completion Checklist

Before `/complete` succeeds:

```markdown
## Pre-Completion Verification

### Gate 1: Code Standards
- [ ] Coding-standard checks pass
- [ ] Static analysis passes
- [ ] No disabled lint rules

### Gate 2: Tests
- [ ] All tests pass (user confirms)
- [ ] New code has tests

### Gate 3: Architecture
- [ ] SOLID principles followed
- [ ] DRY - no duplication
- [ ] Library-First pattern used

### Gate 4: Security
- [ ] Input validated
- [ ] Output escaped or encoded
- [ ] Access controlled
- [ ] File uploads restricted
- [ ] Secrets kept out of exportable config
- [ ] No sensitive data in logs

### Gate 5: Code Purposefulness
- [ ] No unnecessary try-catch blocks
- [ ] No hallucinated API calls
- [ ] Comments explain "why", not "what"
- [ ] Developer can explain each component

All gates passed? Task can be completed.
```

## Blocking vs Warning

| Severity | Action |
|----------|--------|
| **Blocking** | Cannot complete task until fixed |
| **Warning** | Can complete but should create a follow-up task |

### Blocking Issues
- Security vulnerabilities
- Failing tests
- Missing test coverage for critical paths
- Hidden global lookups in new code (a dependency-injection violation)
- Calls to non-existent APIs or methods
- Excessive try-catch blocks swallowing errors
- Code the developer cannot explain

### Warning Issues
- Minor code style issues
- Missing docblocks
- Low-priority refactoring opportunities
- Over-commented obvious code
