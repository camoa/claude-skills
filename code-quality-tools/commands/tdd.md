---
description: Start Test-Driven Development workflow for Drupal/Next.js projects
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# TDD Workflow

Start Test-Driven Development (TDD) workflow with RED-GREEN-REFACTOR cycle.

## Usage

```
/code-quality:tdd [project-path]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Starts test watcher in continuous mode
3. Guides through RED-GREEN-REFACTOR cycle
4. Reports coverage changes

## TDD Cycle

```
RED → Write failing test
GREEN → Write minimal code to pass
REFACTOR → Improve code while keeping tests green
REPEAT → Next feature
```

## Test Watchers

**Drupal:**
- PHPUnit in watch mode (via custom script)
- Auto-runs tests on file changes
- Shows coverage delta

**Next.js:**
- Jest in watch mode (`--watch`)
- Interactive menu for test selection
- Coverage tracking

## Detection & Execution

!cd skills/code-quality-audit && bash scripts/core/detect-project.sh

Based on detection result, executes:
- **Drupal**: `bash scripts/drupal/tdd-workflow.sh`
- **Next.js**: `bash scripts/nextjs/tdd-workflow.sh`

## Interactive Mode

**Drupal TDD Workflow:**
1. Shows current test status
2. Waits for file changes
3. Re-runs affected tests
4. Reports pass/fail with coverage

**Next.js TDD Workflow:**
```
Watch Usage
 › Press a to run all tests.
 › Press f to run only failed tests.
 › Press p to filter by filename pattern.
 › Press t to filter by test name.
 › Press q to quit watch mode.
 › Press Enter to trigger a test run.
```

## Coverage Tracking

TDD workflow tracks coverage incrementally:
- Shows coverage % for changed files
- Alerts if coverage decreases
- Encourages 100% coverage for new code

## Output

- Real-time test results
- Coverage delta (before/after)
- Failure details with stack trace

## Best Practices

1. **Write test first** - RED phase
2. **Minimal implementation** - GREEN phase (just enough to pass)
3. **Refactor** - Improve code quality while tests pass
4. **Commit when green** - Only commit passing code
5. **Keep tests fast** - Under 1 second for unit tests

## Error Handling

Common issues:
- **"Test watcher not starting"**: Run `/code-quality:setup`
- **"Tests too slow"**: Review test isolation, mock external dependencies

See: `references/troubleshooting.md#tdd-workflow-issues`

## Related Commands

- `/code-quality:coverage` - Check overall coverage
- `/code-quality:audit` - Full audit (includes tests)
