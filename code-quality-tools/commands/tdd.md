---
description: Start Test-Driven Development workflow for Drupal/Next.js projects. Use when user says "test first", "TDD", "write tests", "Red Green Refactor", "test driven", "start TDD", "PHPUnit watch", "Jest watch". Guides through RED-GREEN-REFACTOR cycle with test scaffolding.
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

## Drive the GREEN phase with `/goal`

The RED-GREEN cycle is iterative by nature — a good fit for the built-in `/goal` command, which keeps the session working turn after turn until a fresh evaluator model confirms a completion condition from the transcript.

Once a failing test exists (RED), set a goal for the GREEN phase:

```
/goal all tests in tests/Unit pass and phpstan exits 0, verified by running
the suite — and no test file is modified — or stop after 12 turns
```

Write the condition as a **transcript-checkable end state**: the evaluator does not run tools, it reads what Claude has surfaced, so name the proof (`npm test exits 0`, `the PHPUnit run reports 0 failures`) — not "the feature works". Add constraints that must hold (`no test file is modified`) and an explicit `stop after N turns` bound.

`/goal` requires an accepted workspace-trust dialog and is unavailable when `disableAllHooks` or `allowManagedHooksOnly` is set; in those cases it reports why rather than failing silently. It is a session-scoped interactive / headless-`-p` convenience.

## Error Handling

Common issues:
- **"Test watcher not starting"**: Run `/code-quality:setup`
- **"Tests too slow"**: Review test isolation, mock external dependencies

See: `references/troubleshooting.md#tdd-workflow-issues`

## Related Commands

- `/code-quality:coverage` - Check overall coverage
- `/code-quality:audit` - Full audit (includes tests)
