# TDD Workflow

Test-Driven Development principles enforced during Phase 3 implementation. The Red-Green-Refactor cycle and the test tiers below are stack-neutral. The concrete test runner, directory layout, and base classes for a given stack live in the phase recipes (implement standards-and-tests recipe), which reference the dev-guides knowledge guides.

## The Non-Negotiable Rule

**Tests MUST precede implementation. No exceptions.**

Before writing ANY implementation code, ask: "Is there a failing test for this?"

## Red-Green-Refactor Cycle

| Phase | Action | Checkpoint |
|-------|--------|------------|
| **RED** | Write failing test | Test MUST fail. If it passes, the test is wrong. |
| **GREEN** | Write minimal code to pass | Only enough to pass. No extras. |
| **REFACTOR** | Improve code quality | Tests must stay green. |

## When to Apply TDD

| Component | TDD Required | Test Tier |
|-----------|--------------|-----------|
| Logic units with business rules | **YES - Always** | Unit or Integration |
| Validation logic | **YES** | Unit |
| Pluggable behaviors (actions, conditions) | **YES** | Integration |
| Lifecycle hooks and event handlers | **YES** | Integration |
| Access-control logic | **YES** | Integration |
| Simple getters and setters | Optional | Unit |
| Presentation templates | No | End-to-end |

## Test Tiers

| Tier | Use For | Isolation |
|------|---------|-----------|
| Unit | Pure logic, no platform bootstrap | Full (dependencies mocked) |
| Integration | Logic against real dependencies (data store, container) | Partial (real wiring) |
| End-to-end | Full request through the running system | None (full bootstrap) |

## Integration Over Mocks

Prefer integration tests with real dependencies over unit tests with heavy mocking:
- Use the actual data store, cache, and object wiring where practical.
- Mock only external APIs and third-party services.
- A real dependency-injection container catches wiring bugs that mocks hide.

## Enforcement Checkpoints

During `/implement`, verify at each step:

1. **Before coding**: "What test verifies this works?"
2. **Write test**: Confirm it fails (RED)
3. **Write code**: Minimal implementation only
4. **Run test**: Confirm it passes (GREEN)
5. **Refactor**: Only if tests stay green

## Red Flags to Intercept

| Developer Says | Response |
|----------------|----------|
| "Let me just add this feature..." | "Stop. Is there a test?" |
| "I'll add tests later..." | "Tests first. What behavior are we testing?" |
| "This is too simple for tests..." | "Simple now, complex later. Test it." |
| "Let me implement multiple things..." | "One test, one feature at a time." |

## Who runs the tests, and what has to be recorded

The RED step is an **observation**, not an intention. "I wrote the test first" and "I watched
the test fail before the code existed" are different claims, and only the second one is TDD.
Everything below exists because the first claim is free to make and was, until v5.34.0, the
only one anything in this framework ever recorded.

### Who runs them depends on `run_mode`

The predecessor to this section said, flatly, that the user executes the tests and reports
results back. That is right for an attended build and impossible for an unattended one:
`run_mode: autonomous` has no user in the loop to run anything, so the rule as written left
the autonomous path with a mandatory step nobody could perform and no instruction to fall back
on. An agent reaching that point had to invent an answer or stop and ask, which is what a live
run did.

Read `run_mode` from disk (`scripts/project-state-read.sh "<project_folder>"` → `.runMode`,
with a task override via `scripts/fm-read.sh "<task_folder>"` → `.run_mode`) and follow the
matching row. Neither row is a licence to skip the observation.

| `run_mode` | Who runs the test | How RED is observed |
|---|---|---|
| `interactive` (default) | The user, unless they have said otherwise for this project | Claude gives the exact command; the user runs it and reports the result back |
| `autonomous` | The agent, because there is nobody else | The agent runs the command itself and keeps the exit code |

### When the build is delegated (v5.48.0+)

Everything above reads as though a build is something the main context does. Often it is not. A
`/run-work-orders` build hands each unit to a fresh subagent, and that subagent inherits none of
this: not the methodology floor `/implement` loads, not the activated `tdd-companion`, not the
loop that records an outcome per criterion. **The discipline was not weak on that path. It was
absent**, and the framework demanded a TDD record of the in-session record and of nothing else,
so following an orchestration rule that says the main loop coordinates rather than builds routed
every real build around this rung by construction. Measured on a live build: three components
built, reviewed and merged with no TDD record of any kind, every downstream check satisfied,
because each one reads a record nobody was asked to write.

**The unit of the record is the unit of work, not the phase.** A delegated builder writes its own
record and the orchestrator collects rather than authoring on its behalf. The whole path, end to
end:

1. **`skills/work-order-builder`** states the obligation in the prompt it hands the subagent and
   names one absolute path to write it to: `<WO_DIR>/wo-NN.tdd.json`, beside that work-order's
   `wo-NN.run.json` and `wo-NN._critique.json`. It is the only file the BUILDER writes outside its
   build root; the atom separately flips `status:` on `wo-NN.md` in the same directory, before any
   code is mutated.
2. **The builder** writes ONE JSON object there: `{red_observed, passed_first_run, ratified,
   unobserved[], reason}` — the same shape an in-session `_build-critique.json` carries, so
   `/review` reads one record and not two.
3. **The build atom does nothing with it.** It does not read the file, validate it, or carry it in
   the handle. The handle is derived from git and disk and structurally accepts no subagent content
   (M-6), which is exactly why the record travels beside it rather than inside it.
4. **The loop** (`work-order-loop`, `work-order-loop-parallel`) computes the same path from the
   work-order id it is already looping over and runs `wo-run-state.sh collect --tdd-file <path>`
   when the file is there. No file ⇒ no flag ⇒ no `tdd` key, and nothing invents a default.
   `wo-run-state.sh` parses and type-checks the content before storing it and refuses a malformed
   one outright, because the content is subagent output even though the channel is a file.
5. **`/review`'s build-critique gate** fails a work-order whose run record carries no `tdd` block,
   fail-closed and unresolved.

**A file, not a line in the builder's reply.** Every other subagent-produced value in this plugin
already moves this way — `wo-critic` writes `wo-NN._critique.json`, `architecture-validator` writes
`_arch-validate-<slug>.json`, `distill-agent` writes `_distill.json` — and `commands/review.md`
step 5.0 records the measurement behind it: an agent whose report was its Task response alone had
that response truncate in transit repeatedly, and the session had to improvise a scratchpad file
mid-review to recover it. A record asked for as a trailing line in a reply has no reader and no
path. On a file, both ends derive the path from data they already hold, so a truncated reply costs
nothing.

`run_mode` still decides who runs the test, by the table above. A delegated builder is running
unattended by definition, so its rows are the `autonomous` ones: it runs the command and keeps the
exit code. What it must not do is infer a RED it did not watch, which is the same rule as
everywhere else here and is why `unobserved[]` is a value it can return rather than a failure.

**What this does not fix.** The record is a self-report, exactly as the in-session one is. Moving
it from a reply to a file fixed the delivery, not the trust: the builder still writes its own
numbers, nothing captures the runner's exit code into the record, and a builder that writes nothing
is caught only downstream, by a gate that fails on the absence. This closes the gap between
recorded and unrecorded on a path where nothing was recorded at all. It does not close the gap
between recorded and true.

**A targeted run is part of the cycle, not a test-suite sweep.** A project instruction along the
lines of "I run the test suites, not you" is about unattended whole-suite runs; a single
`--filter`-scoped invocation whose entire purpose is to watch one new test fail is the RED step
itself. If a project genuinely wants Claude to run nothing at all, that is a legitimate choice
and it makes RED user-observed, not unobserved: the user still runs it and still reports back.
What is never legitimate is nobody running it and the build continuing as though somebody had.

### The observation gets recorded

Whoever runs it, the result is recorded per acceptance criterion, and `unobserved` is a real
value that must be written down rather than implied by silence:

| Value | Meaning |
|---|---|
| `observed` | The test was run before the implementation existed and failed **at its own assertion, for the reason it names** |
| `passed_first_run` | It was run and it passed, and the test is wrong: `tdd-companion`'s named violation. The reason says what happened |
| `ratified` | It passed the moment it was written, because the code it describes already existed — a characterization or regression test. Counted apart from `observed`, never standing in for it |
| `unobserved` | Nobody ran it. Legal to record, never legal to leave unsaid |

**Which value applies turns on what the test's author was reading, not on the order the commands
ran in.** That distinction, and the three proxies for judging it, live in
`development/tdd-spec-driven/what-a-failing-test-proves` and are not restated here.

**A failure is not automatically a RED.** A test that dies in `setUp` — a missing schema, an
unregistered service the test itself needs, a database error — has failed without ever reaching
the behaviour it exists to check, and recording that as `observed` credits the cycle with an
observation nobody made. Read the failure before you count it: it must come from the assertion
or from the missing production code the test names, not from the harness around it. Seen live on
this framework's own build, where the first run of a new kernel test failed on an uninstalled
contrib entity schema; the second, after the harness was fixed, failed on the absent service,
and only the second was a RED.

`/implement` carries these into the component's `_build-critique.json` at loop step 8, and
`/review`'s build-critique gate reads them back. An `unobserved` criterion does not silently
fail the build, but it does stop the phase from claiming a discipline it did not follow.
