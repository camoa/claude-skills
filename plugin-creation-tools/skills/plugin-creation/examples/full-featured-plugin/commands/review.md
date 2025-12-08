---
description: Review a file or recent changes for code quality issues
allowed-tools: Bash, Read, Grep, Glob
argument-hint: [file-path]
---

# Code Review

Review the specified file or recent changes for code quality.

## Arguments

- `$1`: File path to review (optional, defaults to recent changes)
- `$ARGUMENTS`: All arguments passed

## Steps

If file specified ($1):
1. Read the file at $1
2. Apply code-helper skill patterns
3. Report findings

If no file specified:
1. Run `git diff --name-only HEAD~1` to find changed files
2. Review each changed file
3. Report findings per file

## Output Format

```
## File: [filename]

### Issues Found
- [issue 1]
- [issue 2]

### Suggestions
- [suggestion 1]
- [suggestion 2]

### Overall Assessment
[brief assessment]
```
