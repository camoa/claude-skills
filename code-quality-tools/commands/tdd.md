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
/code-quality:tdd --changed <src.php> [src2.php ...]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Starts test watcher in continuous mode
3. Guides through RED-GREEN-REFACTOR cycle
4. Reports coverage changes

### --changed mode

Scopes test execution to changed source files only — suitable for per-WO gate runs.

```
# Run only the tests mapped from changed sources
/code-quality:tdd --changed web/modules/custom/my_mod/src/Service/MyService.php

# Multiple changed files (typical CI/gate usage)
/code-quality:tdd --changed $(cat .changed-files.txt)
```

**Mapping convention (Drupal):**

```
changed  web/modules/custom/<mod>/src/<Dir>/Foo.php
→ Unit   web/modules/custom/<mod>/tests/src/Unit/<Dir>/FooTest.php
→ Kernel web/modules/custom/<mod>/tests/src/Kernel/<Dir>/FooTest.php
```

Module root = the ancestor directory whose direct child is the `src/` segment.

**Mapping limit — PHPUnit has no `--findRelatedTests`:**

> This flag exists in Jest (Next.js) and is used by the Next.js toolchain.
> PHPUnit has no equivalent. The Drupal mapping here is *structural* —
> it derives test paths from source paths by convention. It does NOT
> perform semantic analysis of import graphs or call sites.

Sources with no co-located `*Test.php` are recorded as **coverage gaps** in
the output. A gap is informational — it is **not a test failure**. The no-`--changed`
path runs the whole suite unchanged.

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
