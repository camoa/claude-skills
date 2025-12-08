# Code Patterns to Check

## Good Patterns

### Single Responsibility
- Functions do one thing
- Classes have one reason to change
- Modules have focused purpose

### Clear Naming
- Variables describe their content
- Functions describe their action
- Constants are SCREAMING_CASE

### Error Handling
- Errors are caught and handled
- User-friendly error messages
- Proper error propagation

## Anti-Patterns to Flag

### Code Smells
- Functions longer than 50 lines
- Deeply nested conditionals (>3 levels)
- Magic numbers without explanation
- Commented-out code blocks
- Duplicate code blocks

### Security Issues
- Hardcoded credentials
- SQL string concatenation
- Unsanitized user input
- Exposed API keys

### Performance Issues
- N+1 queries
- Missing indexes
- Unnecessary loops
- Large objects in memory

## Review Checklist

- [ ] No hardcoded secrets
- [ ] Error handling present
- [ ] Functions are focused
- [ ] Names are descriptive
- [ ] No obvious duplications
