# Getting Started with drupal-dev-framework

A 5-minute walkthrough. For the full reference, see [README.md](README.md).

## What this framework does

Guides Claude Code through a disciplined **Research → Architecture → Implementation** workflow for Drupal work. Instead of jumping straight to code, Claude:

- Searches contrib modules and core patterns first
- Documents architecture decisions before implementation
- Validates against quality gates at completion

You stay in control: Claude proposes, you approve.

## Step 1 — Install

```
/plugin marketplace add https://github.com/camoa/claude-skills
/plugin install drupal-dev-framework@camoa-skills
```

This pulls `dev-guides-navigator` and `code-quality-tools` automatically (v2.1.110+).

## Step 2 — Start your first project

A "project" is a logical unit of work — a custom Drupal module, a sub-theme, or a related set of features.

```
/drupal-dev-framework:new my_first_module
```

The framework asks a few short questions about scope, codebase location (`codePath`), and goals, then creates a project folder under `~/workspace/claude_memory/projects/<name>/`.

## Step 3 — Pick or create a task

A "task" is a single feature, bugfix, or component within a project.

```
/drupal-dev-framework:next
```

This is the only command you really need to remember. It:

- Lists your projects (or remembers the active one)
- Lists in-progress tasks (or offers to create a new one)
- Tells you exactly what command to run next

Want to skip the menu and create a task by name? Type a new task name when prompted (e.g., `settings_form`).

## Step 4 — Walk through the 3 phases

Each task goes through Research → Architecture → Implementation before code ships.

### Phase 1 — Research

```
/drupal-dev-framework:research settings_form
```

What happens:
- Claude scans drupal.org/contrib for existing solutions
- Searches Drupal core for matching patterns
- Loads relevant guides from [dev-guides](https://camoa.github.io/dev-guides/) (forms, entities, etc.)
- Writes findings to `<project>/implementation_process/in_progress/settings_form/research.md`

You review. Add or correct anything. The framework asks 4 short questions to scope the task if it looks complex (Goal / Expected result / Done when / Won't do here).

### Phase 2 — Architecture

```
/drupal-dev-framework:design settings_form
```

What happens:
- Claude proposes a design based on research
- Names components, dependencies, patterns to follow
- Maps acceptance criteria to architectural decisions
- Writes to `architecture.md`

You review. Adjust before code starts.

### Phase 3 — Implementation

```
/drupal-dev-framework:implement settings_form
```

What happens:
- Claude works through architecture step by step
- Writes tests first (TDD), then implementation
- You approve each change before it lands
- Progress recorded in `implementation.md`

You stay in the driver's seat. Claude asks before each significant change.

### Finish

```
/drupal-dev-framework:complete settings_form
```

What happens:
- Verifies all acceptance criteria are checked
- Runs quality gates (TDD / SOLID / DRY / Security / Guides)
- Moves the task folder to `completed/`
- Suggests the next task

## Step 5 — Returning to work

```
/drupal-dev-framework:next
```

That's it. `/next` figures out where you left off and tells you the next command.

## Common situations

### "I want to see my progress"

```
/drupal-dev-framework:status
```

Shows all projects and tasks with their current phase.

### "This task is bigger than I thought"

If a task is really 3-4 separable pieces of work, convert it to an **epic** with sub-tasks:

```
/drupal-dev-framework:migrate-to-epic <task-name>
```

The framework also prompts you when it detects this automatically.

### "I want to use my own conventions"

The framework ships with [Carlos's Drupal best-practices playbook](https://camoa.github.io/dev-guides/drupal/best-practices/camoa/) loaded by default. To use a different opinion-set OR add your own project-local rules:

```
/drupal-dev-framework:set-playbook-sets drupal/best-practices/<other>   # subscribe to a different set
/drupal-dev-framework:set-user-playbook /path/to/your/playbook.md       # add your own rules
```

Your local playbook always wins on conflict.

### "I need to run two Claude sessions on the same project"

Use a worktree:

```
/drupal-dev-framework:worktree <task-name>
```

This sets up `.worktrees/<task-name>/` on a separate branch so the two sessions don't collide.

## What's next

You're done with the basics. When you're ready for more:

- [README.md](README.md) — full command reference, references list, principles enforced
- [CHANGELOG.md](CHANGELOG.md) — what each version added
- [CLAUDE.md](CLAUDE.md) — internal conventions (read if extending the framework)
- [Dev-guides site](https://camoa.github.io/dev-guides/) — the published guides Claude loads

## One framework principle to remember

**Phases happen per task, not per project.** A single project can have one task in research, another in implementation, another completed. The framework tracks each independently. Use `/next` to navigate — it always knows where to resume.
