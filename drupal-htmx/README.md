# Drupal HTMX Plugin

[![Listed on ClaudePluginHub](https://www.claudepluginhub.com/badge/camoa-drupal-htmx-drupal-htmx)](https://www.claudepluginhub.com/plugins/camoa-drupal-htmx-drupal-htmx?ref=badge)

Migrating Drupal AJAX to HTMX by hand is fiddly and easy to get wrong: it is easy to drop `onlyMainContent()` and ship a full page where a fragment belongs, to miss an `aria-live` region a screen reader needed, or to guess at a pattern that Drupal core already has a cleaner answer for. This plugin gives you an analyzer that finds the AJAX worth migrating, a recommender for the right HTMX pattern before you write new code, a guided step-by-step migration, and a validator that checks the result against Drupal 11.3+'s native HTMX support, so the decision is informed and the result is checked instead of guessed at.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md): skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

## See it in action

A migration on one form, real commands, output trimmed to the lines that matter.

```text
$ /drupal-htmx:htmx-analyze modules/custom/my_module
  ## AJAX Analysis Report: my_module
    Files with AJAX: 3, patterns: 5 (3 simple, 1 medium, 1 complex)
    Simple: src/Form/MyForm.php:45 - Dependent dropdown
    Next steps: Run /htmx-migrate src/Form/MyForm.php for guided migration

$ /drupal-htmx:htmx-migrate modules/custom/my_module/src/Form/MyForm.php dropdown
  Shows the current #ajax callback next to the Htmx-class equivalent, then a
  migration checklist: remove #ajax, add the Htmx configuration, move callback
  logic into buildForm(), delete the now-unused callback method.

$ /drupal-htmx:htmx-validate modules/custom/my_module
  ## HTMX Validation Report: my_module
    Issues found: 2
    Critical: MyForm.php:67 - missing onlyMainContent() (full page HTML returned)
    Warning:  MyForm.php:89 - no aria-live attribute on the dynamic region
```

Nothing here is auto-applied. `/htmx-migrate` shows you the before and after and you make the edit; `/htmx-validate` then tells you what it still owes, including the accessibility check most hand-written migrations skip.

## When to reach for it

- **You have existing AJAX** in a custom module and want to know what is worth converting and in what order. Start with `/htmx-analyze`.
- **You are building something new** (a dependent dropdown, infinite scroll, a multi-step wizard) and want the HTMX pattern before you write AJAX you will migrate later anyway. Start with `/htmx-pattern`.
- **You are unsure whether a given interaction should be HTMX or AJAX at all.** Both can coexist and migrating incrementally is fine; see the `/branch` tip below for comparing both paths on the same context.
- **Not for** core or contrib modules: everything here targets custom code only, and it does not scan or modify contrib or core unless you explicitly ask.

## Commands

| Command | Purpose |
|---------|---------|
| `/htmx [path]` | Quick status scan; suggests the next command. |
| `/htmx-analyze <path>` | Analyze a module's AJAX patterns and rank migration candidates by complexity. |
| `/htmx-migrate <file> [pattern]` | Guided before/after migration for one file. |
| `/htmx-pattern <use-case>` | Recommend the HTMX pattern for a use case, with a code example. |
| `/htmx-validate <path>` | Check an implementation for correctness and accessibility. |

Three read-only agents back the commands that need deeper scanning (`ajax-analyzer`, `htmx-recommender`, `htmx-validator`; all sonnet, `Read`/`Glob`/`Grep` only). The `htmx-development` skill auto-activates on HTMX and AJAX-migration topics so it can surface guidance even outside these commands. Full command reference, the skill's effort-adaptive depth, and how it fits with the rest of the marketplace: [docs/usage.md](docs/usage.md).

## Installation

```bash
# Add the marketplace
/plugin marketplace add https://github.com/camoa/claude-skills

# Install
/plugin install drupal-htmx@camoa-skills
```

**Requirements:** Drupal 11.3+ (this is where native HTMX support landed; there is no legacy-AJAX guidance here by design) and Claude Code.

**Recommended companion:** `dev-guides-navigator`, for the Drupal forms/routing/render-API context the skill pulls in at `high` effort and above.

## Tips

**Deciding HTMX vs AJAX with `/branch`.** When a migration could go either way, use Claude Code's `/branch` to fork the session at the decision point and try each path against the same loaded context: implement the HTMX version in one branch, keep the AJAX version in another, then compare. The original session is unchanged and stays in the session picker.

**Effort-adaptive depth.** The `htmx-development` skill scales to the active effort level: `low` emits HTMX scaffolding and stops; `medium` and above also run the validation checklist inline; `high`/`xhigh`/`max` additionally cross-reference the Drupal forms and JS-development dev-guides.

**Skill visibility.** `htmx-development` triggers proactively on common terms like "AJAX" and "Drupal". If that is noise on a given project, `skillOverrides` in `.claude/settings.json` (Claude Code v2.1.129+) can dial it back per skill without editing the plugin: `"user-invocable-only"` suppresses proactive triggering, `"name-only"` keeps it reachable for cross-skill delegation only, `"off"` hides it entirely.

## References

Condensed reference guides ship with the plugin's skill (`skills/htmx-development/references/`): `quick-reference.md` (command equivalents, method tables), `htmx-implementation.md` (the `Htmx` class API, detection, JS integration), `migration-patterns.md` (7 detailed migration patterns), and `ajax-reference.md` (AJAX commands, for reading existing code). Online dev-guides at [camoa.github.io/dev-guides](https://camoa.github.io/dev-guides/) supply the supplementary Drupal domain context (AJAX architecture, forms, routing, render API, JS behaviors).

## More

- **Deeper how-to:** [docs/usage.md](docs/usage.md). Prerequisites, "it's working if", the full command reference, where this fits with the rest of the marketplace.
- **Changelog:** [CHANGELOG.md](./CHANGELOG.md).

## License

MIT
