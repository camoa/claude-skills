---
description: "Run the Security quality gate on demand and persist the result to the current task folder. Thin wrapper around /code-quality:security — adds task context, persistence, and the shared result envelope. Soft-nudge: reports fail verdict but never blocks. Introduced v3.13.0."
allowed-tools: Read, Write, Bash, Glob, Skill
argument-hint: "[<task-name>]"
---

# Validate: Security

Run the Security quality gate (Security — OWASP Top 10 style audit + framework-specific sink checks) against the current task. Wraps `/code-quality:security` from the `code-quality-tools` plugin; adds task-context resolution, result persistence to the task folder, and emits the shared result envelope (`references/validation-gate-result.md` v1.1).

## Usage

```
/ai-dev-assistant:validate-security                          # run against current task from session context
/ai-dev-assistant:validate-security <task-name>              # run against a specific task
/ai-dev-assistant:validate-security <task> --files <path>    # change-scoped: forward <path> as --changed to the underlying check
```

## What this does

1. **Resolve task context** — resolve the project folder in this order:
   (a) run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-read.sh` (Bash) and parse its JSON (`.project`, `.projectPath`, `.task`, `.taskPath`) if it resolves — it carries the active project's absolute path
   (b) walk up from `$PWD` until you find a directory containing `implementation_process/`
   (c) abort with "no project context — run /ai-dev-assistant:next first, or cd to a project workspace" if neither resolves

   Then resolve the task folder: if `<task-name>` arg is given, locate it under `<project>/implementation_process/in_progress/**/<task-name>/` (glob handles both flat and sub-epic nesting). If no arg, use the task from the `session-context-read.sh` output (`.task`/`.taskPath`). If the task doesn't resolve, abort with candidate suggestions.

2. **Verify dependency (v5.33.0+ — a resolved version, not a non-empty directory).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/plugin-dep-check.sh code-quality-tools 3.0.0` (Bash) and branch on `.status`. **`ok`** — proceed, and use the returned `path` if you need to read anything out of that plugin; it is the newest installed version resolved by version order, which is not the same as the first or last directory a glob returns. **`too_old`** — abort, naming `resolved_version` and the 3.0.0 minimum, with upgrade instructions: a wrapper aimed at an interface that version does not have produces a confident wrong verdict. **`undetermined`** — do NOT abort. The script can only see the marketplace cache, and the plugin may be installed from elsewhere; proceed and print one line saying the version could not be confirmed, so an unverified dependency never passes silently as a verified one. **`unreadable`** — same as `undetermined`, with its reason.

   The predecessor to this step confirmed the directory was non-empty and then declared a 3.0.0 minimum it never checked, so a cache holding only 2.x passed. Separately, a live run resolved that plugin's path with a lexically-sorted glob and read 3.9.6 while 3.9.8 sat beside it.

3. **Invoke the check** — execute the `/code-quality:security` flow as documented in the `code-quality-tools` plugin's `commands/security.md` within this command's own execution context. Do NOT attempt to shell out to the sibling slash command. If a `--files <list>` parameter was supplied to this wrapper, forward it to the underlying flow as `--changed <list>` — this scopes the SAST gate to the listed files; the code-quality tool handles the empty-list → clean-skip case internally. When `--files` is absent, run the flow's standard whole-project scan (auto-detect project type, run the security check, surface findings). **Stamp the time before invoking** — `date -u +%Y-%m-%dT%H:%M:%SZ` (Bash) — and keep the gate's exit code. Both go to the resolver at step 4: `report-dir.sh` can resolve to a dated directory and fall back to the newest existing one, so a run that dies before writing leaves the PREVIOUS run's report in place, and without a baseline the resolver would read a stale green.

4. **Resolve the verdict with the script, not by reading** — locate `security-report.json` via `report-dir.sh --latest`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/gate-verdict-resolve.sh security "<report>" --exit-code "<code>" --not-before "<step-3 timestamp>" --tool-catalog "<step-2 path>/skills/code-quality-audit/schema/tool-catalog.json"` (Bash) and use its JSON verbatim per "Verdict interpretation" below. **Pass the catalog** — it is the authority on whether a missing tool is one the project can install, and without it every gap is treated as closeable, which fails a clean review on any machine without semgrep or gitleaks (catalog scope `machine`, and `install-tools.sh` has no mechanism for them). `plugin-dep-check.sh` already returned the plugin path at step 2. The classification needs code-quality-tools **3.10.2+**, whose catalog carries the `layers` map for the names no installer places; with an older one those fall back to `unknown` and block, which is fail-closed and visible in `evidence.coverage_gap.scope_source`. A gap that does not block is still REPORTED: it arrives as a `coverage_gap_nonblocking:` line in `messages[]` and as `evidence.coverage_gap`, and both must reach the envelope unedited. Every field path, both report modes and the coverage arithmetic live in that script, where `tests/gate-verdict-resolve-spec.sh` checks them against the gate's own emitters and against fixture reports. Pass `messages[]` through unedited and `evidence{}` into `--details`.

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

**Locating the report.** Run `bash "<code-quality-tools path>/skills/code-quality-audit/scripts/core/report-dir.sh" --latest`
(Bash) and read `security-report.json` from the directory it prints. Never hardcode
`.reports/`; it stopped being the default in code-quality-tools v3.9.6.

**This gate emits two different report shapes** — whole-project and `--changed`, the
latter being `/review`'s default path — and they do not carry the same keys. The resolver
handles both and reads the verdict from `.summary.overall_status`, because there is no
top-level `.status`. A wrapper that read one went green on a project with a critical
finding. `meta.tools[]` is deliberately not consulted: it exists only in whole-project
mode, and `--changed` is the default path. Its names disagreed with the ones the code
pushed until cqt 3.10.4; that half is fixed and the mode half is not.

## Verdict interpretation

There is no table here on purpose. Run the resolver and use what it returns:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gate-verdict-resolve.sh" security "<report path>" \
  --tool-catalog "<code-quality-tools path>/skills/code-quality-audit/schema/tool-catalog.json" \
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
reach for `--skip-security`, which is the bypass that makes this whole mechanism worthless.

**If the resolver cannot be run**, emit `verdict: "skipped"` with `unresolved: true` and
say so. Do not fall back to reading the console text: guessing from prose is the thing
this replaced.

## Emitting the envelope (per `references/validation-gate-result.md`)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/validation-envelope-write.sh" gate \
  --gate security \
  --task "<task_name>" \
  --task-folder "<abs path to the task folder>" \
  --verdict "<pass|warning|fail|skipped>" \
  --details "$(jq -n \
      --arg raw "<absolute path to security-report.json as resolved by report-dir.sh --latest, else empty>" \
      --arg cqt "<version from plugin.json of code-quality-tools>" \
      '{source: "code-quality-tools:security",
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

1. `<task_folder>/validations/latest/security.json` — overwritten, via temp file + rename
2. `<task_folder>/validations/history.jsonl` — one compact line appended

It creates `validations/latest/` when absent. `history.jsonl` is JSON Lines (one
object per line); append-safe, git-diff-legible, easy to tail.

## CLI output format

```
Security gate on <task_name>: <verdict>

  • <message 1>
  • <message 2>
  • <message 3>

Saved:
  latest  → <task>/validations/latest/security.json
  history → <task>/validations/history.jsonl
```

On `pass`: 0-2 messages (usually "all checks passed" + a brief observation). On `fail`: up to 5 top findings surfaced.

## Error cases

| Scenario | Behavior |
|---|---|
| No session context AND no `<task-name>` arg | Print "no task context; pass a task name or run /ai-dev-assistant:next first" + exit 2 |
| `<task-name>` doesn't resolve to a folder | Print candidate suggestions + exit 2 |
| `code-quality-tools` plugin missing | Print "code-quality-tools not installed; install via /plugin install code-quality-tools@camoa-skills" + exit 3 |
| `/code-quality:security` fails to execute | Emit envelope with `verdict: skipped`, messages describing the failure, exit 0 |
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
- `/code-quality:security` — the underlying check this command wraps
- `/code-quality:coverage`, `/code-quality:lint`, `/code-quality:review`, `/code-quality:audit`, `/code-quality:ultrareview` — NOT wrapped; invoke directly for deeper coverage

## Output

Writes the result envelope to `<task_folder>/validations/latest/security.json`, overwriting the previous run, and appends the same envelope as one line to `<task_folder>/validations/history.jsonl`. The wrapped `/code-quality:security` flow writes `security-report.json` wherever `report-dir.sh` resolves — by default outside the audited repository, never `.reports/` unless `REPORT_DIR_IN_REPO=1` asked for it; its path is recorded in the envelope rather than written by this command. Prints the verdict, the top messages, and both persisted paths.
