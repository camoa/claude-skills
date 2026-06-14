# Recipe resolution: the one protocol for a framework-specific step

This is the uniform protocol any generic phase, command, or agent follows the moment it hits a
framework-specific step. It lives in one place so every lifecycle phase resolves its process recipe
the same way. The single resolver is the `process-recipe-loader` skill; this doc is the contract
callers cite instead of re-describing the steps inline.

## The protocol

1. **Recognize the dependency.** You have a framework-specific step here (install a package, scaffold
   a layout, discover surfaces, derive a matrix, follow a stack-specific procedure). Do **not**
   proceed generically and do **not** guess the stack specifics. You must resolve a recipe first.

2. **Invoke the loader.** Call the `process-recipe-loader` skill (Skill tool) with:
   - `phase`: your phase id (see the declared list below)
   - `project_folder`: the active project's folder

3. **Let the loader resolve and record.** For each framework in the project the loader:
   - checks `project_state` first. A recorded entry under `**Process Recipes:**`
     (`- <phase>/<framework>/<slug> → source=<src>`) is the memory of the prior decision and
     resolves directly from its recorded source (no re-searching).
   - on a miss (no recorded entry) searches by source order: repo-local → machine-local →
     dev-guides (via the navigator).
   - on a true miss (no record and nothing in the source order) returns `action:ask-user`.
   - records or updates the source choice in `project_state.md` so the next run is a hit.

   It returns JSON:
   ```
   {schema_version, phase, results:[{framework, key, source, sha, verified, available,
     body_path, recorded, notes[], action}], warnings[]}
   ```
   Surface any `warnings[]` to the user. The recipe body is **never** streamed into context; the
   loader reports a `body_path` (an on-disk file) for you to Read.

4. **Follow each available result.** For every result with `available:true`:
   - Read the body from `body_path` with the Read tool (nothing is streamed; you Read the file).
   - `verified:true` (a dev-guides upstream body) → follow it directly.
   - `verified:false` (a `local` / `machine-local` / researched body) → surface it for human review
     and get an explicit go-ahead **before** following it. The execute-or-halt decision is the
     orchestrator's, never the loader's.

   **How to deliver the body to whoever follows it.** "Follow it" has two concrete delivery modes; a
   phase uses whichever fits how it does the work:

   - **Command follows it directly** (the command's own agent executes the recipe steps in place; for
     example `/setup-e2e` installs the harness itself). Read `body_path` with the Read tool, then
     follow those steps in place.
   - **Command dispatches a generic agent to follow it** (the command spawns a stack-neutral agent to
     execute the recipe; for example `/research` spawns `prior-art-researcher`). Read `body_path` with
     the Read tool, then dispatch the agent with the Task tool and include the recipe body **verbatim**
     in the agent's prompt, inside a clearly delimited block:

     ```
     === RESOLVED RECIPE (key=<key>, source=<source>, verified=<verified>) ===
     <full recipe body text>
     === END RECIPE ===
     ```

     The agent treats that block as the method to follow. The agent **never** resolves the recipe
     itself and needs no Skill tool.

   **The rule:** the body must be passed to whoever follows it. Reading `body_path` and then
   dispatching an agent **without** including the body in the agent's prompt is a bug. The agent would
   have no method to follow. Whichever delivery mode a phase uses, the body that was Read is the input
   to the follow-step.

5. **Handle a true miss (`action:ask-user`).** When a result has `available:false` and
   `action:ask-user`, ask the user: `no <phase>/<framework> recipe found; provide a path or say
   research it`. On a path, the user's recipe becomes a `local` source. On "research it", research
   live and save the result to a local file (`source=research` is transient and flips to
   `source=local` once saved). Either way the loader records the chosen source, so the next phase run
   short-circuits. Never fabricate a recipe.

6. **No body resolved (do not dispatch a method-less agent).** The follow-step from step 4 (whether
   the command follows in place or dispatches a generic agent) runs **only** when a `body_path` is
   present. When no body resolved for a framework there is no method to follow, so do not dispatch the
   generic agent and do not invent steps. Handle each no-body case explicitly:

   - **`results:[]` with `no_frameworks_defined`** (the project has no frameworks recorded): tell the
     user to run `/upgrade-project` to backfill frameworks, or to set them in `project_state.md`, then
     skip the framework-specific step gracefully for this run.
   - **`action:ask-user`** (a true miss): ask the user for a path or to research it, per step 5, and
     proceed according to the answer. Until a body is resolved and Read, there is nothing to follow.
   - **A framework whose result is `available:false`** with no `body_path` for any other reason: skip
     that framework with a clear note to the user, and continue with the frameworks that did resolve.

   The generic-agent dispatch and the follow-in-place step both require a `body_path` that was Read.
   No `body_path` means no follow-step for that framework.

## Who invokes the loader (commands, not agents)

The **phase command** invokes the loader and injects the resolved body for its agent to follow. The
agents stay generic: they need no framework knowledge and no Skill tool. The command owns the
interface and orchestration (resolve project + code path, call the loader, act on its results, follow
or surface each body); the recipe owns the stack specifics. This keeps the resolution logic in
exactly one place and the agents stack-neutral.

## Phases that resolve a framework recipe

One declared list, so it is not scattered. A generic step in any of these phases follows the protocol
above with the matching `phase` id:

- `research`
- `design`
- `implement`
- `review`
- `e2e-setup`
- `visual-regression`

## See also

- `references/recipe-interface.md`: the **content** contract — what a resolved recipe body may declare
  (the five gate declarations) so the plugin's gates can act on it. This doc is transport; that doc is content.
- `skills/process-recipe-loader/SKILL.md`: the single resolver (source arms, trust model, the
  `project_state` short-circuit, the ask-user miss, the `project_state.md` source-record write)
- `scripts/project-state-read.sh`: emits `frameworks`, `codePath`, `localGuidesPath`, `processRecipes`
