# Drupal Dev Framework - Plugin Conventions

## Task Hierarchy (v3.10.0+)

The plugin supports **opt-in epic/sub-task hierarchy** on top of flat tasks (which remain first-class). Concepts:

- **Flat task** — default. No frontmatter needed. Behaves exactly as v3.0.0+.
- **Epic** — a task folder containing `task.md`, `shared/`, `in_progress/<subtasks>/`, and `completed/<subtasks>/`. Declared via `task.md` frontmatter (`kind: epic`, `children: [local:<id>, ...]`).
- **Sub-epic** — a subtask that is itself an epic (second and final nesting level; no sub-sub-epics).
- **Subtask** — a task nested inside an epic's `in_progress/` (while active) or `completed/` (when done). Completion never removes a subtask from its parent epic.

**Key commands:**
- **`/drupal-dev-framework:migrate-to-epic <task>`** — convert a flat task into an epic. Manual, per-task, transactional. Supports `--dry-run` and `--children "a,b,c"`.
- `/status` is hierarchy-aware — renders a tree for epics, flat list for flat tasks.
- `/next` biases toward sibling subtasks inside the active epic; surfaces `/migrate-to-epic` when a task looks epic-sized.
- `/complete` enforces epic-completion gates (all children done before the epic itself completes).

**When to promote a task to epic:** many heterogeneous acceptance criteria, long-in-progress without phase progression, or user signals "this is too big." Most tasks should stay flat — epic-ification is additive, not aspirational.

**Automated epic proposal (`/propose-epics`) and alignment-step (P7) land in sub-tasks 3.2 / 3.3.** In v3.10.0, the primitive is manual.

## Agents
- Frontmatter must include: name, description, capabilities, version, model
- Description starts with "Use when..." for auto-delegation
- Read-only agents must have `disallowedTools: Edit, Write`
- Agents that learn across sessions should have `memory: project`

## Skills
- Frontmatter must include: name, description, version
- Add `model:` matched to complexity (haiku for lookup, sonnet for balanced, opus for complex)
- Internal-only skills must have `user-invocable: false`
- Body uses imperative voice — instructions for Claude, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` for discoverability
- Restrict `allowed-tools` to minimum needed

## Online Dev-Guides — Proactive Usage
**ALWAYS consult dev-guides before making Drupal development decisions** unless the relevant guide was already loaded in this session.
- Use the `dev-guides-navigator` skill for topic discovery, caching, and disambiguation
- Do NOT fetch `llms.txt` or dev-guides URLs directly — invoke the navigator skill instead
- The `guide-integrator` and `guide-loader` skills delegate to the navigator
- **Phase 1 (Research):** Load guides for the task's Drupal domain (forms, entities, plugins, etc.)
- **Phase 2 (Design):** Load guides for architecture decisions (services, routing, caching, config)
- **Phase 3 (Implementation):** Load guides for security, SDC, JS patterns before writing code
- If a guide was loaded earlier in the session, do not re-fetch — use the cached content

## Recurring Checks with /loop

Users can poll deploy status or run periodic checks during long sessions:

```
/loop 5m check if drush cr finished and the site is responding on https://mysite.ddev.site
/loop 2m check if the config import completed
/loop 10m /drupal-dev-framework:status
```

Session-scoped — stops when session exits. 3-day auto-expiry.

## Sandbox and DDEV

If users enable Claude Code sandboxing (`/sandbox`), DDEV commands will fail because Docker socket access is restricted. Required configuration:

```json
{
  "sandbox": {
    "excludedCommands": ["ddev"],
    "filesystem": {
      "allowWrite": ["~/.ddev", "/tmp"]
    }
  }
}
```

`ddev` must be in `excludedCommands` (not `allowWrite`) because it uses the Docker socket which sandboxing blocks at the network level.

## Path-Specific Rules for Drupal Projects

Recommend users create `.claude/rules/` files scoped to file types for Drupal-specific conventions:

- `drupal-php.md` with `paths: ["*.php", "*.module", "*.install"]` — PHP coding standards, service injection, hook naming
- `drupal-twig.md` with `paths: ["*.twig", "*.html.twig"]` — Twig coding standards, accessibility, escaping
- `drupal-scss.md` with `paths: ["*.scss"]` — BEM, Bootstrap usage, mobile-first

These load only when Claude works on matching files, keeping context lean.

## General
- Current state only — no historical narratives
- Replace outdated content, don't keep alongside new
- Every edit is a chance to prune irrelevant content
- Reference files instead of reproducing content
