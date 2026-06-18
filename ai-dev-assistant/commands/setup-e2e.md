---
description: "Resolve and follow the project's e2e-setup process recipe(s) to stand up a behavioral E2E test harness, scaffold tests/e2e/, seed the surface registry, and discover site journeys. Framework-agnostic: the per-framework recipe supplies the stack specifics. Idempotent. Use --add-journey to add a single journey post-setup."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill
argument-hint: "[--add-journey <description>] [--skip-demo-recipe] [--skip-discovery]"
---

# /setup-e2e

Resolves the e2e-setup process recipe for each of the project's frameworks (via the `process-recipe-loader` skill) and follows each resolved recipe to install the test harness, scaffold `tests/e2e/`, wire the runner's e2e project, seed the surface registry, and discover site journeys. The command owns the interface and the orchestration (validate flags, resolve code path, dispatch the loader, act on its results). The recipe owns the stack-specific work: what to install, how to scaffold, how to bind the gate, and how to discover journeys. Any stack assumptions (runtime, package manager, required modules) live in the recipe's preconditions, not here.

## Arguments

- _(no args)_: full setup. Resolve and follow the e2e-setup recipe(s), including journey discovery
- `--add-journey <description>`: re-enter the recipe's journey-discovery step for one new journey (no reinstall)
- `--skip-demo-recipe`: passed through to the recipe. Recipes that seed demo content skip that step (use on sites with real content)
- `--skip-discovery`: follow the recipe's install and scaffold steps only. Skip its journey-discovery step
- `--force`: re-run even when the recipe's idempotency probe reports `complete`

Unsupported flag: `--variant cypress` → print `"/setup-e2e: only the Playwright variant is supported in v1. --variant cypress is not available."` and exit.

## Step 1: Validate arguments and resolve project context

Parse `$ARGUMENTS`. If `--variant` appears (in any form: `--variant cypress`, `--variant=cypress`, `--VARIANT cypress`, case-insensitive) with the value `cypress`, print the literal message above and stop. (EC-F14)

Read the active project's state by running `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parsing its JSON:

- `.codePath`: if null or unknown (`.codePath == null`, or a `code_path_unknown` / `code_path_missing` warning), prompt the user to run `/set-code-path` first and stop.
- `.frameworks`: the project's framework list. If it is empty (`[]` or absent), do **not** assume any stack. Print: `"setup-e2e: no frameworks recorded for this project. Run /upgrade-project to backfill frameworks, or set them in project_state.md, then re-run /setup-e2e."` and stop. The point-of-need detect-or-ask sub-protocol (`references/recipe-resolution.md` step 6) does not cover setup commands — adopt frameworks first via `/upgrade-project` or the recipe-adoption flow before running `/setup-e2e`.

**Non-web precondition guard.** Certain frameworks have no web UI and therefore no meaningful E2E harness. After reading `.frameworks` (and only when it is non-empty), check whether every framework in the list is a member of the **non-web set**:

> Non-web frameworks: `claude-code-plugins`
> (extend this list as new non-web frameworks are detected)

If **all** frameworks are in the non-web set → print:

```
setup-e2e: e2e/visual-regression is not applicable to a non-web framework (<comma-list of frameworks>); skipping — no harness scaffolded.
```

and exit (stop, no scaffold, no recipe resolution). If `.frameworks` is empty, or if **any** framework is not in the non-web set (i.e. at least one web framework is present), proceed exactly as today — no behavior change for web projects.

## Step 2: --add-journey fast path

If `--add-journey <description>` is present:

- Guard: if `tests/e2e/` does not exist at `<codePath>`, print: `"setup-e2e: run /setup-e2e first before using --add-journey."` and stop. (EC-F6)
- Extract the description text following the flag. If the description is empty (nothing after the flag), print: `"setup-e2e: provide a journey description: /setup-e2e --add-journey <description>"` and stop. (EC-F15)
- Note: `--skip-discovery` has no effect when `--add-journey` is also present. `--add-journey` takes precedence and `--skip-discovery` is silently ignored. (EC-F16)
- Collect existing journey slugs by globbing `<codePath>/tests/e2e/specs/*.md` and taking the basenames without extension (empty list if the directory is absent). These tell the recipe's discovery step not to overwrite an authored journey.
- Resolve the e2e-setup recipe(s) using the loader invocation in Step 3, then follow **only** the journey-discovery portion of each resolved recipe, in add-one mode, for `<description>` and the existing-slugs context. Do not run the install or scaffold steps.
- Skip the remaining steps.

## Step 3: Resolve and follow the e2e-setup process recipe(s)

Follow the shared recipe-resolution protocol in `references/recipe-resolution.md` with `phase: e2e-setup` and the active project's `<project_folder>` (resolved in Step 1). That protocol invokes the `process-recipe-loader` skill, resolves each framework's recipe (project_state-first, then source order, else `action:ask-user`), records the source in `project_state.md`, and defines how to follow each result: Read the `body_path` (never streamed), follow `verified:true` directly, surface `verified:false` for human review first, and on `action:ask-user` ask the user for a path or to research. Surface any loader `warnings[]` (for example `no_frameworks_defined`, `navigator_unavailable:<framework>`) to the user.

When you follow an available recipe, supply its input contract from the resolved context and flags: `code_path` = `<codePath>`, `skip_demo_recipe` from `--skip-demo-recipe`, honor `--skip-discovery` by not running the recipe's journey-discovery step, and honor `--force` by re-running past the recipe's idempotency probe. The recipe handles the install, the `tests/e2e/` scaffold, the runner's e2e project entry, the registry and preflight seeding, and journey discovery.

**Record the resolution (recipe-resolution.md step 7).** After resolving, run `${CLAUDE_PLUGIN_ROOT}/scripts/recipe-declarations-audit.sh --body <body_path> --phase e2e-setup --framework <fw>` per resolved framework and surface any `absent_recommended` declaration as a one-line advisory (e2e-setup carries the `recommended:true` `preflight_command` field, so a missing one is flagged here). Then, **only when a task folder is in scope**, write `_recipe-load.json` via `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh "<task_folder>" recipe-load "<payload>"` (per `references/gate-audit-schema.md` §5.12); `/setup-e2e` usually runs project-level with no task folder, in which case skip the write with a note (the lint still runs). Observability only — never blocks.

## Step 4: Summary

Print a summary:

- Frameworks processed, and for each: the resolved recipe `key`, its `source`, and whether it was `verified`
- Files created and scaffolded under `tests/e2e/`
- Journey specs staged (if any)
- Surface registry surfaces added
- Any framework left without a recipe (`research-needed`)
- Next steps: `run /ai-dev-assistant:validate:e2e` · `add more journeys with --add-journey` · `review specs in tests/e2e/specs/`
