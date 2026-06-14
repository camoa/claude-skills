# Purposeful Code

Ensures code is intentional, comprehensible, and not over-engineered. Verified during `/validate` and `/complete` commands. These principles are stack-neutral. The stack-specific idioms and APIs live in the phase recipes (review checks recipe), which reference the dev-guides knowledge guides.

## Philosophy

**Good code is purposeful code.** Every line should:
- Serve a clear function
- Be understood by the developer who wrote it
- Use real, existing APIs
- Avoid unnecessary defensive patterns

This guidance applies regardless of how code is written, whether by hand, with AI assistance, or generated. The measure is the same: does the developer understand it, and is it necessary?

## Quick Reference

| Area | Good | Bad |
|------|------|-----|
| Error handling | Catch specific errors you can recover from | Wrap everything in try-catch |
| Null checks | Check when a value might actually be null | Check injected dependencies for null |
| Comments | Explain "why" | Describe "what" the code does |
| APIs | Use documented, existing APIs | Call methods that do not exist |

## Unnecessary Try-Catch Blocks

### When Try-Catch Is Appropriate

Wrap an operation that can genuinely fail and that you can do something about (an outbound network call, a parse of external input). Catch the specific error, then log, recover, or rethrow.

### When Try-Catch Is Unnecessary

- Wrapping an operation whose failure is a programming error the platform should surface. Let it bubble.
- An empty catch block, or one that swallows the error silently. That hides bugs and makes failures invisible.

### Checklist
- [ ] Try-catch only wraps operations that can genuinely fail
- [ ] Caught errors are specific, not a catch-all base type
- [ ] Catch blocks actually handle the error (log, recover, rethrow)
- [ ] No empty catch blocks

## Unnecessary Defensive Checks

### Injected Dependencies

A dependency-injection container guarantees a dependency is valid when it is injected. Checking an injected, required dependency for null guards against a state that cannot happen. Trust the container.

### Operations That Throw

When an operation raises on failure rather than returning an empty value, a null check after it is dead code. Let the error surface during development.

### When Null Checks ARE Appropriate

- A lookup that can legitimately return "not found". Check it and handle the absence.
- An optional dependency that may genuinely be unset. Check before use.

### Checklist
- [ ] No null checks on required injected dependencies
- [ ] Null checks only for genuinely nullable values (lookups, optional dependencies)
- [ ] No defensive checks for impossible states

## API Validity

### Hallucinated APIs

Code that calls methods, hooks, services, or events that do not exist. Common with generated code that pattern-matches a plausible name instead of a real one.

### How to Verify

1. **Methods**: Check the interface or class definition.
2. **Extension points**: Check the platform's documented extension-point list.
3. **Dependencies**: Check the service or module registry.
4. **Permissions and routes**: Check the relevant declaration files.

### Common Hallucination Patterns

| What's Called | Reality |
|---------------|---------|
| A plausible-sounding getter | The real accessor has a different name |
| An extension point that "should" exist | No such extension point is defined |
| A dependency by a guessed name | The registered name differs |
| A removed or renamed API | It was deprecated and replaced |

### Checklist
- [ ] All method calls verified against actual interfaces
- [ ] All extension points verified against the platform's documentation
- [ ] All dependencies verified against the registry
- [ ] No deprecated APIs

## Comment Quality

### Good Comments

- Explain *why*, not *what*: the business rule, the constraint, or the non-obvious reason a choice was made.
- Document a non-obvious rule that the code alone cannot convey.

### Bad Comments

- Restate what the code obviously does.
- Read like an instruction or a prompt ("now we loop through the items").
- Describe a function's job in a comment that just paraphrases its name.

### Instruction-Style Comments (Red Flag)

These patterns suggest code was generated without full understanding:

| Pattern | Example |
|---------|---------|
| "Now we..." | `// Now we need to validate the data` |
| "Let's..." | `// Let's check if the user exists` |
| "First/Then/Next..." | `// First, get the record` |
| "This handles..." | `// This handles the form submission` |
| "We will..." | `// We will iterate through the results` |

### Checklist
- [ ] Comments explain reasoning, not obvious behavior
- [ ] No instruction-style language ("now we", "let's")
- [ ] No comments that duplicate what the code clearly shows
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
- [ ] Developer can explain the purpose of each function
- [ ] Developer can predict output for given inputs
- [ ] Developer knows what errors could occur
- [ ] Developer knows why specific patterns were chosen

## Validation Process

During `/validate`, check for:

1. **Try-catch audit**: Are all try-catch blocks necessary?
2. **Null check audit**: Are all null checks for actually nullable values?
3. **API verification**: Do all method, extension-point, and dependency calls exist?
4. **Comment review**: Do comments explain "why"?
5. **Comprehension check**: Can the developer explain each component?

### Blocking Issues
- Calls to non-existent APIs
- Invalid extension-point implementations
- Instruction-style comments indicating lack of understanding
- Developer cannot explain what the code does

### Warning Issues
- Unnecessary try-catch (not swallowing errors)
- Over-defensive null checks
- Comments describing obvious behavior
