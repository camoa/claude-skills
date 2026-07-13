# Using Plugin Creation Tools

The [README](../README.md) is the shop window. This is the how: what the plugin does, when to reach for it, what it needs, how you know it is working, and where it fits with the rest of the marketplace.

## What it does

`/plugin-creation-tools:create` scaffolds a new plugin from templates: pick a name and the components you want (`--skill`, `--command`, `--agent`, `--hook`, `--mcp`), and it lays down `plugin.json`, a README, and a stub for each component, already shaped to the current plugin spec. `/plugin-creation-tools:add-component <type> <name>` does the same for one component on a plugin that already exists, including a theme or the session-remembrance hook pattern. Underneath both, the `plugin-creation` skill auto-triggers whenever you are authoring any of this and progressively discloses the reference that matches what you are building, so you get the frontmatter schema, the hook event payload, or the SDK note you need, not the whole doc set at once.

`/plugin-creation-tools:validate` is the gate. It parses every frontmatter block as real YAML rather than eyeballing it (a block that fails to parse loads with no metadata at runtime, silently), checks manifest keys against the documented `plugin.json` / `marketplace.json` / `settings.json` schemas, walks all 30 hook events and five handler types, and runs a deterministic bash kernel that scans for absolute home paths, leaked secrets, and personal emails before anything reaches a public marketplace. A tagged subset of findings is auto-fixable with `--fix` (mechanical, reversible, logged); `--strict` promotes warnings to errors for CI. Two read-only agents go past what the validator checks structurally: `plugin-structure-auditor` for architecture balance and cross-component consistency, `skill-quality-reviewer` for whether a skill's description and body actually route and read well.

## When to reach for it

- **Starting a plugin or adding a component to one.** `create` and `add-component` save you from reconstructing a frontmatter schema, a hook event list, or a manifest shape from memory or an old example that has since drifted.
- **Before a PR or a marketplace publish.** `validate` is the pre-publish gate. Run it plain first to see the findings, then `--fix` for the mechanical ones, then re-run to confirm.
- **When a skill or command's description, structure, or progressive disclosure needs a second opinion.** `skill-quality-reviewer` catches things `validate` does not check for: whether the description actually routes, whether the body reads as instructions or documentation, whether prior imperatives (`PROACTIVELY`, `MUST`, `NEVER`) survived an edit.
- **When a plugin has grown past a couple of components and you want to check the shape holds together.** `plugin-structure-auditor` looks at architecture, cross-component consistency, and performance footguns that a per-file validator does not see.
- **Any time `ai-dev-assistant` runs a task that touches plugin files.** Its review method invokes this plugin's validate gate and both agents automatically, so plugin work goes through the same lifecycle as any other code.

It is not needed for a throwaway prompt you are not distributing. Reach for it once a component is going in front of someone else, or before you trust a "looks done" plugin enough to publish it.

## Prerequisites

- Claude Code, with this plugin installed (`/plugin install plugin-creation-tools@camoa-skills`).
- A plugin root with `.claude-plugin/plugin.json` for `add-component` and `validate` to find; `create` makes one for you.
- Git, if you want `--fix` reviewed the normal way: `--fix` writes non-interactively (it is a forked command with no confirmation turn), so `git diff` is how you review what it changed, and `git restore` is how you undo it.
- No external services or API keys. Every check runs locally; the containment scan is a bundled bash script, not a network call.

## It's working if

- `/plugin-creation-tools:create <name> --skill` produces a plugin directory with `.claude-plugin/plugin.json`, a `README.md`, and a `skills/<name>/SKILL.md` stub in place.
- `/plugin-creation-tools:add-component command <name>` produces `commands/<name>.md` from the command template, and the new command shows up when you list the plugin's commands.
- `/plugin-creation-tools:validate <path>` prints the `## Plugin Validation: {name} v{version}` report with Errors / Warnings / Info / Checked-clean sections and a `PASS` or `FAIL` result, using a deterministic component count (not an eyeballed one) in the clean section.
- `/plugin-creation-tools:validate <path> --fix --dry-run` lists the migrations it would make without writing anything; running the same command without `--dry-run` writes them and appends an entry to `.claude-plugin/.validate-fixes.log`.
- A plugin with a leaked absolute home path or a token in a tracked file fails validation with a **P01** or **P02** error, not a warning, and the match is redacted in the output.

If `validate` reports it cannot find `.claude-plugin/plugin.json`, you are not pointed at a plugin root, pass the path explicitly rather than relying on current-directory detection.

## Where it fits

- **[ai-dev-assistant](../../ai-dev-assistant/README.md)** invokes this plugin's `validate` gate and both agents when a task's Phase 4 review touches Claude Code plugin files, so plugin work runs the same Research → Architecture → Implementation → Review lifecycle as application code.
- **[code-paper-test](../../code-paper-test/README.md)** is the behavioral complement: this plugin checks structure (does the frontmatter parse, does the manifest key exist, is the field on the right component type); code-paper-test mentally executes a skill or command to check whether it actually does what it claims. Both run as part of a plugin's review method.
- **[dev-guides-navigator](../../dev-guides-navigator/README.md)** and **[code-quality-tools](../../code-quality-tools/README.md)** are not dependencies of this plugin, but sit alongside it in the same marketplace: this plugin's job stops at plugin-authoring structure, not application code quality or guide discovery.

For the reasoning behind gates that enforce structure rather than advice that is easy to drift from, see the marketplace [PHILOSOPHY.md](../../PHILOSOPHY.md).
