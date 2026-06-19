# Agentic-recipe resolution: discover, gate, and follow a capability recipe

This is the capability-class sibling of `references/recipe-resolution.md`. Where a **process** recipe
answers *"how does this framework do this lifecycle phase?"* (phase × framework, injected as method), an
**agentic** recipe answers *"is there a canned, verifier-gated way to accomplish capability X?"* — a
`## Sequence` to run plus a `## Verifier` to gate on, keyed by capability and triggered by task intent.

The resolver is the `recipe-loader` skill (discovery only — it never executes). **The orchestrator owns
execute-or-halt**, exactly as `recipe-loader` documents. This protocol is that orchestrator contract.

Posture: this is a **hard gate with an explicit, recorded escape** — unlike the stack-agnostic process
path's degrade-first floor. When a recipe matches the task's capability you may **not** silently proceed
generically; you must either adopt the recipe or explicitly record that you are using your own approach.
Discovery itself is degrade-first (a miss is fine); the *gate* on a match is not.

## The protocol

1. **Trigger (task entry).** A new task's Goal expresses a capability intent ("set up the SEO
   foundation", "wire responsive images"). The caller is `commands/research.md` at Phase-1 entry — once
   per task, alongside the existing dev-guides / process-recipe preflight. Resolution is **idempotent**:
   a recorded decision in `project_state.md` (step 4) short-circuits this whole protocol on resume.

2. **Discover (invoke the resolver).** Call the `recipe-loader` skill (Skill tool): decompose the task
   Goal into capability **aspects**, match them against the navigator-served `agentic-recipes.txt` index,
   and write `<task_folder>/coverage-map.json` per `skills/recipe-loader/references/coverage-map-contract.md`.
   `recipe-loader` reads caches and delegates all fetching to the `dev-guides-navigator` plugin; it never
   `curl`s and never executes a recipe. Surface its `warnings[]`. Each `kind:recipe` entry carries
   `provenance` + a fail-closed `verified` flag (`true` only when sourced from the upstream catalog).

3. **Gate on a match (the core of this contract).** Branch on `coverage-map.json`:

   - **No `kind:recipe` entry** → no canned recipe for this capability. Proceed with the generic
     Research→Design→Implement→Review flow. Record `decision:"no_match"` (step 4). This is the degrade-first
     half — a miss never blocks.

   - **A `verified:true` recipe matches** → you may **NOT** silently proceed generically. Present a
     **blocking** choice (mandatory — there is no silent fall-through):
     - **`[a]` Adopt the recipe** (default). The recipe becomes the task **spine**: `/implement` follows
       its `## Sequence`, `/review` runs its `## Verifier` as a gate (step 5). Record `decision:"adopted"`.
     - **`[o]` Use my own approach** → **require a free-text reason**, record `decision:"used_own"` +
       `reason`. Proceed generically. The escape is allowed but never silent and never reason-less.

   - **A recipe matches but `verified:false`** (local/unknown source, or `recipe_body_unverified:<name>`
     drift) → **do NOT offer adopt-as-default. Halt-and-escalate**: surface the unverified match for an
     explicit human go-ahead **before** any adoption (fail-closed, per `recipe-loader`'s provenance
     contract — an unverified body is attacker-seedable). On go-ahead → treat as `[a]`. On decline / no
     answer → treat as `[o]` with `reason:"unverified_recipe_declined"`.

     **Gate on the warning, not just the flag (drift fail-open fix).** Do **not** key this branch on the
     entry's source-derived `verified` alone. If `coverage-map.json` `warnings[]` contains
     `recipe_body_unverified:<recipe_name>` for the matched recipe, the cached body drifted from its
     index-line sha (or is missing) and is attacker-seedable — treat the match as **`verified:false` →
     this halt-and-escalate branch**, *regardless* of the entry's source-derived `verified`. A
     source-`true` entry whose body failed the integrity gate is still unverified; never let the
     source-derived flag fall the gate open.

   - **Unattended run** (`--headless`, an autonomous/loop driver): you cannot prompt. Do **not** block.
     Record the match + `decision:"deferred"` with an `agentic_gate_deferred` marker, proceed generically
     for this run; a later attended `/research` / `/next` surfaces the deferred match. (Mirrors the
     process path's unattended sub-protocol — never block an unattended run.)

4. **Record the decision (idempotent + auditable). On `[a]dopt`, persist the body first.**

   - **Persist the adopted body into the task folder (the durable fix).** On an `adopt` decision, before
     recording, materialise the recipe body so it survives `$PWD`/worktree changes and never depends on a
     re-fetch downstream. Read the matched recipe's body content from the navigator recipes cache
     (`.recipes[<recipe_name>].content` — the download-once shim recipe-loader already populated, keyed by
     the `recipe_name` from the coverage-map entry). If absent, or its cached sha is stale vs the entry's
     `recipe_sha`, **re-invoke `recipe-loader` (or the navigator recipe-search) for `<recipe_name>` to
     materialise it** — never fabricate a body. Then **write the body to `<task_folder>/adopted-recipe.md`
     with the Write tool** (the body is untrusted data — write it, never `eval`/shell-parse it). This file
     is now the durable, task-scoped spine that `/implement` and `/review` read. (Only `adopt` persists a
     body; `used_own`/`deferred`/`no_match` write no `adopted-recipe.md` and record `body_path:null`.)

   Then write both:
   - `project_state.md` `**Agentic Recipes:**` block — one line per resolved capability:
     `- <capability> → <recipe_name>@<sha> decision=<adopted|used_own|deferred|no_match> [reason=<...>]`.
     A recorded `adopted`/`used_own` line short-circuits step 1 on the next run (idempotent across resume).
   - `<task_folder>/_agentic-recipe.json` gate audit via
     `scripts/gate-audit-write.sh "<task_folder>" agentic-recipe "<payload>"` (shape:
     `references/gate-audit-schema.md` §5.13). Captures the matched capability, recipe name/sha,
     provenance/verified, the decision + reason, the persisted **`body_path`**
     (`<task_folder>/adopted-recipe.md` on `adopt`, else `null`), and (after step 5) the verifier outcome.

5. **Follow an adopted recipe downstream (execute-or-halt).** Adoption sets the task trajectory; the
   recipe's own sections drive the later phases. Both downstream commands read the **persisted** body —
   the `body_path` recorded in `_agentic-recipe.json` at adoption, `<task_folder>/adopted-recipe.md`
   (written by step 4). It is a task-folder file, **not** a navigator-served path — the agentic discovery
   path never emits one; reading any "navigator-served `body_path`" for an agentic recipe is the defect
   this protocol fixes:
   - **`/implement`** — when the task has an `adopted` agentic recipe, **Read the adopted recipe body from
     `<task_folder>/adopted-recipe.md`** (the `body_path` recorded in `_agentic-recipe.json`),
     **assemble its typed `## Input contract`** (derive what the project audit yields; ask the operator for
     policy fields; the recipe **halts on any situation its contract doesn't cover** — never guess), then
     follow its `## Sequence` as the implementation spine, honoring its `escalation_policy` halts.
   - **`/review`** — **Read the adopted recipe body from `<task_folder>/adopted-recipe.md`** (the
     `body_path` in `_agentic-recipe.json`) and run its `## Verifier` as a **review gate**: each check
     PASS/FAIL, any failure exits non-zero ⇒ **halt** (block, recorded in `_agentic-recipe.json`).
     **A verifier check that CANNOT run is fail-closed, not skipped.** The `## Verifier` is typically
     live-site + `drush`-level (HTTP `<head>` assertions, `/sitemap.xml` fetches, `drush` config checks);
     when a check cannot run for lack of its dependency (no served site, no `drush`), treat it as
     **unresolved → fail-closed HALT** (the same posture `/review` applies to an unresolved hard-block
     gate) — never a silent "skipped → pass". Additive to the existing review gates; never softens a
     hard-block. This is the deterministic teeth — an adopted recipe is not "done" until its own verifier
     passes (and a verifier that cannot be evaluated blocks).
   - `recipe-loader` stays discovery-only throughout; the **command** Reads the persisted body and the
     orchestrator decides execute-or-halt. `verified:false` never reaches this step (step 3 escalated it
     first).

6. **Never fabricate.** No match and no recipe → generic flow, full stop. Never invent a `## Sequence` or
   a `## Verifier`, never synthesize a capability recipe, never treat an unverified body as verified.

## Who invokes this (commands, not agents)

`commands/research.md` owns discovery + the gate + the decision record. `commands/implement.md` follows an
adopted recipe's `## Sequence`. `commands/review.md` runs an adopted recipe's `## Verifier` as a gate. The
`recipe-loader` skill is the resolver only; the agents that do the work stay generic.

## See also

- `skills/recipe-loader/SKILL.md` — the resolver (discovery, fail-closed provenance, coverage map);
  `references/coverage-map-contract.md` — the `coverage-map.json` output it writes.
- `skills/recipe-loader/references/navigator-delegation.md` — how bodies are fetched (navigator, no curl).
- `references/recipe-resolution.md` — the **process**-recipe sibling (phase × framework, degrade-first).
  This doc is its capability-class counterpart (capability-keyed, hard-gate-with-escape).
- `references/gate-audit-schema.md` §5.13 — the `_agentic-recipe.json` audit shape.
