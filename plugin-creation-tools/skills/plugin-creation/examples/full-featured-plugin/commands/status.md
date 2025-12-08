---
description: Show project status including git state, recent changes, and pending tasks
allowed-tools: Bash, Read, Glob
---

# Project Status

Provide a comprehensive status report for the current project.

## Steps

1. Run `git status` to show working tree state
2. Run `git log --oneline -5` to show recent commits
3. Check for TODO comments in code: `grep -r "TODO" --include="*.py" --include="*.js" --include="*.ts" .`
4. Summarize findings in a clear format

## Output Format

```
## Git Status
[git status output]

## Recent Commits
[last 5 commits]

## Pending TODOs
[list of TODO comments found]

## Summary
[brief summary of project state]
```
