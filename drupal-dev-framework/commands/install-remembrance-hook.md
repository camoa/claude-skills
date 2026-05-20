---
description: "Wire per-project session-remembrance hooks into a project. Fills the session primer (framework facts + user-specific reminders), writes a SessionStart hook that injects it (covering compaction too) and a SessionEnd hook that runs save-session.sh, into <project>/.claude/settings.json. Opt-in, per project, idempotent. Introduced v4.5.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill
argument-hint: ""
---

# Install Remembrance Hook

Wire the **session-remembrance** hooks into a project so Claude does not forget,
after compaction / `/clear` / a new session, that this project runs the
drupal-dev-framework — and so in-flight state is persisted on every exit.

This is **opt-in, per project**. Run it once per project. It is **idempotent** —
re-run it any time to update the primer or repair the hook entries; it never
duplicates them.

## What gets installed

Into the project's working directory (`<project>/`):

| Path | Purpose |
|------|---------|
| `<project>/.claude/drupal-dev-framework/session-primer.md` | The filled primer. **User-editable by hand.** |
| `<project>/.claude/drupal-dev-framework/save-session.sh` | A copy of the persistence script (so the hook does not depend on the plugin install path). |
| `<project>/.claude/settings.json` → `hooks.SessionStart` | `cat`s the primer to stdout. SessionStart stdout is injected as context — and it fires on `startup`, `resume`, `clear`, **and `compact`**, so one entry covers post-compaction re-injection too. |
| `<project>/.claude/settings.json` → `hooks.SessionEnd` | Runs `save-session.sh` on every exit. Scripted safety net. |

> **Why not a `PostCompact` hook?** `PostCompact` stdout is *not* injected into
> Claude's context (only `SessionStart`, `UserPromptSubmit`, and
> `UserPromptExpansion` stdout is). A no-matcher `SessionStart` hook already
> fires with `source: "compact"` after compaction, so it does the job. A
> `PostCompact` hook here would be dead config.

> **Why copy `save-session.sh` into the project?** The hook lives in the
> project's `settings.json`, not in the plugin. `${CLAUDE_PLUGIN_ROOT}` does not
> resolve there, and an absolute plugin path breaks on every plugin update.
> A project-local copy referenced via `${CLAUDE_PROJECT_DIR}` is stable and
> self-contained. Re-running this command refreshes the copy.

## Interactive flow

### Step 1 — Detect and confirm project facts

Resolve the active project. Read the per-workspace session file
(`~/.claude/drupal-dev-framework/sessions/<md5(cwd)>.json`) for `projectPath`;
if no project is active, tell the user to run `/drupal-dev-framework:next`
first and stop.

Run the `project-state-reader` skill (or `scripts/project-state-read.sh
<projectPath>`) to get `project_name`, the project `folder` (the **memory
path**), and `codePath`.

Determine the **install directory** — the directory Claude Code is started from
for this project, where `.claude/settings.json` belongs:
- Default it to `codePath` when that is a real absolute path.
- If `codePath` is `(docs-only)` / null, default it to the memory `folder`.

Show the user all four values and let them confirm or edit each:

```
Project name : <project_name>
Memory path  : <folder>
Code path    : <codePath or "(docs-only)">
Install into : <install-dir>/.claude/

Confirm these? [Y] accept  /  [e] edit a value  /  [n] cancel
```

Validate the install directory is an existing absolute path before continuing.

### Step 2 — Gather user-specific reminders

If `<install-dir>/.claude/drupal-dev-framework/session-primer.md` already
exists (re-run), read its current **`## User-specific reminders`** section and
show it as the existing value — so hand-edits are preserved by default.

Prompt:

> Anything else the AI should be reminded of every session? Examples: coding
> conventions, deployment quirks, files to never touch, preferred effort level.
> Leave blank to skip.
>
> (On re-run, press Enter to keep the existing reminders shown above, or type
> new text to replace them.)

### Step 3 — Show the filled primer and get approval

Read the template from `${CLAUDE_PLUGIN_ROOT}/templates/session-primer.md`.
Substitute the placeholders:

| Placeholder | Value |
|-------------|-------|
| `{generated_date}` | today's date (`date -I`) |
| `{project_name}` | confirmed project name |
| `{memory_path}` | confirmed memory path |
| `{code_path}` | confirmed code path, or `(docs-only — no separate code path)` |
| `{user_additions}` | the reminders from step 2, or `_(none)_` if blank |

Show the fully rendered primer and ask the user to approve. If they reject,
return to step 2.

### Step 4 — Write hook entries into `<install-dir>/.claude/settings.json`

Create `<install-dir>/.claude/` if absent. If `settings.json` does not exist,
start it as `{}`.

Merge the two hook entries with the jq filter below. It is **idempotent**: it
first drops any prior group whose handler command references this plugin's
primer / script (matched by path substring), then appends a fresh group. Other
events, other plugins' hooks, and unrelated `SessionStart` / `SessionEnd`
groups are left untouched.

```bash
SETTINGS="<install-dir>/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Literal ${CLAUDE_PROJECT_DIR} — single-quoted so bash does NOT expand it.
# Claude Code substitutes it when the hook runs.
SS_CMD='cat "${CLAUDE_PROJECT_DIR}/.claude/drupal-dev-framework/session-primer.md" 2>/dev/null || true'
SE_CMD='${CLAUDE_PROJECT_DIR}/.claude/drupal-dev-framework/save-session.sh'

TMP="$SETTINGS.tmp.$$"
jq --arg ssCmd "$SS_CMD" --arg seCmd "$SE_CMD" '
  .hooks //= {}
  | .hooks.SessionStart = (
      ((.hooks.SessionStart // []) | map(select(
        ([.hooks[]?.command // ""]
         | map(test("drupal-dev-framework/session-primer\\.md")) | any) | not
      )))
      + [ { hooks: [ { type: "command", command: $ssCmd, timeout: 5 } ] } ]
    )
  | .hooks.SessionEnd = (
      ((.hooks.SessionEnd // []) | map(select(
        ([.hooks[]?.command // ""]
         | map(test("drupal-dev-framework/save-session\\.sh")) | any) | not
      )))
      + [ { hooks: [ { type: "command", command: $seCmd, args: [], timeout: 10 } ] } ]
    )
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS" || { rm -f "$TMP"; echo "settings.json merge failed" >&2; }
```

The `timeout: 10` on the `SessionEnd` hook matters: `SessionEnd`'s default
budget is 1.5 s, and a per-hook `timeout` set in a project `settings.json`
raises it. Keep it.

### Step 5 — Write the primer and copy the script

```bash
DEST="<install-dir>/.claude/drupal-dev-framework"
mkdir -p "$DEST"
# Write the rendered primer from step 3 to $DEST/session-primer.md (overwrite).
# Copy the script and make it executable:
cp "${CLAUDE_PLUGIN_ROOT}/scripts/save-session.sh" "$DEST/save-session.sh"
chmod +x "$DEST/save-session.sh"
```

Write the rendered primer (from step 3) to `$DEST/session-primer.md`,
overwriting any previous copy.

### Step 6 — Report

Tell the user:
- The three files written (`settings.json`, `session-primer.md`, `save-session.sh`).
- That `SessionStart` (incl. post-compaction) and `SessionEnd` hooks are now active.
- They can hand-edit `session-primer.md` directly — no need to re-run this command.
- **Re-run this command if the project name, memory path, or code path changes**
  — the primer is a static snapshot and does not track `project_state.md`.
- New hooks take effect on the next Claude Code session in that directory.

## Idempotency

Re-running is safe and expected:
- The jq merge replaces this plugin's hook groups in place — never duplicates.
- The primer is overwritten; step 2 pre-fills the existing user reminders so
  hand-edits survive unless the user changes them.
- `save-session.sh` is re-copied (picks up plugin updates).

## Coexistence with other plugins

Multiple plugins may each install their own `SessionStart` hook in the same
project. Claude Code runs all matching hooks and concatenates their context —
they are additive, not conflicting. The merge above only ever touches groups
that reference *this* plugin's primer / script.

## Errors

| Error | Resolution |
|-------|------------|
| `No active project. Run /drupal-dev-framework:next first.` | Resolve a project, then retry. |
| `Install directory does not exist: <p>` | Confirm or edit the install directory in step 1. |
| `settings.json merge failed` | The existing `settings.json` is not valid JSON — fix it, then retry. |

## Related

- `/drupal-dev-framework:save-session` — the judgement-first persistence command.
- `/drupal-dev-framework:next` — resume work; see current phase and task.
