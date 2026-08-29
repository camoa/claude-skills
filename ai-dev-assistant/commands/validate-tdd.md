---
description: "Run the TDD quality gate on demand and persist the result to the current task folder. Thin wrapper around /code-quality:tdd — adds task context, persistence, and the shared result envelope. Soft-nudge: reports fail verdict but never blocks. Introduced v3.13.0."
allowed-tools: Read, Write, Bash, Glob, Skill
argument-hint: "[<task-name>]"
---

# Validate: TDD

Run the TDD (Red-Green-Refactor discipline) quality gate against the current task. Wraps `/code-quality:tdd` from the `code-quality-tools` plugin; adds task-context resolution, result persistence to the task folder, and emits the shared result envelope (`references/validation-gate-result.md` v1.1).

## Usage

```
/ai-dev-assistant:validate-tdd                          # run against current task from session context
/ai-dev-assistant:validate-tdd <task-name>              # run against a specific task
/ai-dev-assistant:validate-tdd <task> --files <path>    # change-scoped: forward <path> as --changed to the underlying check
```

## What this does

1. **Resolve task context** — resolve the project folder in this order:
   (a) run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-read.sh` (Bash) and parse its JSON (`.project`, `.projectPath`, `.task`, `.taskPath`) if it resolves — it carries the active project's absolute path
   (b) walk up from `$PWD` until you find a directory containing `implementation_process/`
   (c) abort with "no project context — run /ai-dev-assistant:next first, or cd to a project workspace" if neither resolves

   Then resolve the task folder: if `<task-name>` arg is given, locate it under `<project>/implementation_process/in_progress/**/<task-name>/` (glob handles both flat and sub-epic nesting). If no arg, use the task from the `session-context-read.sh` output (`.task`/`.taskPath`). If the task doesn't resolve, abort with candidate suggestions.

2. **Verify dependency (v5.33.0+ — a resolved version, not a non-empty directory).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/plugin-dep-check.sh code-quality-tools 3.0.0` (Bash) and branch on `.status`. **`ok`** — proceed, and use the returned `path` if you need to read anything out of that plugin; it is the newest installed version resolved by version order, which is not the same as the first or last directory a glob returns. **`too_old`** — abort, naming `resolved_version` and the 3.0.0 minimum, with upgrade instructions: a wrapper aimed at an interface that version does not have produces a confident wrong verdict. **`undetermined`** — do NOT abort. The script can only see the marketplace cache, and the plugin may be installed from elsewhere; proceed and print one line saying the version could not be confirmed, so an unverified dependency never passes silently as a verified one. **`unreadable`** — same as `undetermined`, with its reason.

   The predecessor to this step confirmed the directory was non-empty and then declared a 3.0.0 minimum it never checked, so a cache holding only 2.x passed. Separately, a live run resolved that plugin's path with a lexically-sorted glob and read 3.9.6 while 3.9.8 sat beside it.

3. **Invoke the check** — execute the `/code-quality:tdd` flow as documented in the `code-quality-tools` plugin's `commands/tdd.md` within this command's own execution context. Do NOT attempt to shell out to the sibling slash command. If a `--files <list>` parameter was supplied to this wrapper, forward it to the underlying flow as `--changed <list>` — this scopes the gate to the listed files; the code-quality tool handles the empty-list → clean-skip case internally. **When `--files` is absent, do not invoke the underlying flow at all** — see path A of "Verdict interpretation" for what that mode is and why it is `unresolved`. Capture the exit code and console output for step 4.

4. **Resolve the verdict with the script** — run `${CLAUDE_PLUGIN_ROOT}/scripts/gate-verdict-resolve.sh tdd "" --exit-code "<the gate's exit status>"` (Bash) and use its JSON verbatim per "Verdict interpretation" below. This gate writes no report, so the path argument is empty and the exit code carries the whole answer; the resolver knows that and does not treat the absence as unresolved. `raw_output_path` in `--details` stays `null`. Pass `messages[]` through unedited and `evidence{}` into `--details`.

5. **Emit and persist the envelope** — call `${CLAUDE_PLUGIN_ROOT}/scripts/validation-envelope-write.sh` (Bash) with the verdict, the findings and this gate's `details`. See "Emitting the envelope" below. The script builds the envelope and writes both files; do not assemble the JSON by hand.

6. **Check the exit code** — 0 means both writes succeeded. 1 is a write failure (missing task folder, permissions) — carry on and say so in the CLI summary. 2 means the arguments were rejected and nothing was written; fix the call rather than falling back to a hand-written file.

7. **Print CLI summary** — show verdict, top 3 messages, and the persisted-result paths. When invoked non-interactively (chained from `/validate:all` or CI equivalents), signal verdict via exit code: 0 for `pass`/`warning`/`skipped`; 1 for `fail`. In interactive use the printed summary IS the signal — Claude does not literally exit the session. User workflow is NEVER blocked regardless of verdict.

## Where the result comes from

**`scripts/gate-verdict-resolve.sh` decides the verdict. This file does not.** It used to
carry the mapping as prose, and prose got the field paths wrong every round it was
rewritten: `security-report.json` has no top-level `.status` (it is
`.summary.overall_status`), `meta.tools[]` does not exist in `--changed` mode, and
`dry-report.json` has no `tools_failed` at all. Each was a claim about a producer, and a
claim about a producer is only checkable by reading the producer — which
`tests/gate-verdict-resolve-spec.sh` now does, against every path the resolver declares.
A table in a command file cannot be run, so it was never checked, so it was wrong.

**This gate writes no JSON report on any path**, and says so where it sets its exit
codes: "This gate writes no JSON report, so the exit code is not a fallback channel — it
is the only one there is." So pass an empty report path and the exit code; the resolver
resolves this gate from the code alone, and does NOT treat the absent report as
unresolved. Doing so would mark every TDD run on every project unresolved and fail-close
every review, on a gate behaving exactly as designed.

Exit `4` is `CQT_EXIT_UNMEASURED` — no test runner, nothing tested — and is the one state
that must not read as a finding. It is `unresolved`.

**When `--files` is absent, do not invoke the underlying flow at all.** There is no
whole-project TDD mode: `code-quality-tools/commands/tdd.md` calls `tdd-workflow.sh` with
no argument, the script defaults `ACTION="${1:-help}"`, and the "whole-project scan" is its
usage text printed to stdout. Emit `verdict: "skipped"` with `unresolved: true` naming the
missing capability. Do not synthesise a whole-tree mode by enumerating the tree and passing
it as `--changed`: on any project that vendors its framework that means mapping every core
and vendor source to a co-located test, which is both wrong and unbounded.

**This gate has no partial state either** — one channel, one question — so it never sets
`coverage_partial`.

## Verdict interpretation

There is no table here on purpose. Run the resolver and use what it returns:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gate-verdict-resolve.sh" tdd "<report path>" \
  --exit-code "<the gate's exit status>" --not-before "<the step-3 timestamp>"
```

It prints one JSON object:

| Field | Use it for |
|---|---|
| `verdict` | the envelope's `--verdict`, verbatim: `pass` \| `warning` \| `fail` \| `skipped` |
| `unresolved` | `true` ⇒ **nothing** was measured. The resolver has already put the literal `unresolved: true` in `messages[]`; pass those messages through unchanged. `/review` step 8 rule 2 reads it and fails closed |
| `coverage_partial` | `true` ⇒ **part** of it was measured. Same deal: the literal `coverage_partial: true` is already in `messages[]`, and `/review` step 8 rule 4 fails closed on it |
| `messages[]` | one `--message` per entry, in order. **Do not edit, reorder or drop any of them** — the two markers live in here, and a marker a caller trims is a green review |
| `evidence{}` | put it in `--details` as-is. It records which fields were read and what they held, so a verdict can be argued with |
| `measured`, `mode` | context for the CLI summary |

Both markers are never set at once: nothing-measured and part-measured are different
facts. An ordinary `warning` — a real, complete measurement whose number sits over a soft
threshold — carries **neither**, and stays exactly as non-blocking as it has always been.
Failing those would block projects where every tool is installed and teach everyone to
reach for `--skip-tdd`, which is the bypass that makes this whole mechanism worthless.

**If the resolver cannot be run**, emit `verdict: "skipped"` with `unresolved: true` and
say so. Do not fall back to reading the console text: guessing from prose is the thing
this replaced.

## Emitting the envelope (per `references/validation-gate-result.md`)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/validation-envelope-write.sh" gate \
  --gate tdd \
  --task "<task_name>" \
  --task-folder "<abs path to the task folder>" \
  --verdict "<pass|warning|fail|skipped>" \
  --details "$(jq -n \
      --arg raw "" \
      --arg cqt "<version from plugin.json of code-quality-tools>" \
      '{source: "code-quality-tools:tdd",
        raw_output_path: (if $raw == "" then null else $raw end),
        code_quality_tools_version: $cqt}')" \
  --message "<one finding>" \
  --message "<the next finding>"
```

One `--message` per finding, repeated as many times as there are findings; none
at all is fine. The script derives `status` from the verdict, `timestamp` from
one clock read, and one `findings[]` entry per message carrying the severity the
verdict implies, so those fields cannot disagree with the ones they mirror.
Message text goes through `jq --arg`, so quotes, newlines and shell
metacharacters in a tool's output are safe to pass straight through.

`--details` is this gate's own detail object and is passed through verbatim.

## Persistence

`validation-envelope-write.sh` does both writes itself:

1. `<task_folder>/validations/latest/tdd.json` — overwritten, via temp file + rename
2. `<task_folder>/validations/history.jsonl` — one compact line appended

It creates `validations/latest/` when absent. `history.jsonl` is JSON Lines (one
object per line); append-safe, git-diff-legible, easy to tail.

## CLI output format

```
TDD gate on <task_name>: <verdict>

  • <message 1>
  • <message 2>
  • <message 3>

Saved:
  latest  → <task>/validations/latest/tdd.json
  history → <task>/validations/history.jsonl
```

On `pass`: 0-2 messages (usually "all checks passed" + a brief observation). On `fail`: up to 5 top findings surfaced.

## Error cases

| Scenario | Behavior |
|---|---|
| No session context AND no `<task-name>` arg | Print "no task context; pass a task name or run /ai-dev-assistant:next first" + exit 2 |
| `<task-name>` doesn't resolve to a folder | Print candidate suggestions + exit 2 |
| `code-quality-tools` plugin missing | Print "code-quality-tools not installed; install via /plugin install code-quality-tools@camoa-skills" + exit 3 |
| `/code-quality:tdd` fails to execute | Emit envelope with `verdict: skipped`, messages describing the failure, exit 0 |
| Persistence write fails | Still print CLI summary; mention the failure in messages; exit 1 |

## Soft-nudge posture

- Manual invocation always runs, regardless of task kind or applicability signals (no auto-skip in v1)
- `fail` verdict signals but does not block — user can continue working or fix the issue
- Non-zero exit codes surface the signal to CI / `/validate:all` chaining, but the local session keeps going

## Related

- `/ai-dev-assistant:validate-solid` / `:validate-dry` / `:validate-security` — sibling wrappers, same pattern
- `/ai-dev-assistant:validate-guides` — framework-owned gate, not a wrapper
- `/ai-dev-assistant:validate-visual-parity` / `:validate-visual-regression` — visual gates
- `/ai-dev-assistant:validate-all` — sequential orchestrator that calls this + all other gates
- `references/validation-gate-result.md` — the shared envelope contract
- `/code-quality:tdd` — the underlying check this command wraps
- `/code-quality:coverage`, `/code-quality:lint`, `/code-quality:review`, `/code-quality:audit`, `/code-quality:ultrareview` — NOT wrapped; invoke directly for deeper coverage

## Output

Writes the result envelope to `<task_folder>/validations/latest/tdd.json`, overwriting the previous run, and appends the same envelope as one line to `<task_folder>/validations/history.jsonl`. The wrapped `/code-quality:tdd` flow writes no JSON report of its own, so the envelope's `raw_output_path` is `null` for this gate. Prints the verdict, the top messages, and both persisted paths.
