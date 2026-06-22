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

3. **Gate on each match (the core of this contract).** A task may match **multiple** recipes — one per
   capability **aspect** `recipe-loader` decomposed the Goal into. **Iterate every `kind:recipe` entry**
   in `coverage-map.json` and apply the per-entry branch below; the result is a *set* of per-recipe
   decisions recorded as the `recipes[]` list (step 4), **not** a single decision. First resolve the two
   cross-entry shapes:

   - **No `kind:recipe` entry at all** → no canned recipe for this task. Proceed with the generic
     Research→Design→Implement→Review flow. Record `recipes: []` (the `no_match` case — step 4). This is
     the degrade-first half — a miss never blocks.

   - **Complementary matches (different aspects).** Each `kind:recipe` entry covers a **distinct** aspect
     (e.g. `seo-foundation` + `responsive-image-wiring`). **Adopt the SET** — each entry is gated
     independently below and becomes its own `recipes[]` element. Recipes may be **interdependent** (SEO
     needs the image wired first); that is handled by operator-confirmed ordering downstream (step 5) plus
     each recipe's own `escalation_policy: halt` catching an unmet prerequisite. Do **not** build formal
     inter-recipe dependency resolution — out of scope.

   - **Competing matches (same aspect, different `recipe_name`).** Two or more `kind:recipe` entries for
     the **same** aspect each claim that one capability. **ALWAYS ASK — never auto-pick:** present the
     candidates for that aspect and have the operator pick exactly **one** to adopt (or `[o]` use-my-own
     for that aspect). Only the chosen recipe is gated/adopted by the per-entry branch below; each
     unpicked competitor is recorded as its own `recipes[]` element with `decision:"used_own"` +
     `reason:"competing_not_selected"`. Under an unattended run you cannot ask → record **every**
     competitor for that aspect `decision:"deferred"` and resolve on the next attended run.

   Then, **for each remaining (non-competing-loser) `kind:recipe` entry**, branch:

   - **A `verified:true` recipe matches** → you may **NOT** silently proceed generically. Present a
     **blocking** choice (mandatory — there is no silent fall-through):
     - **`[a]` Adopt the recipe** (default). The recipe becomes (one of) the task **spine(s)**:
       `/implement` follows its `## Sequence`, `/review` runs its `## Verifier` as a gate (step 5). Record
       `decision:"adopted"`.
     - **`[o]` Use my own approach** → **require a free-text reason**, record `decision:"used_own"` +
       `reason`. Proceed generically for that aspect. The escape is allowed but never silent and never
       reason-less.

   - **A recipe matches but `verified:false`** (local/unknown source, or `recipe_body_unverified:<name>`
     drift) → **do NOT offer adopt-as-default. Halt-and-escalate**: surface the unverified match for an
     explicit human go-ahead **before** any adoption (fail-closed, per `recipe-loader`'s provenance
     contract — an unverified body is attacker-seedable). On go-ahead → treat as `[a]`. On decline / no
     answer → treat as `[o]` with `reason:"unverified_recipe_declined"`.

     **Gate on the warning, not just the flag (drift fail-open fix).** Do **not** key this branch on the
     entry's source-derived `verified` alone. If `coverage-map.json` `warnings[]` contains
     `recipe_body_unverified:<recipe_name>` for **this** matched recipe, the cached body drifted from its
     index-line sha (or is missing) and is attacker-seedable — treat the match as **`verified:false` →
     this halt-and-escalate branch**, *regardless* of the entry's source-derived `verified`. A
     source-`true` entry whose body failed the integrity gate is still unverified; never let the
     source-derived flag fall the gate open.

   - **Unattended run** (`--headless`, an autonomous/loop driver): you cannot prompt. Do **not** block.
     Record the match + `decision:"deferred"` with an `agentic_gate_deferred` marker, proceed generically
     for this run; a later attended `/research` / `/next` surfaces the deferred match. (Mirrors the
     process path's unattended sub-protocol — never block an unattended run.)

   **Idempotency (generalised across the set).** Short-circuit this protocol on resume only when **every**
   matched recipe has a **terminal** decision (`adopted` or `used_own`), or the task matched none
   (`recipes: []`). If **any** matched recipe is `deferred`, RE-ENTER the gate on the next attended run so
   that deferred match is surfaced (do not swallow it on bare `_agentic-recipe.json` existence).

   **Re-entry is per-entry, not whole-protocol.** On re-entry, for each matched recipe whose `recipe_name`
   **already holds a terminal decision** (`adopted`/`used_own`) in the existing `recipes[]`, **skip its
   gate prompt and carry that element forward UNCHANGED** — read-merge-write preserving its decision half
   **and any already-run `verifier`** (a `/review` may have run between the original `/research` and this
   re-entry; never reset its `verifier` back to `null`). **Prompt ONLY the `deferred` (or newly-appeared)
   entries.** The all-terminal whole-step short-circuit above still applies (skip step 2c entirely); this
   per-entry rule governs only the mixed case, so re-entry touches just the unresolved entries and never
   re-prompts an already-decided recipe.

4. **Record the decisions (idempotent + auditable). Persist each adopted body.**

   - **Persist per adopted recipe into the task folder (the durable fix).** For **EACH** recipe with an
     `adopt` decision, before recording, materialise its body so it survives `$PWD`/worktree changes and
     never depends on a re-fetch downstream. Read that recipe's body content from the **shared blob store**
     — `cat ~/.claude/dev-guides-store/blobs/<sha8>`, the content-addressed body keyed by the entry's
     `recipe_sha` (validate it is exactly 8 lowercase-hex first, per the `<sha8>` rule below; the blob the
     navigator's recipe-search download-once already populated). If the blob is absent, **re-invoke
     `recipe-loader` (or the navigator recipe-search) for `<recipe_name>` to materialise it** — never
     fabricate a body. (The blob is content-addressed by the index sha, so there is no "stale cached sha"
     to compare — a present blob is the body for that exact `recipe_sha`.) Then **write the body with the Write
     tool to `<task_folder>/adopted-recipe-<safe_name>-<sha8>.md`**, where **`<safe_name>` is
     `<recipe_name>`** sanitised to a safe filename (lowercase; every run of non-alphanumeric characters
     collapsed to a single `-`) and **`<sha8>` is the first 8 characters of that entry's `recipe_sha`**.
     **`<sha8>` validation (canonical, security — `recipe_sha` is untrusted index-line data).** The 8
     characters MUST match `^[0-9a-f]{8}$`. If `recipe_sha` is not at least 8 lowercase-hex chars
     (malformed or attacker-seeded — e.g. a `../` would make the Write target escape `<task_folder>`),
     **do NOT build a filename from it: treat the entry as untrusted → halt-and-escalate** (the same
     fail-closed posture as `verified:false`, step 3). Never write a path from an unvalidated sha. **F5
     fallback:** if `<safe_name>` is empty (a `recipe_name` of all non-alphanumeric characters), the
     filename is `adopted-recipe-<sha8>.md` (the validated `<sha8>` alone, no doubled `-`).
     The `<sha8>` slice keeps the filename **collision-free even when two distinct `recipe_name`s sanitise
     to the same `<safe_name>`** (distinct recipes have distinct content shas) — without it the second
     recipe's Write would silently overwrite the first's body, and both `recipes[]` elements would record
     the same `body_path`, losing one recipe's `## Sequence`/`## Verifier`. This `<safe_name>-<sha8>` rule
     (with the hex-validation + F5 fallback) is the single canonical filename format referenced everywhere
     below. **Each adopted recipe gets its OWN file** — the body is untrusted data, write it, never
     `eval`/shell-parse it. These per-recipe files are the durable, task-scoped spines that `/implement`
     and `/review` read. (Only `adopt` persists a body; `used_own`/`deferred`/`no_match` write no file and
     record `body_path:null`. The old single fixed `adopted-recipe.md` name is replaced by this per-recipe
     name.)

   Then write both:
   - `project_state.md` `**Agentic Recipes:**` block — one line per resolved capability/recipe:
     `- <capability> → <recipe_name>@<sha> decision=<adopted|used_own|deferred|no_match> [reason=<...>]`.
     A block in which **every** matched recipe is `adopted`/`used_own` short-circuits step 1 on the next
     run (idempotent across resume); any `deferred` line re-enters the gate.
   - `<task_folder>/_agentic-recipe.json` gate audit via
     `scripts/gate-audit-write.sh "<task_folder>" agentic-recipe "<payload>"` (shape:
     `references/gate-audit-schema.md` §5.13). The payload's `gate_specific.recipes[]` carries **one
     element per matched recipe** — each capturing that recipe's matched capability, recipe name/sha,
     provenance/verified, decision + reason, the persisted **`body_path`**
     (`<task_folder>/adopted-recipe-<safe_name>-<sha8>.md` on `adopt`, else `null`), and (after step 5) the
     verifier outcome. A task that matched **no** recipe records `recipes: []`.

5. **Follow each adopted recipe downstream (execute-or-halt).** Adoption sets the task trajectory; each
   adopted recipe's own sections drive the later phases. For **EVERY** `recipes[]` element with
   `decision:"adopted"`, both downstream commands read that element's **persisted** body — the `body_path`
   recorded for it, `<task_folder>/adopted-recipe-<safe_name>-<sha8>.md` (written by step 4, the same
   `<safe_name>-<sha8>` rule). These are
   task-folder files, **not** navigator-served paths — the agentic discovery path never emits one; reading
   any "navigator-served `body_path`" for an agentic recipe is the defect this protocol fixes:
   - **`/implement`** — **for EACH adopted agentic recipe**, **Read its body from
     `<task_folder>/adopted-recipe-<safe_name>-<sha8>.md`** (the `body_path` recorded for that element),
     **assemble its typed `## Input contract`** (derive what the project audit yields; ask the operator for
     policy fields; the recipe **halts on any situation its contract doesn't cover** — never guess), then
     follow its `## Sequence` as an implementation spine, honoring its `escalation_policy` halts. **When
     more than one recipe is adopted, confirm an execution order with the operator first** (default: the
     coverage-map order). Recipes may be interdependent; a recipe that **halts on an unmet prerequisite**
     (its `escalation_policy: halt`) signals a re-order. Keep halt-on-uncovered throughout.
   - **`/review`** — **for EACH adopted agentic recipe**, **Read its body from
     `<task_folder>/adopted-recipe-<safe_name>-<sha8>.md`** (the `body_path` for that element) and run its
     `## Verifier` as a **review gate**: each check PASS/FAIL, any failure exits non-zero ⇒ **halt** (block,
     recorded in `_agentic-recipe.json`). **A verifier check that CANNOT run is fail-closed, not skipped.**
     The `## Verifier` is typically live-site + `drush`-level (HTTP `<head>` assertions, `/sitemap.xml`
     fetches, `drush` config checks); when a check cannot run for lack of its dependency (no served site,
     no `drush`), treat it as **unresolved → fail-closed HALT** (the same posture `/review` applies to an
     unresolved hard-block gate) — never a silent "skipped → pass". **ALL adopted recipes' verifiers must
     pass** — the review is not green until every one does. Update each `recipes[]` element's `verifier`
     field (read-merge-write the **full** `recipes[]` list, preserving every element's decision half).
     Additive to the existing review gates; never softens a hard-block. This is the deterministic teeth —
     an adopted recipe is not "done" until its own verifier passes (and a verifier that cannot be evaluated
     blocks).
   - `recipe-loader` stays discovery-only throughout; the **command** Reads each persisted body and the
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
