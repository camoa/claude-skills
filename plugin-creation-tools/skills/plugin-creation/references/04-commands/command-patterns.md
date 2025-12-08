# Command Patterns

Advanced patterns for building powerful slash commands.

## Bash Execution

Prefix lines with `!` to execute bash commands. Output is included in context:

```markdown
---
description: Show git status and recent commits
---

# Git Summary

!git status
!git log --oneline -5

Based on the above, summarize the current state of the repository.
```

The bash output appears before Claude processes the rest of the command.

### Multiple Bash Commands

```markdown
!npm test 2>&1 | head -50
!npm run lint

Review the test and lint results above. Identify failures and suggest fixes.
```

### Bash with Arguments

```markdown
!git show $1

Analyze the commit shown above.
```

## File References

Use `@` prefix to include file contents:

```markdown
---
description: Analyze a specific file for issues
argument-hint: [file-path]
---

# Analyze File

@$1

Review the file above for:
1. Code quality
2. Potential bugs
3. Security issues
```

### Multiple File References

```markdown
Compare these two files:

@src/old-implementation.js
@src/new-implementation.js

Identify differences and evaluate the changes.
```

### Static File References

```markdown
Review the following configuration:

@package.json
@tsconfig.json

Identify any compatibility issues.
```

## Namespacing with Subdirectories

Organize commands with subdirectories:

```
commands/
├── frontend/
│   ├── component.md    → /frontend:component
│   └── style.md        → /frontend:style
├── backend/
│   ├── api.md          → /backend:api
│   └── database.md     → /backend:database
└── deploy.md           → /deploy
```

Commands in subdirectories get a namespace prefix.

### Invocation

```
/frontend:component Button   # With namespace
/deploy staging              # Root level
```

## Combining Patterns

### Bash + File Reference

```markdown
---
description: Review changes in a specific file
argument-hint: [file]
---

# File Change Review

!git diff $1

Current file content:
@$1

Review the changes shown in the diff. Provide feedback.
```

### Arguments + Bash + Conditional

```markdown
---
description: Run tests for specific module
argument-hint: [module-name]
---

# Test Module

!npm test -- --grep="$1" 2>&1

Analyze the test results. If failures exist:
1. Identify root cause
2. Suggest fixes
3. Show corrected code
```

## Tool Restriction Patterns

### Read-Only Analysis

```markdown
---
description: Analyze codebase without modifications
allowed-tools: Read, Grep, Glob
---
```

### Git Operations Only

```markdown
---
description: Git workflow helper
allowed-tools: Bash(git:*)
---
```

### Specific Tool Combination

```markdown
---
description: Refactor with testing
allowed-tools: Read, Edit, Bash(npm test:*)
---
```

## Conditional Content

Include instructions that vary based on input:

```markdown
---
description: Deploy to environment
argument-hint: [prod|staging|dev]
---

# Deploy

Target environment: $1

If deploying to prod:
1. Ensure all tests pass
2. Create backup
3. Deploy with rollback ready

If deploying to staging or dev:
1. Run quick smoke tests
2. Deploy directly
```

## Error Handling Patterns

```markdown
---
description: Safe database migration
allowed-tools: Bash, Read
---

# Safe Migration

!npm run db:status

Before proceeding:
1. Verify database is accessible
2. Check for pending migrations
3. If any issues found, STOP and report

Only if all checks pass:
!npm run db:migrate
```

## Best Practices

1. **Use bash for context gathering**, not for all operations
2. **File references load full content** - be mindful of large files
3. **Namespaces organize related commands** - use for teams
4. **Combine patterns thoughtfully** - don't overcomplicate

## See Also

- `writing-commands.md` - basic command structure
- `command-arguments.md` - argument handling
