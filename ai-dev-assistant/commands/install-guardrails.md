---
description: "Wire an opt-in PreToolUse guardrail that blocks a small set of dangerous git/shell command patterns (git push, reset --hard, rm -rf /, etc.) before Bash runs them. Writes a Bash matcher into the user's chosen settings.json (project or user-level). Opt-in, idempotent. Introduced v5.20.0."
allowed-tools: Read, Write, Edit, Bash, Glob
argument-hint: ""
---

# Install Guardrails

Wire the **dangerous-command guardrail** so Claude Code refuses to run a small,
fixed list of destructive git/shell commands during a Bash tool call — a
`git push`, `git reset --hard`, `rm -rf /`, and similar — without you asking
for it first.

This is **opt-in**. The plugin never installs this hook by default (`hooks.json`
does not reference it) — running this command once is the only way it gets
wired in. It is **idempotent** — re-run it any time (e.g. after a plugin
update) to refresh the installed script; it never duplicates the hook entry.

> **Not a security boundary.** This is friction against an accidental
> destructive command, not a sandbox and not a permission system. It matches a
> fixed list of literal patterns — a differently-phrased or obfuscated command
> can bypass it — and it **fails open** on any parse error (see `AIDA_ALLOW_DANGEROUS`
> below). Use it as a second pair of eyes, not a guarantee.

## What gets blocked

`hooks/block-dangerous-commands.sh` matches the Bash command string against:

```
git push · git reset --hard · git clean -f · git clean -fd · git branch -D ·
git checkout . · git restore . · push --force · --force-with-lease ·
reset --hard · rm -rf / · rm -rf ~ · rm -rf . · git clean -x
```

A match prints `BLOCKED: <command> matches dangerous pattern '<p>' — the
guardrail is preventing this. Remove the guardrail or run it yourself if
intended.` to stderr and blocks the tool call. No match → the command runs
normally.

## The override

Set `AIDA_ALLOW_DANGEROUS=1` in the environment to skip all checks for that
session/call — e.g. you genuinely need to run `git push --force` and know it.
This is documented, not hidden: anyone reading the hook script sees the escape
hatch.

## What gets installed

| Path | Purpose |
|------|---------|
| `<install-dir>/.claude/ai-dev-assistant/block-dangerous-commands.sh` | A copy of the guardrail script (executable). |
| `<install-dir>/settings.json` → `hooks.PreToolUse` (matcher `Bash`) | Runs the copied script before every Bash call. |

`<install-dir>` is either the **project** (`<project-root>/.claude/`) or the
**user** (`~/.claude/`) location — you choose in Step 1.

> **Why copy the script instead of pointing at `${CLAUDE_PLUGIN_ROOT}`?**
> `${CLAUDE_PLUGIN_ROOT}` is substituted only inside the plugin's own
> `hooks.json`. A hook command written into an *external* `settings.json` (a
> project's or the user's) never sees that substitution — the literal string
> `${CLAUDE_PLUGIN_ROOT}` would end up in the command with nothing to expand
> it. A local copy referenced by a stable path is self-contained and survives
> plugin reinstalls/updates that move the plugin's cache location. Same
> reasoning as `/install-remembrance-hook`'s `save-session.sh` copy.

## Interactive flow

### Step 1 — Choose the install location

Ask:

```
Install the guardrail into:
  [p] this project's .claude/settings.json  (<cwd>/.claude/settings.json)
  [u] your user-level ~/.claude/settings.json (applies to every project)
Choice [p/u]:
```

Resolve `<install-dir>`:
- `[p]` → `<cwd>/.claude` (create if absent; confirm `<cwd>` is the intended
  project root first if ambiguous)
- `[u]` → `$HOME/.claude`

### Step 2 — Confirm

Show:

```
Script    : <install-dir>/ai-dev-assistant/block-dangerous-commands.sh
Settings  : <install-dir>/settings.json  (hooks.PreToolUse → matcher "Bash")
Blocks    : git push, reset --hard, rm -rf /, and 11 other patterns (see above)
Override  : AIDA_ALLOW_DANGEROUS=1 skips all checks for a call

Confirm install? [Y] yes  /  [n] cancel
```

Stop on `[n]`.

### Step 3 — Copy the script

```bash
DEST="<install-dir>/ai-dev-assistant"
mkdir -p "$DEST"
cp "${CLAUDE_PLUGIN_ROOT}/hooks/block-dangerous-commands.sh" "$DEST/block-dangerous-commands.sh"
chmod +x "$DEST/block-dangerous-commands.sh"
```

### Step 4 — Write the hook entry into `<install-dir>/settings.json`

Create `<install-dir>/` if absent. If `settings.json` does not exist, start it
as `{}`.

Merge the `PreToolUse` entry with the jq filter below. It is **idempotent**: it
first drops any prior `Bash`-matcher group whose handler command references
this script (matched by path substring), then appends a fresh group. Other
matchers, other events, and other plugins' hooks are left untouched.

```bash
SETTINGS="<install-dir>/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Resolve to an ABSOLUTE path before writing it into settings.json. A relative
# path here would resolve against whatever cwd Claude Code happens to launch
# from for a given session — for the project-scoped option that is not
# guaranteed to be <project-root>, so a relative path can silently point at
# the wrong location and the hook never fires. realpath (falling back to a
# manual $PWD/$HOME-anchored join if realpath is unavailable) makes this
# independent of the shell's cwd at hook-invocation time.
HOOK_CMD="$(realpath "<install-dir>/ai-dev-assistant/block-dangerous-commands.sh" 2>/dev/null || echo "<install-dir>/ai-dev-assistant/block-dangerous-commands.sh")"

TMP="$SETTINGS.tmp.$$"
jq --arg cmd "$HOOK_CMD" '
  .hooks //= {}
  | .hooks.PreToolUse = (
      ((.hooks.PreToolUse // []) | map(select(
        (.matcher != "Bash") or
        (([.hooks[]?.command // ""]
          | map(test("block-dangerous-commands\\.sh")) | any) | not)
      )))
      + [ { matcher: "Bash", hooks: [ { type: "command", command: $cmd, timeout: 5 } ] } ]
    )
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS" || { rm -f "$TMP"; echo "settings.json merge failed" >&2; }
```

### Step 5 — Report

Tell the user:
- The two files written (`block-dangerous-commands.sh`, `settings.json`).
- The guardrail takes effect on the **next Claude Code session** in that
  directory (project) or **any session** (user-level).
- How to test it: ask Claude to run `git push` in a scratch repo and confirm
  it is blocked.
- How to uninstall: delete the `PreToolUse` → `Bash` group referencing
  `block-dangerous-commands.sh` from `settings.json` (or just delete the whole
  group if nothing else shares the `Bash` matcher), and optionally remove
  `<install-dir>/ai-dev-assistant/block-dangerous-commands.sh`.
- The `AIDA_ALLOW_DANGEROUS=1` override, once more, so it isn't forgotten.

## Idempotency

Re-running is safe and expected:
- The jq merge replaces this script's `Bash`-matcher group in place — never
  duplicates it. A `Bash`-matcher group belonging to a *different* hook is
  left alone (the `test("block-dangerous-commands\\.sh")` filter only matches
  this plugin's own handler).
- The script copy is overwritten (picks up plugin updates) — re-run after
  updating the plugin to refresh a stale copy.

## Coexistence with other plugins

Multiple plugins may each install their own `PreToolUse` hooks. Claude Code
runs all matching hooks; a `Bash` call runs every `Bash`-matcher hook present,
and any one of them returning exit 2 blocks the call. The merge above only
ever touches the group that references *this* plugin's script.

## Errors

| Error | Resolution |
|-------|------------|
| `Install directory does not exist` | Confirm or edit the target directory in Step 1. |
| `settings.json merge failed` | The existing `settings.json` is not valid JSON — fix it, then retry. |

## Related

- `hooks/block-dangerous-commands.sh` — the guardrail script itself.
- `/ai-dev-assistant:install-remembrance-hook` — the sibling opt-in hook
  installer this command mirrors in structure.
