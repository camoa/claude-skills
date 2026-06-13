# drupal-dev-framework — DEPRECATED

This plugin has been renamed to **ai-dev-assistant**. Install that going forward.

`drupal-dev-framework` remains installable only to run a **one-time upgrade** that
migrates your local wiring to the new plugin:

- repoints your project store (`~/.claude/drupal-dev-framework/`) to
  `~/.claude/ai-dev-assistant/`, and
- re-stamps each registered project's session-remembrance hooks to the new paths.

Once you've migrated, uninstall this plugin.
