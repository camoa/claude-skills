# Session-Remembrance Hooks Pattern

A reusable cross-plugin pattern for plugins that maintain **per-project state**.
Scaffold it with `/plugin-creation-tools:add-component remembrance-hooks`.

## The failure mode it solves

Compaction, `/clear`, and new sessions strip context. Claude forgets which
plugin is active in a project, where the project's state lives, and any
user-specific conventions. Symmetrically, session termination leaves in-flight
notes unsaved because persistence is command-invoked, never automatic.

This is not domain-specific — every plugin that tracks ongoing project state
has the same failure mode.

## The pattern: two hook events + one command

A single install command per plugin wires **two** hook events into the user's
**project** `.claude/settings.json`:

| Event | Type | Matcher | Purpose |
|-------|------|---------|---------|
| `SessionStart` | `command` | none | `cat` a project primer to stdout. SessionStart stdout is injected as context, and the event fires on `startup`, `resume`, `clear`, **and `compact`** — so one no-matcher entry also covers post-compaction re-injection. |
| `SessionEnd` | `command` | none | Run a plugin-shipped `save-session.sh`. Bash-only — no AI possible at exit. Safety net. |

Pair the hooks with a `/save-session` slash command that calls the same script
*after* Claude reviews in-flight state. Two entry points, one script.

## Two corrections every adopter must copy

These come from the first adopter (drupal-dev-framework v4.5.0) and override the
pattern's original design sketch:

### 1. No `PostCompact` hook

It is tempting to add a `PostCompact` hook to re-inject the primer after
compaction. **It does not work.** Only `SessionStart`, `UserPromptSubmit`, and
`UserPromptExpansion` hook stdout is injected into Claude's context — every
other event's stdout goes to the debug log only (Hooks Reference, "Exit code
output"). A `PostCompact` `cat primer` hook is dead config.

The fix is free: a no-matcher `SessionStart` hook **already** fires after
compaction with `source: "compact"`. The pattern is **two** hook events, never
three.

### 2. Copy `save-session.sh` into the project — do not reference the plugin

The `SessionEnd` hook lives in the user's **project** `settings.json`.
`${CLAUDE_PLUGIN_ROOT}` is plugin-context only — it does **not** resolve in a
project settings file. An absolute plugin install path is no better: it breaks
on every plugin update (the install directory changes).

The install command must **copy** `save-session.sh` into
`<project>/.claude/<plugin-name>/save-session.sh` and have the hook reference it
via `${CLAUDE_PROJECT_DIR}`. Re-running the installer refreshes the copy. The
primer file is project-local for the same reason.

## Hard constraints (verified against the Hooks Reference)

- **`SessionStart` and `SessionEnd` support only `command` and `mcp_tool`
  handler types** — not `prompt`, not `agent`, and `SessionStart` not `http`
  either (Hooks Reference: "SessionStart and Setup support command and mcp_tool
  hooks. They do not support http, prompt, or agent hooks."). AI-decided
  behavior on `SessionStart` is achievable only indirectly — inject instructions
  and Claude reads them next turn. On `SessionEnd` it is not achievable at all:
  the session is terminating, no turn remains. `SessionEnd` persistence must be
  fully scripted.
- **`SessionEnd` has a 1.5 s default timeout.** A per-hook `timeout` set in a
  *project* `settings.json` raises the budget (up to 60 s); timeouts on
  plugin-provided hooks do **not** raise it. Install the `SessionEnd` hook with
  an explicit `timeout` (the pattern uses `10`) and keep `save-session.sh` to
  bounded, fast file I/O — no network, no AI.
- **Only `SessionStart` / `UserPromptSubmit` / `UserPromptExpansion` stdout
  reaches Claude's context.** This is the single fact the whole pattern rests
  on, and the reason `PostCompact` cannot be used.

## Idempotency: merge, never overwrite

The install command must **merge** its two entries into the existing
`settings.json` `hooks.SessionStart` / `hooks.SessionEnd` arrays. Dedupe by a
path substring unique to the plugin (the primer / script path) so a re-run
replaces the plugin's own entry in place and leaves every other hook — the
user's, other plugins' — untouched. A single `jq` filter does this; see the
`install-remembrance-hook.md.template` scaffold.

Multiple plugins installing their own `SessionStart` hook in the same project
do not conflict: Claude Code runs all matching hooks in parallel and
concatenates their stdout. Each plugin writes its own
`<project>/.claude/<plugin-name>/session-primer.md` and registers its own entry.

## The four artifacts each adopting plugin ships

1. **`templates/session-primer.md`** — a primer with `{placeholders}` plus an
   open `{user_additions}` section, and a generated-by header documenting the
   re-run-on-staleness contract.
2. **`scripts/save-session.sh`** — bash that persists whatever the plugin
   considers session state. No AI, no network. Exits 0 always.
3. **`commands/save-session.md`** — the judgement-first slash command: Claude
   reviews state, then runs the script.
4. **`commands/install-remembrance-hook.md`** — the interactive, idempotent
   installer described above.

`/plugin-creation-tools:add-component remembrance-hooks` scaffolds all four with
`TODO(plugin-author)` markers on the plugin-specific logic (project resolution,
state-file scheme, the state scan).

## Adoption fit

Adopt when the plugin maintains **ongoing per-project state** Claude must not
forget mid-flight — task/phase state, an active brand or design project,
pipeline intermediate state. Skip for stateless plugins (a single command path,
no project memory) — the primer would add nothing the plugin's own skill
descriptions don't already convey. A plugin used to *build other plugins* rather
than maintain project state (like plugin-creation-tools itself) should not adopt
the pattern.

## What the pattern is NOT

- Not validation or enforcement of plugin rules — that is a separate concern.
- Not a replacement for a project-root `CLAUDE.md`. `CLAUDE.md` is project-wide
  always-on context; the primer is plugin-scoped, post-compaction-resilient
  state the user can edit freely without touching `CLAUDE.md`.
- Not automatic. Install is opt-in per project per plugin.
