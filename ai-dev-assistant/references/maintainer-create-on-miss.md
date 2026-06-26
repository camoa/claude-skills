# Maintainer create-on-miss (lifecycle-side wiring)

Why this exists: the navigator's create-on-miss offer
(`dev-guides-navigator/.../references/create-on-miss.md`) is real, but the lifecycle's guide-discovery
path (`/research` Step 3, `/design` Step 2) runs a deterministic script + the `guides-matcher` agent
over the cached catalog — it **never invokes the navigator skill**, so that offer could never surface.
This reference defines the COMMAND-level wiring that makes it surface, plus the propose-only recipe
notices. A command can prompt; a nested skill/agent data-delegation cannot — so the offer lives here.

**Maintainer-only, always.** Every surface below first runs
`${CLAUDE_PLUGIN_ROOT}/scripts/maintainer-mode-detect.sh` (Bash) and parses `.maintainer_mode` /
`.dg_src`. When `maintainer_mode == false` (an ordinary consumer — no dev-guides SOURCE repo by the
4-part signature) **none of these surfaces fire** — behavior is exactly as before. Non-blocking
throughout: a decline or a propose-note never stops the phase.

---

## Surface 1 — GUIDE create-on-miss (an assertive, one-time, author-handoff OFFER)

Fires in `/research` Step 3 and `/design` Step 2, **after** the two-stage preflight has written
`_dev-guides-load.json`.

**Trigger (all must hold):**
1. `maintainer_mode == true`.
2. **Genuine domain miss** — the preflight's `Domain guides matched:` group is empty
   (`catalog_candidates[] ∪ matched_domain_guides[]` is empty, i.e. "— none auto-matched —"). The
   always-present methodology floor (tdd/solid/dry[/library-first]) does **not** count — only a true
   absence of a *domain* guide is a miss (a weak/partial match is not a miss).
3. **Not already settled for this topic** — the **durable** sidecar `<task>/_create-on-miss.json` does
   not already record `decision` ∈ {`dont_ask`, `skipped`, `authored`} for the same `topic`. Asked at
   most once per task per topic. **This sidecar — NOT `_dev-guides-load.json` — is the suppression
   source of truth**, because the offer fires in both `/research` Step 3 and `/design` Step 2 and
   `_dev-guides-load.json` is **overwrite-on-fire** (rewritten every preflight run, so a prior run's
   decision would be lost). The sidecar is read-merge-write: read it first, append/replace this topic's
   entry, write it back — a `/research` decline must still suppress the `/design` re-offer.

**The offer (assertive — name the gap plainly, default `[n]`, never blocks):**

> 🧭 **Maintainer create-on-miss.** No dev-guide topic matched this task's domain
> (**`<topic>`**), and your dev-guides source repo is detected at `<dg_src>`. As the maintainer, you
> can close this gap now so the next task on this topic is covered.
> `/create-guide <topic>` researches a source guide, **pauses for your review**, partitions it into
> `docs/<topic>/`, and opens a PR — it never merges or deploys.
> `[y]` author it now · `[n]` skip (default) · `[d]` don't ask again for `<topic>`

- `<topic>` is a kebab-case slug derived from the task's primary domain (task name / Goal); the user
  refines it in `/create-guide`.
- **Handoff (the command cannot invoke `/create-guide` programmatically — it lives in the dev-guides
  repo's `.claude/commands/`):**
  - If `dg_src == $PWD` → tell the user to run `/create-guide <topic>` (already loaded).
  - Else → tell the user to open a session in `dg_src` (or `cd` there) and run `/create-guide <topic>`.
  Then **STOP** — never replicate an authoring step here.

**Record the outcome durably** in `<task>/_create-on-miss.json` (read-merge-write; survives across
`/research`→`/design` and across re-runs):
`{ "topic": "<topic>", "decision": "authored" | "skipped" | "dont_ask", "dg_src": "<dg_src>" }` appended
to a `guides[]` list keyed by `topic`. A `dont_ask`/`skipped`/`authored` for the same `topic` suppresses
the re-offer (one-time). **Also mirror** the current-run outcome into `_dev-guides-load.json`'s
`create_on_miss` for per-run observability — but that audit is overwrite-on-fire, so it is a snapshot,
never the suppression source. Never blocks.

---

## Surface 2 — AGENTIC-RECIPE gap (PROPOSE-ONLY notice — no offer, no handoff)

Fires in `/research` Step 2c, on the **genuine `no_match`** case only.

**Trigger (all must hold):**
1. `maintainer_mode == true`.
2. `coverage-map.json` `recipes: []` **AND** `recipe_lookup_status == "ok"` (a conclusive miss — NOT
   `index_unavailable`/`navigator_unavailable`, which mean "couldn't check").
3. A load-bearing capability aspect in `coverage-map.json` is uncovered by any recipe.
4. Not already proposed for this task (`_agentic-recipe.json` `gate_specific.recipe_gap_proposed[]`
   does not already list the aspect).

**The notice (informational — NOT a `[y]/[n]`, NO authoring wiring):**

> 💡 **Maintainer note:** no agentic recipe covers **`<aspect>`** in the dev-guides catalog. Worth
> capturing one when you next maintain the catalog. (Proceeding with the generic flow now.)

**This is visibility only.** There is deliberately no create handoff for recipes — proceed exactly as
the genuine `no_match` path always did. Record the surfaced aspect in
`_agentic-recipe.json` `gate_specific.recipe_gap_proposed[]` (additive) so it surfaces once per task.

---

## Surface 3 — PROCESS-RECIPE gap (PROPOSE-ONLY note, appended to the existing ask-user)

Fires from the shared `references/recipe-resolution.md` step 5 (`action:ask-user`, a true miss) — used
by `/design` and every other phase that resolves a process recipe.

**Trigger:** `maintainer_mode == true` AND the step-5 true-miss is reached (frameworks defined, no
recorded source, nothing in the source order).

**Behavior:** keep the existing ask-user (provide a path / research-and-save-locally) unchanged, and
**append** one maintainer note — propose-only, no extra prompt:

> 💡 **Maintainer note:** no published `<phase>/<framework>` recipe exists in the catalog. Whatever you
> resolve here is local (`verified:false`); consider authoring a catalog recipe later. (Not done
> automatically.)

No authoring handoff, no auto-create. The existing local/research resolution proceeds unchanged.

---

## Hard rules (all surfaces)

- **Detect → offer/propose → (guides only) hand off. Never author, commit, push, or deploy** from the
  lifecycle. Guides hand off to `/create-guide`; recipes only propose.
- **Consumers never see any of this** (`maintainer_mode == false`).
- **Never blocks.** Every surface is a soft-nudge; declining or ignoring proceeds with the phase.
- **One-time.** Each surface records its outcome in the phase audit so a re-run does not re-nag the
  same topic/aspect.
- **Misses only, not refreshes.** These fire on a true absence, never to update an existing guide/recipe.
