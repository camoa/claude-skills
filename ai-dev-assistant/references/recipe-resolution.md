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
   - **Maintainer recipe-gap note (v5.16.0+, propose-only — Surface 3 in
     `references/maintainer-create-on-miss.md`).** Before the ask-user prompt, run
     `${CLAUDE_PLUGIN_ROOT}/scripts/maintainer-mode-detect.sh`; when `maintainer_mode == true`, **append**
     one informational line to the prompt — "💡 Maintainer note: no published `<phase>/<framework>`
     recipe exists in the catalog; whatever you resolve here is local (`verified:false`) — consider
     authoring a catalog recipe later (not done automatically)." This is **propose-only**: it adds no
     extra prompt, no authoring handoff, and never blocks; the existing path/research-local resolution
     proceeds unchanged. Consumers (`maintainer_mode == false`) never see the note.

6. **No body resolved (do not dispatch a method-less agent).** The follow-step from step 4 (whether
   the command follows in place or dispatches a generic agent) runs **only** when a `body_path` is
   present. When no body resolved for a framework there is no method to follow, so do not dispatch the
   generic agent and do not invent steps. Handle each no-body case explicitly:

   - **`results:[]` with `no_frameworks_defined`** (the project has no frameworks recorded): run the
     **framework-resolution branch** below, which drives the cascade in
     `references/framework-resolution.md`. The *need* for a recipe is the trigger to resolve a framework,
     not a reason to silently run stack-neutral forever. Do **not** merely tell the user to run
     `/upgrade-project` and skip.
   - **`action:ask-user`** (a true miss): ask the user for a path or to research it, per step 5, and
     proceed according to the answer. Until a body is resolved and Read, there is nothing to follow.
   - **A framework whose result is `available:false`** with no `body_path` for any other reason: skip
     that framework with a clear note to the user, and continue with the frameworks that did resolve.

   The generic-agent dispatch and the follow-in-place step both require a `body_path` that was Read.
   No `body_path` means no follow-step for that framework.

7. **Surface the declaration fail-open + record the outcome (observability, v5.11.0+).** Recipe
   resolution degrades to the framework-neutral floor *silently* when a recipe is absent or a recipe body
   is missing a gate declaration — deliberate (stack-agnostic, never block), but until now invisible and
   unrecorded. Make that degradation **visible and auditable**. This step **observes; it does not gate.**

   - **Declaration lint.** For each framework whose body you Read in step 4, on a **declaration-bearing
     phase** run `scripts/recipe-declarations-audit.sh --body <body_path> --phase <phase> --framework
     <framework>` (zero-model kernel, always exit 0). The kernel scopes the expected declarations **per
     phase** — it returns `declarations:[]` for `research` (the body is followed verbatim, nothing grepped),
     so the lint is a no-op there and may be skipped; for the other phases it returns only the gate-consumed
     tokens, so you do not hardcode which phase carries what. When
     `summary.absent_recommended > 0`, surface a **one-line advisory** per absent recommended declaration —
     e.g. *"recipe `<framework>/<phase>`: expected `<token>` absent; the gate will use the neutral floor. If
     intended, ignore; if a typo, fix the recipe."* This is what catches a misspelled declaration
     (`## Screenshots` vs `## Screenshot capture`) that would otherwise be silently ignored (an advisory
     fires only for a `recommended:true` token — today that is `review`, `visual-regression`, and
     `e2e-setup`; `research`/`design`/`implement` carry no required token, so their lint is a clean no-op).
     **Never block** — an absent declaration is a valid agnostic-floor choice. Capture each kernel's JSON
     for the audit below.
   - **Assess whether the method fits the task (v5.30.1+).** Before recording, read the resolved body
     and answer one question about each: does this method describe the kind of work this task actually
     does? Routing chose it by phase and framework alone and never asked what the task is, so the answer
     is genuinely open. Record it as `frameworks[].method_fit` = `{verdict, reason}`, verdict one of
     `fits` / `partial` / `mismatch` / `undetermined`, reason one line and mandatory for `partial` and
     `mismatch`. `undetermined` is a real answer for a body you did not read; what is not allowed is
     leaving it out, because an unassessed recipe then reads exactly like a suitable one.
     **A mismatch never changes what you do here.** Inject the body verbatim as this protocol requires
     and follow it. A mismatch means the method's own steps may return an explicit nothing-applicable,
     and that a later phase should read the verdict rather than assume the work was measured against a
     method that suited it. Do not manufacture work to satisfy an ill-fitting recipe, and do not skip
     the recipe because it fits poorly.
     **Then make it durable.** `_recipe-load.json` is overwrite-on-fire, so a verdict written only there
     is gone at the next phase. Append `fit=<verdict>` to this recipe's line in `project_state.md`'s
     `**Process Recipes:**` block — `- design/drupal/architecture → source=dev-guides fit=mismatch`.
     `scripts/project-state-read.sh` parses it into `processRecipes[].fit`; absent parses as `null`.
     This step exists because it twice did not. An environment task — three configuration values and a
     build — was handed a contrib-module prior-art method, then a service-and-plugin architecture method.
     Both phases saw it and wrote a paragraph into a `notes` key no consumer reads, and both times the
     observation was gone by the next phase.
   - **Record `_recipe-load.json`** — every phase run that resolves recipes and has a task folder in scope.
     Assemble the `recipe-load` payload (`references/gate-audit-schema.md` §5.12) and write it with
     `scripts/gate-audit-write.sh "<task_folder>" recipe-load "<payload>"`. Include every framework the
     phase considered (resolved or not) with its `source`/`verified`/`available`/`body_path`, its
     `declarations_audit` (the kernel JSON, or `null` for `research`/`design`), its `method_fit` from the
     step above, at `phase: review` its `arch_validate` outcome from the step-5.0 `architecture-validator`
     dispatch (`{verdict, sidecar, reason}`, verdict including `no_return` for an absent sidecar — the
     field the reason lives in; `references/gate-audit-schema.md` §5.12), the surfaced `advisory` (or
     `null`), `resolved_count`, and a `bypass` object for any
     no-recipe outcome (`no_frameworks_defined`,
     `navigator_unavailable`, `recipe_not_published`, `user_declined`). This makes resolution **auditable
     and idempotent across resume** and records the degrade-first path rather than leaving it silent.
     The setup commands (`/setup-e2e`, `/setup-visual-regression`) may run before a task folder exists —
     they write the audit only when a `<task_folder>` is in scope, else skip the write with a note (the
     lint still runs).

   Body-as-method adherence stays model-trust (as with SOLID/DRY and the other methodology gates) — this
   step does not verify the recipe was *followed*. What is now deterministic: resolution **ran and was
   recorded**, and an absent recommended declaration is **surfaced**, not silently degraded.

### Framework resolution (the `no_frameworks_defined` branch)

The need IS the trigger: when a phase step needs a recipe but the project has no `**Frameworks:**`, the
**calling command** resolves a framework at the point of need rather than skipping. The method is the
five-step cascade in `references/framework-resolution.md`: the model identifies the framework by reading
the repository (facts from `scripts/framework-evidence.sh`), then `scripts/framework-support.sh <slug>`
reports what the three catalogs carry for it, a remaining gap goes to the user (who may name another
source, including a local path), a gap the user cannot close goes to web research tagged unverified, and
the answer is recorded once in `<task_folder>/_framework.json` and `project_state.md` where every later
phase reads it. Follow that document; do not restate its steps here.

This branch fires **only** when `frameworks == []` (an empty result with `no_frameworks_defined`). It never
touches the `action:ask-user` path (frameworks set, recipe missing, which is step 5, unchanged). It is
idempotent: once a Frameworks line is written, `frameworks != []`, so it cannot re-fire. It is degrade-safe:
on a decline the phase proceeds stack-neutral exactly as before, no regression.

What the calling command owes on top of the cascade:

- **Attended-mode gate.** The cascade asks the user, so it runs ONLY when an answer is possible. In an
  **unattended** run (a `--headless` command, or an autonomous/loop driver), do NOT prompt: record a
  `frameworks_unset` gap marker so the gap is not silently lost, skip the framework-specific step for this
  run, and continue. A later attended `/next` surfaces the marker. Never block an unattended run.
- **Guard codePath.** Read `codePath` via `scripts/project-state-read.sh` (the loader's result JSON does
  **not** carry codePath, so a command that did not already read it must read it here). Identification is a
  read of the codebase, so with **codePath unknown** there is nothing to read: ASK the user (offer
  `/set-code-path`), or skip-with-note for this run. Do not silently gate on a missing codePath.
- **Write the line, or write nothing.** Once the user confirms a framework, write the `**Frameworks:**` line
  into `project_state.md` using the `/upgrade-project` idiom (flush-left, inserted after the last top-block
  metadata field, the exact format `project-state-read.sh` parses). **Never** write a blank or placeholder
  line. A cascade that reaches its end with no framework, and a user who declines, both leave the line absent.
- **Re-resolve once (loop guard).** After the line is written, re-invoke the `process-recipe-loader` skill
  (it re-reads `project_state.md` from disk on every call, so it sees the new line) and use its results to
  proceed with the framework-specific step. Re-resolve **at most once**: if it *still* returns
  `no_frameworks_defined` (the write failed, or its format was not parseable), do **not** loop.
  Skip-with-note and warn.

This behavior lives **only** here and in `references/framework-resolution.md`; the phase commands cite it
rather than re-describing it. The two setup commands (`/setup-e2e`, `/setup-visual-regression`) handle empty
frameworks with their own pre-loader guards and are out of scope for this branch; they point the user to
adopt frameworks first.

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
- `scripts/recipe-declarations-audit.sh`: the zero-model declaration lint run in step 7 (present vs
  absent gate declarations per phase); `references/gate-audit-schema.md` §5.12: the `_recipe-load.json`
  audit it feeds. Step 7 is what makes the otherwise-silent declaration fail-open visible and the
  resolution outcome auditable.
- `references/framework-resolution.md`: the cascade that answers "which framework is this?" when the
  project has none recorded, plus `scripts/framework-evidence.sh` (facts about a codebase, identifies
  nothing) and `scripts/framework-support.sh` (what the catalogs carry for a slug), the two scripts it runs
- `scripts/project-state-read.sh`: emits `frameworks`, `codePath`, `localGuidesPath`, `processRecipes`
