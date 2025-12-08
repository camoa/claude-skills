# Command Arguments

Handle user input in slash commands using argument variables.

## Argument Variables

| Variable | Description | Example Input | Value |
|----------|-------------|---------------|-------|
| `$ARGUMENTS` | All arguments as string | `/cmd foo bar baz` | `foo bar baz` |
| `$1` | First argument | `/cmd foo bar` | `foo` |
| `$2` | Second argument | `/cmd foo bar` | `bar` |
| `$3`+ | Third+ arguments | `/cmd a b c d` | `c`, `d` |

## Basic Usage

### Single Argument

```markdown
---
description: Fix a specific issue by number
argument-hint: [issue-number]
---

# Fix Issue

Fix issue #$1:

1. Read the issue details
2. Implement the fix
3. Create appropriate tests
4. Commit with message "fix: resolve issue #$1"
```

**Usage**: `/fix-issue 123`

### Multiple Arguments

```markdown
---
description: Rename a function across the codebase
argument-hint: [old-name] [new-name]
---

# Rename Function

Rename function `$1` to `$2`:

1. Find all occurrences of `$1`
2. Replace with `$2`
3. Update any related documentation
4. Run tests to verify
```

**Usage**: `/rename getUserData fetchUserData`

### All Arguments

```markdown
---
description: Search codebase for patterns
argument-hint: [search-terms...]
---

# Search

Search for: $ARGUMENTS

1. Use grep to find matches
2. List files containing the terms
3. Show relevant context around matches
```

**Usage**: `/search TODO fixme hack` → `$ARGUMENTS` = `TODO fixme hack`

## The argument-hint Field

Provides UI hints for autocomplete:

```yaml
# Single required argument
argument-hint: [file-path]

# Multiple arguments
argument-hint: [source] [destination]

# Optional argument
argument-hint: [environment?]

# Variable arguments
argument-hint: [files...]

# Mixed
argument-hint: [required] [optional?] [extras...]
```

The hint is displayed in autocomplete but does not enforce validation.

## Argument Patterns

### Optional with Default

```markdown
---
description: Deploy to environment
argument-hint: [environment?]
---

# Deploy

Deploy to: ${1:-staging}

If no environment specified, deploy to staging.
```

### Validation in Body

```markdown
---
description: Create component of specific type
argument-hint: [type]
---

# Create Component

Type: $1

Validate type must be one of: button, card, modal, form
If invalid type, list valid options and stop.

Create component of type $1...
```

### Multiple with Bash

```markdown
---
description: Compare two branches
argument-hint: [branch1] [branch2]
---

# Compare Branches

!git diff $1..$2 --stat

Compare branch $1 to $2 based on the diff above.
```

## Common Patterns

### File Path Argument

```markdown
---
argument-hint: [file-path]
---

@$1

Analyze the file above...
```

### Number Argument

```markdown
---
argument-hint: [count]
---

!git log --oneline -$1

Show last $1 commits...
```

### Choice Argument

```markdown
---
argument-hint: [prod|staging|dev]
---

Environment: $1

Based on environment, apply appropriate settings...
```

## Empty Arguments

Handle missing arguments gracefully:

```markdown
---
description: Review file or all changes
argument-hint: [file?]
---

# Review

${1:+Reviewing specific file: $1}
${1:-Reviewing all recent changes}

!git diff ${1:-HEAD~1}
```

## Best Practices

1. **Always provide argument-hint** - improves UX
2. **Document expected format** in command body
3. **Handle missing arguments** - provide defaults or clear errors
4. **Use meaningful variable names** in documentation
5. **Validate in body** when type matters

## Example: Full Command with Arguments

```markdown
---
description: Create a new component with tests
argument-hint: [component-name] [type?]
---

# Create Component

Create component: $1
Type: ${2:-functional}

Steps:
1. Create component file at `src/components/$1.tsx`
2. Create test file at `src/components/$1.test.tsx`
3. Use ${2:-functional} component pattern
4. Add to component index

If type is 'class', use class component pattern.
If type is 'functional' or omitted, use functional pattern with hooks.
```

**Usage**:
- `/create-component Button` → functional Button
- `/create-component Modal class` → class Modal

## See Also

- `writing-commands.md` - command structure
- `command-patterns.md` - bash and file patterns
