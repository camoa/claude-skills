---
description: "Run the v3.13.0 /validate:* gates in isolated Claude Code agent teams (4 teammates) so each gate is assessed in a fresh context free of the main session's prior reasoning. Sibling to /validate:all — not a replacement. Gracefully falls back to /validate:all when the experimental flag is unset or TeamCreate fails. Introduced v3.14.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: [<task-name>] [--no-fallback]
---

# Validate: Team

Run the 7 `/validate:*` gates in **independent Claude Code agent-team sessions** so each gate is assessed by a fresh context window. Primary driver: **honest validation** — the validator cannot be anchored on what the main session just built. Secondary benefits: context-window economy, parallel throughput for code gates.

Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Without it, this command prints a fallback message and auto-runs `/validate:all` instead. Add `--no-fallback` to disable the auto-fallback (CI users who want team-or-nothing).

## Usage

```
/drupal-dev-framework:validate-team                         # run on current task, allow fallback
/drupal-dev-framework:validate-team <task-name>             # run on a specific task
/drupal-dev-framework:validate-team <task-name> --no-fallback   # refuse to run /validate:all if team spawn fails
```

## When to use

- **Pre-PR / pre-merge / pre-release honest-validation moments** — when self-review bias is a concern
- **Long main-session conversations** where context-window economy matters
- **Routine validation** — prefer `/validate:all` (single-session, warm caches, no agent-teams setup)

## What this does

### Step 1 — Resolve task + project context

- Accept `<task>` arg (falls back to session-context `task` if omitted).
- Invoke `project-state-reader` → `codePath`, `codePathState`, memory project folder.
- Resolve task folder. Refuse if the folder doesn't exist.

### Step 2 — Detect agent-teams availability (fallback chain)

```
$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == "1" ?
    NO  → print fallback message → auto-run /validate:all (unless --no-fallback)
    YES → attempt TeamCreate
        failed   → print fallback message → auto-run /validate:all (unless --no-fallback)
        succeeded → continue
            team already resident in session?
                YES → REFUSE with cleanup guidance (do NOT auto-cleanup)
                NO  → continue
```

Fallback message format:

> `/validate:team` cannot run agent teams (reason: `<env-unset | teamcreate-failed | team-resident>`). Falling back to `/validate:all`. Use `--no-fallback` to refuse this fallback.

With `--no-fallback`: print the reason, exit 2, do NOT invoke `/validate:all`.

"Team already resident" refusal message format:

> `/validate:team` detected an existing agent team in this session. Agent teams are one-per-session. Clean up via the team's cleanup procedure (see agent-teams docs §"Clean up the team"), then re-invoke. `/validate:team` will not auto-cleanup — teams the user didn't explicitly end may have in-flight work.

### Step 3 — Read context for manifest

Invoke these skills/readers **in parallel** where possible:

- `alignment-reader` → `sections.task_level` (used by teammates that need the goal/success-criteria)
- `project-state-reader` → `codePath`, `codePathState` (already loaded in Step 1; re-use)
- `screenshot-store-reader` → enumerate `<component>/<viewport>` pairs with `role: baseline` → used to populate `visual_fanout[]` for the visual gate entry

If the screenshot store is empty OR `codePathState != "set"` for visual gates, the visual-regression entry in the manifest still ships but its `visual_fanout[]` is an empty array (teammate will emit `verdict: "skipped"` with reason).

### Step 4 — Write manifest

Compose the manifest per `references/team-manifest-schema.md` v1.0 and write to:

```
<task>/validations/tmp/team-manifest.json
```

Invariants (see schema §9):
- All paths absolute
- `visual_fanout[]` present only on `visual-regression` gate entries (omit the field for code/docs gates — do NOT write `visual_fanout: []`)
- `gates[]` non-empty
- Teammate spawn prompts reference the manifest by **absolute path**; they do NOT re-inline the envelope contract

Write the manifest **before** spawn so every teammate can read it regardless of its `cwd` (worktree or main). The lead's PWD when writing is irrelevant to readability; absolute paths resolve from any `cwd`.

### Step 5 — Spawn 4 teammates

The roster covers **6 of the 7 v3.13.0 gates** — `validate-visual-parity` is excluded from the v1 roster (deferred to v2 Set B5 — requires an explicit `<reference>` arg that `/validate:all` can't supply either).

Spawn each teammate with `TeamCreate`. Spawn prompts are ≤40 lines each, reference the manifest by absolute path, and declare the teammate's role + gate assignments + isolation mode in a header block:

```
**Model:** sonnet
**MaxTurns:** 20
**Isolation:** worktree
```

Roster (from architecture §7):

| Teammate | Gates owned | Model | MaxTurns | Isolation |
|---|---|---|---|---|
| `validator-code-1` | `tdd`, `solid` | sonnet | 20 | worktree |
| `validator-code-2` | `dry`, `security` | sonnet | 20 | worktree |
| `validator-docs` | `guides` | haiku | 10 | worktree |
| `validator-visual` | `visual-regression` (fanned out) | sonnet | 15 | none |

Each spawn prompt MUST include the absolute-path reminder (schema §10):

> When you write `<gate>.json` or append to `history.jsonl`, use the absolute paths in `manifest.envelope.latest_dir` / `manifest.envelope.history_file`. Do NOT use relative paths — you are in a worktree and relative writes will not reach the lead.

Each spawn prompt MUST include the progress-message contract:

> When a gate completes, send a mailbox message to the lead in this exact format: `"<gate> complete, verdict: <verdict>"` where `<verdict>` is one of `pass | warning | fail | skipped`. Do not vary the format — the lead parses it.

### Step 6 — Stream progress

Receive mailbox messages from teammates. Print one CLI line per message:

```
  tdd complete, verdict: pass
  solid complete, verdict: warning
  dry complete, verdict: pass
  security complete, verdict: pass
  guides complete, verdict: pass
  visual-regression complete, verdict: skipped
```

Do NOT wait on `TaskCompleted` hook events (deferred to v2 Set B2). The mailbox stream is the progress signal.

### Step 7 — Aggregate

When all expected gates have reported (or timeout reached — document as manual-recovery scenario):

1. Read each `<task>/validations/latest/<gate>.json` envelope written by teammates.
2. Assemble `_all.json` using the same aggregation shape `/validate:all` emits (per `references/validation-gate-result.md` §6), with one addition:
   ```json
   "discoverability_hint": "Run produced by /validate:team (source: \"validate:team\"). For deeper coverage, see: /code-quality:lint, /code-quality:coverage, /code-quality:review, /code-quality:audit, /code-quality:ultrareview (not wrapped by /validate:*)"
   ```
3. Include an explicit `source: "validate:team"` marker inside the aggregate object so downstream consumers can distinguish team-mode runs from single-session runs:
   ```json
   { "source": "validate:team", "schema_version": "1.0", ... }
   ```

Write aggregate to:
- `<task>/validations/latest/_all.json` (overwrite)
- `<task>/validations/history.jsonl` (append — note: each teammate already appended its own per-gate line; the `_all.json` aggregate appends one additional summary line)

Print the summary table in the same format as `/validate:all` Step 7.

### Step 8 — Cleanup

- Remove `<task>/validations/tmp/team-manifest.json`
- Clean up the agent team per the agent-teams guide §"Clean up the team"
- Leave the `tmp/` directory itself in place (may be empty)

Do NOT remove per-gate envelopes in `validations/latest/` — they are persistent artifacts, same as `/validate:all` produces.

### Step 9 — Persist run metadata

Append one aggregate-summary line to `<task>/validations/history.jsonl` tagged with `run_id` matching the manifest. The run_id links the per-gate history lines to the aggregate line for any future analysis tooling.

## CLI summary

```
Team validation for <task_name>:

  Teammate              Gates              Verdict mix
  validator-code-1      tdd, solid         pass, warning
  validator-code-2      dry, security      pass, pass
  validator-docs        guides             pass
  validator-visual      visual-regression  skipped (no baselines)

  Aggregate verdict: warning (1 warning, 5 pass, 1 skipped)

  Saved:
    summary → <task>/validations/latest/_all.json
    history → <task>/validations/history.jsonl

  Source: validate:team
```

## Honest-validation guarantee

Teammates run in their own Claude Code sessions. They do NOT have access to:

- The lead's conversation history
- Uncommitted edits in the main working directory (if using `isolation: "worktree"`, they see only committed state)
- Any guide loads, skill activations, or file reads the lead performed before spawn

They DO have access to:

- The manifest at the absolute path
- The project's `CLAUDE.md` + any `.claude/rules/` files (inherited per agent-teams runtime)
- MCP configs (e.g., Playwright for visual-regression)
- The filesystem (read + write per their permission mode)
- The mailbox primitive for talking to the lead

This separation is what makes `/validate:team` honest where `/validate:all` is efficient.

## Error cases

| Scenario | Behavior |
|---|---|
| No task context | Abort; exit 2 |
| Task folder missing | Abort; exit 2 |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` unset | Fallback (§Step 2) unless `--no-fallback` |
| `TeamCreate` fails | Fallback (§Step 2) unless `--no-fallback` |
| Team already resident | Refuse with cleanup guidance; do NOT auto-cleanup |
| Teammate dies mid-run | Manifest + any partial envelopes remain; manual recovery (see `--cleanup` in v2 Set B4) |
| Teammate writes invalid envelope (schema mismatch) | Aggregate step logs the mismatch in the `_all.json` `messages[]` for that gate; overall verdict reflects fail |
| `--no-fallback` with env unset | Print reason; exit 2; NO fallback |

## What this does NOT do

- Does NOT wrap or modify `/validate:all` — sibling command, independent lifecycle
- Does NOT introduce a new envelope schema — per-gate envelopes stay at v3.13.0 v1.0; the aggregate adds only the `source` marker
- Does NOT support `validate-visual-parity` in the team roster (deferred to v2 Set B5 — parity requires explicit `<reference>` arg)
- Does NOT offer parallel visual gates (v1 serializes in one visual teammate; deferred to v2 Set B1)
- Does NOT stream per-gate results via hooks (deferred to v2 Set B2 — mailbox messages cover it for now)
- Does NOT offer a `--json` flag (deferred to v2 Set B3 — `_all.json` is already structured)
- Does NOT offer a `--cleanup` subcommand for crash recovery (deferred to v2 Set B4 — manual recovery documented)
- Does NOT auto-skip gates based on AI-inferred applicability (inherits `/validate:all`'s v1 posture)

## Soft-nudge posture

- Individual gate `fail` never blocks; `/validate:team` aggregates, surfaces, and lets the user decide
- The team-mode fallback is automatic unless `--no-fallback` — users on machines without the experimental flag get validated output without re-invoking
- The "team already resident" case REFUSES rather than auto-cleans — the user may have in-flight work; asking is safer than guessing

## Manual recovery (teammate crash)

If a teammate dies mid-run:

1. The manifest at `<task>/validations/tmp/team-manifest.json` is still on disk
2. Any envelopes already written to `<task>/validations/latest/<gate>.json` are valid
3. The lead may aggregate from the available envelopes (print a message for missing gates) OR
4. Clean up the team via agent-teams docs §"Clean up the team", remove the manifest manually, and re-invoke `/validate:team`

v2 Set B4 will ship a `--cleanup` subcommand to automate this.

## Session context

This command does NOT update `session_context.json`. Validation runs are transient; the command body + the envelope already capture everything worth persisting (per architecture §2 Q7.7). Other `/validate:*` commands follow the same convention.

## Related

- `/drupal-dev-framework:validate-all` — sibling; single-session aggregator. Use this for routine validation
- `/drupal-dev-framework:validate-tdd` / `:validate-solid` / `:validate-dry` / `:validate-security` / `:validate-guides` / `:validate-visual-regression` — individual gates invoked by teammates
- `references/team-manifest-schema.md` — canonical `team-manifest.json` v1.0 spec
- `references/validation-gate-result.md` — per-gate + aggregate envelope schema (v3.13.0 v1.0; unchanged)
- `references/screenshot-store-schema.md` — screenshot store layout (unchanged)
