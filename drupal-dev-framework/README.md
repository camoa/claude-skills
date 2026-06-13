# drupal-dev-framework — DEPRECATED

This plugin has been renamed to **ai-dev-assistant**. Install that going forward.

`drupal-dev-framework` remains installable only as a thin **deprecation shell** whose
sole job is to run a **one-time upgrade** that migrates your local wiring to the new
plugin:

- repoints your project store (`~/.claude/drupal-dev-framework/`) to
  `~/.claude/ai-dev-assistant/`, and
- re-stamps each registered project's session-remembrance hooks to the new paths.

## Only `/drupal-dev-framework:upgrade` appears in the menu

The shell still carries every old command **name** on disk, but each one is a symlink
to the single `upgrade` command. Claude Code resolves command symlinks to their target
and de-duplicates them, so only **`/drupal-dev-framework:upgrade`** shows up in the `/`
menu. This is intentional — the shell exists only to migrate you, not to keep running
the old workflow. Use the new namespace for everything else: `/ai-dev-assistant:next`,
`/ai-dev-assistant:research`, `/ai-dev-assistant:implement`, and so on. The command
names are unchanged; only the `drupal-dev-framework:` namespace moved to
`ai-dev-assistant:`.

## Migrate, then switch plugins

1. **Install the new plugin first** (it is the migration target):
   `/plugin install ai-dev-assistant@camoa-skills`.
2. **Run the migration** from the still-installed shell: `/drupal-dev-framework:upgrade`.
   It shows a `--dry-run` first, then performs the move on your confirmation. It is
   idempotent and never deletes data — safe to re-run.
3. **Disable or uninstall this shell** once the upgrade reports success, and use
   `ai-dev-assistant` from then on:
   - **Disable / re-enable** without removing it: open the `/plugin` menu →
     *Manage plugins* → toggle `drupal-dev-framework`. Disable it to clear the
     `/drupal-dev-framework:upgrade` entry from your menu; re-enable it only if you
     need to re-run the migration on another project.
   - **Uninstall outright** when you are done migrating everywhere:
     `/plugin uninstall drupal-dev-framework@camoa-skills` (or remove it from the
     `/plugin` menu).

After migrating, `/ai-dev-assistant:next` resumes your work exactly where
`/drupal-dev-framework:next` left off — the project store and registered projects carry
over untouched.
