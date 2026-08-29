---
description: "Run the DRY quality gate on demand and persist the result to the current task folder. Thin wrapper around /code-quality:dry — adds task context, persistence, and the shared result envelope. Soft-nudge: reports fail verdict but never blocks. Introduced v3.13.0."
allowed-tools: Read, Write, Bash, Glob, Skill
argument-hint: "[<task-name>]"
---

# Validate: DRY

Run the DRY quality gate (DRY — code duplication detection) against the current task. Wraps `/code-quality:dry` from the `code-quality-tools` plugin; adds task-context resolution, result persistence to the task folder, and emits the shared result envelope (`references/validation-gate-result.md` v1.1).

## Usage

```
/ai-dev-assistant:validate-dry                          # run against current task from session context
/ai-dev-assistant:validate-dry <task-name>              # run against a specific task
/ai-dev-assistant:validate-dry <task> --files <path>    # change-scoped: forward <path> as --changed (filters verdict to change-touching clones)
```

## What this does

1. **Resolve task context** — resolve the project folder in this order:
   (a) run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-read.sh` (Bash) and parse its JSON (`.project`, `.projectPath`, `.task`, `.taskPath`) if it resolves — it carries the active project's absolute path
   (b) walk up from `$PWD` until you find a directory containing `implementation_process/`
   (c) abort with "no project context — run /ai-dev-assistant:next first, or cd to a project workspace" if neither resolves

   Then resolve the task folder: if `<task-name>` arg is given, locate it under `<project>/implementation_process/in_progress/**/<task-name>/` (glob handles both flat and sub-epic nesting). If no arg, use the task from the `session-context-read.sh` output (`.task`/`.taskPath`). If the task doesn't resolve, abort with candidate suggestions.

2. **Verify dependency (v5.33.0+ — a resolved version, not a non-empty directory).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/plugin-dep-check.sh code-quality-tools 3.0.0` (Bash) and branch on `.status`. **`ok`** — proceed, and use the returned `path` if you need to read anything out of that plugin; it is the newest installed version resolved by version order, which is not the same as the first or last directory a glob returns. **`too_old`** — abort, naming `resolved_version` and the 3.0.0 minimum, with upgrade instructions: a wrapper aimed at an interface that version does not have produces a confident wrong verdict. **`undetermined`** — do NOT abort. The script can only see the marketplace cache, and the plugin may be installed from elsewhere; proceed and print one line saying the version could not be confirmed, so an unverified dependency never passes silently as a verified one. **`unreadable`** — same as `undetermined`, with its reason.

   The predecessor to this step confirmed the directory was non-empty and then declared a 3.0.0 minimum it never checked, so a cache holding only 2.x passed. Separately, a live run resolved that plugin's path with a lexically-sorted glob and read 3.9.6 while 3.9.8 sat beside it.

3. **Invoke the check** — execute the `/code-quality:dry` flow as documented in the `code-quality-tools` plugin's `commands/dry.md` within this command's own execution context. Do NOT attempt to shell out to the sibling slash command. If a `--files <list>` parameter was supplied to this wrapper, forward it to the underlying flow as `--changed <list>` — DRY keeps its whole-tree clone scan but the `--changed` mode filters the verdict to clones where at least one copy is in the changed-files list (a clone entirely in unchanged code is not your concern this review). The code-quality tool handles the empty-list → clean-skip case internally. When `--files` is absent, run the flow's standard whole-project scan with no verdict filter (auto-detect project type, run the dry check, surface findings). Capture the console output; step 4 reads the report.

4. **Read the report, then classify** — locate `dry-report.json` via `report-dir.sh --latest` and resolve the verdict from it per the "Verdict interpretation" section below, which is ordered coverage-first. The report is the primary source; the console text is the last resort and sets the verdict only when no report exists. Extract actionable findings into `messages[]`, and capture the report's absolute path plus `tools_absent[]`, `tools_failed[]` and `skip_reason` for `--details`.

5. **Emit and persist the envelope** — call `${CLAUDE_PLUGIN_ROOT}/scripts/validation-envelope-write.sh` (Bash) with the verdict, the findings and this gate's `details`. See "Emitting the envelope" below. The script builds the envelope and writes both files; do not assemble the JSON by hand.

6. **Check the exit code** — 0 means both writes succeeded. 1 is a write failure (missing task folder, permissions) — carry on and say so in the CLI summary. 2 means the arguments were rejected and nothing was written; fix the call rather than falling back to a hand-written file.

7. **Print CLI summary** — show verdict, top 3 messages, and the persisted-result paths. When invoked non-interactively (chained from `/validate:all` or CI equivalents), signal verdict via exit code: 0 for `pass`/`warning`/`skipped`; 1 for `fail`. In interactive use the printed summary IS the signal — Claude does not literally exit the session. User workflow is NEVER blocked regardless of verdict.

## Where the result comes from

**The report file is the source of the verdict. The console text is not.** Every gate
in `code-quality-tools` writes `<report-dir>/dry-report.json` on **every** path it can take,
including the ones where it measured nothing, and that file carries the fields a verdict
needs: `status`, `rating`, `mode`, `measured`, `skip_reason`, `tools_absent[]`,
`tools_failed[]`, `tools_unmeasured[]`, `analyzers_ran`. Its console line does not. This
wrapper used to claim "no stable JSON surface exists yet upstream" and parse prose
instead, and that claim was false when it was written.

Parsing prose is not merely less precise here, it inverts the answer. `dry-check.sh` prints `[SKIP] phpcpd not installed` and exits 0 on the absent path, and
the old table's first row matched any `✓` or "no violations" in the surrounding output,
so the row meant to catch this never evaluated.

**Locating the report.** Run `bash "<code-quality-tools path>/skills/code-quality-audit/scripts/core/report-dir.sh" --latest`
(Bash) and read `dry-report.json` from the directory it prints. `--latest` is the reader's mode:
it answers where the most recent run actually wrote, which is a different question from
where the next one would. Do **not** hardcode `.reports/` — it stopped being the default
in code-quality-tools v3.9.6 and is now opt-in behind `REPORT_DIR_IN_REPO=1`, so a
wrapper looking there finds nothing on a normal run and concludes the gate did not run.
`--latest` prints nothing and exits 1 when no run has ever written; treat that exactly
like a missing file, below.

## Verdict interpretation

Resolve in this order. **A is checked before B and B before C** — a coverage question
answered after a findings question is answered too late, which is how the previous
version of this section went wrong.

**A. Was a report written at all?** No `dry-report.json` — the file is missing, unparseable, or
`--latest` exited 1 — ⇒ `skipped`, with `unresolved: true` in `messages[]` saying no
report was found and naming where it looked. A gate that wrote no report cannot tell you
what it measured, and its console text is the least reliable thing in the room. Use the
text heuristics at the bottom of this section **only** to populate `messages[]` with
whatever the run did say; they never set the verdict on this path.

**B. Did it measure anything?** Ordered; first match wins.

| Signal in `dry-report.json` | Our verdict |
|---|---|
| `status` or `rating` is `unmeasured`, or `measured` is `false` | `skipped`, and put `unresolved: true` in `messages[]` quoting the report's reason |
| `skip_reason` is `tool_absent`, or `tools_absent[]` contains `phpcpd` | `skipped`, and put `unresolved: true` in `messages[]`, naming phpcpd |
| `tools_failed[]` is non-empty | `skipped`, and put `unresolved: true` in `messages[]`, naming what failed |
| Otherwise | fall through to C |

phpcpd is this gate's **only** analyzer, so every one of those rows means the same
thing: duplication was not measured, and there is no partial state to report.
`dry-check.sh` says so honestly — `status:"skipped"`, `skip_reason:"tool_absent"`,
`tools_absent:["phpcpd"]`, exit 0, and it writes that report before exiting. A crashed
phpcpd is the same fact as an absent one: a tool that returned nothing usable produced no
evidence, so `tools_failed[]` is treated exactly as seriously as `tools_absent[]`.
"Not measured" must never be reported as "no duplication".

**This gate has no partial state, so it never emits `coverage_partial: true`.** Its
siblings `validate-solid` and `validate-security` do, on a `warning` caused by some
analyzers being gone, and `/review` step 8 rule 4 fails on that marker. DRY runs one
analyzer: it either measured duplication or it did not, and the rows above cover the
second case as `unresolved`. A `warning` from this gate is always a fully measured run
whose duplication exceeded a soft threshold, which has never blocked a review and still
does not.

**C. It measured. Map the finding.**

| `status` in `dry-report.json` | Our verdict |
|---|---|
| `pass` | `pass` |
| `warning` or `partial` | `warning` |
| `fail` | `fail` |
| anything unrecognised | `warning`, naming the status verbatim |

The gate's exit code corroborates and never overrides: `4` is `unmeasured` (B catches it
from the report; if the report and the exit code disagree, the disagreement itself is
`unresolved`), `1` is a real fail, `2` is a bad invocation, `0` covers pass, warning and
the benign skips.

**Last resort — text heuristics.** For `messages[]` only, and for the verdict **only** on
path A, where there is nothing else. Ordered; first match wins.

| Signal in output | Reading |
|---|---|
| Explicit "PASS" / "✓" / "all checks passed" / "no violations" | clean |
| Explicit "FAIL" / "✗" / "violations found" | findings |
| Warnings-but-not-fatal phrasing ("1 concern", "minor issue", "consider") | observations |
| Skip indicators ("not applicable", "no code changes to check", "skipped — <reason>") | a skip |
| Ambiguous or empty output | say so in `messages[]` |

## Emitting the envelope (per `references/validation-gate-result.md`)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/validation-envelope-write.sh" gate \
  --gate dry \
  --task "<task_name>" \
  --task-folder "<abs path to the task folder>" \
  --verdict "<pass|warning|fail|skipped>" \
  --details "$(jq -n \
      --arg raw "<absolute path to dry-report.json as resolved by report-dir.sh --latest, else empty>" \
      --arg cqt "<version from plugin.json of code-quality-tools>" \
      '{source: "code-quality-tools:dry",
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

1. `<task_folder>/validations/latest/dry.json` — overwritten, via temp file + rename
2. `<task_folder>/validations/history.jsonl` — one compact line appended

It creates `validations/latest/` when absent. `history.jsonl` is JSON Lines (one
object per line); append-safe, git-diff-legible, easy to tail.

## CLI output format

```
DRY gate on <task_name>: <verdict>

  • <message 1>
  • <message 2>
  • <message 3>

Saved:
  latest  → <task>/validations/latest/dry.json
  history → <task>/validations/history.jsonl
```

On `pass`: 0-2 messages (usually "all checks passed" + a brief observation). On `fail`: up to 5 top findings surfaced.

## Error cases

| Scenario | Behavior |
|---|---|
| No session context AND no `<task-name>` arg | Print "no task context; pass a task name or run /ai-dev-assistant:next first" + exit 2 |
| `<task-name>` doesn't resolve to a folder | Print candidate suggestions + exit 2 |
| `code-quality-tools` plugin missing | Print "code-quality-tools not installed; install via /plugin install code-quality-tools@camoa-skills" + exit 3 |
| `/code-quality:dry` fails to execute | Emit envelope with `verdict: skipped`, messages describing the failure, exit 0 |
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
- `/code-quality:dry` — the underlying check this command wraps
- `/code-quality:coverage`, `/code-quality:lint`, `/code-quality:review`, `/code-quality:audit`, `/code-quality:ultrareview` — NOT wrapped; invoke directly for deeper coverage

## Output

Writes the result envelope to `<task_folder>/validations/latest/dry.json`, overwriting the previous run, and appends the same envelope as one line to `<task_folder>/validations/history.jsonl`. The wrapped `/code-quality:dry` flow writes `dry-report.json` wherever `report-dir.sh` resolves — by default outside the audited repository, never `.reports/` unless `REPORT_DIR_IN_REPO=1` asked for it; its path is recorded in the envelope rather than written by this command. Prints the verdict, the top messages, and both persisted paths.
