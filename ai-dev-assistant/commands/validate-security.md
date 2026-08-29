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

3. **Invoke the check** — execute the `/code-quality:security` flow as documented in the `code-quality-tools` plugin's `commands/security.md` within this command's own execution context. Do NOT attempt to shell out to the sibling slash command. If a `--files <list>` parameter was supplied to this wrapper, forward it to the underlying flow as `--changed <list>` — this scopes the SAST gate to the listed files; the code-quality tool handles the empty-list → clean-skip case internally. When `--files` is absent, run the flow's standard whole-project scan (auto-detect project type, run the security check, surface findings). Capture the output for envelope construction in step 4, **including the coverage fields** — `security-check.sh` emits `analyzers_ran` only in `--changed` mode, which is `/review`'s default path; on the standard path derive coverage instead by diffing `meta.tools` against `meta.tools_absent` and `meta.tools_unmeasured`. Carry `analyzers_ran` (or the derived count) and `tools_absent[]` in `--details`.

4. **Parse the result** — classify the output into our verdict space (`pass | warning | fail | skipped`) per the "Verdict interpretation" section below. Extract any actionable findings into `messages[]`. If `/code-quality:security` wrote a JSON report to `.reports/security.json` (disk-read fallback), capture its path.

5. **Emit and persist the envelope** — call `${CLAUDE_PLUGIN_ROOT}/scripts/validation-envelope-write.sh` (Bash) with the verdict, the findings and this gate's `details`. See "Emitting the envelope" below. The script builds the envelope and writes both files; do not assemble the JSON by hand.

6. **Check the exit code** — 0 means both writes succeeded. 1 is a write failure (missing task folder, permissions) — carry on and say so in the CLI summary. 2 means the arguments were rejected and nothing was written; fix the call rather than falling back to a hand-written file.

7. **Print CLI summary** — show verdict, top 3 messages, and the persisted-result paths. When invoked non-interactively (chained from `/validate:all` or CI equivalents), signal verdict via exit code: 0 for `pass`/`warning`/`skipped`; 1 for `fail`. In interactive use the printed summary IS the signal — Claude does not literally exit the session. User workflow is NEVER blocked regardless of verdict.

## Verdict interpretation

`/code-quality:security` output has to be mapped to our 4-value verdict enum. Heuristics (ordered; first match wins):

| Signal in output | Our verdict |
|---|---|
| Explicit "PASS" / "✓" / "all checks passed" / "no violations" | `pass` |
| Explicit "FAIL" / "✗" / "violations found" / "tests missing for <x>" | `fail` |
| Warnings-but-not-fatal phrasing ("1 concern", "minor issue", "consider") | `warning` |
| `analyzers_ran == 0` (or every entry of `meta.tools` is absent/unmeasured) | `skipped`, and put `unresolved: true` in `messages[]`, naming each entry of `tools_absent[]` |
| `analyzers_ran >= 1` with a non-empty `tools_absent[]`/`tools_unmeasured[]` — some layers ran, some did not | `warning`, naming the absent tools and which layers went unchecked. Never `pass` |
| Skip indicators ("not applicable", "no code changes to check", "skipped — <reason>") | `skipped` |
| Ambiguous or empty output | `warning` (conservative — surface for human review) |

The security gate stacks many layers — composer audit, semgrep, the phpcs security linter, psalm taint, gitleaks, custom patterns — so it has the same partial state SOLID does, and the same failure if it is flattened: a machine missing every scanner reports a clean tree, and a machine missing only the secret scanner reports a clean tree while nothing read a single credential. `tools_absent[]` is documented as expected-absent and deliberately does not move `security-check.sh`'s own status, which makes naming it here the wrapper's job. A gate that scanned nothing is `unresolved` and fails closed via `/review` step 8 rule 2; a gate that scanned some of its layers says which ones it did not.

If `/code-quality:security` emits JSON via a `--json` flag (future enhancement), prefer structured parsing over heuristics. v1 uses heuristics because no stable JSON surface exists yet upstream.

## Emitting the envelope (per `references/validation-gate-result.md`)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/validation-envelope-write.sh" gate \
  --gate security \
  --task "<task_name>" \
  --task-folder "<abs path to the task folder>" \
  --verdict "<pass|warning|fail|skipped>" \
  --details "$(jq -n \
      --arg raw "<path to .reports/security.json if produced, else empty>" \
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

Writes the result envelope to `<task_folder>/validations/latest/security.json`, overwriting the previous run, and appends the same envelope as one line to `<task_folder>/validations/history.jsonl`. The wrapped `/code-quality:security` flow may also leave `.reports/security.json` in the code being checked; when it does, its path is recorded in the envelope rather than written by this command. Prints the verdict, the top messages, and both persisted paths.
