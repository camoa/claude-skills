# Work-Order Contract — `schema_version: "1.0"`

> **FREEZE STATUS — ✅ FROZEN `schema_version: "1.0"`** (all 4 freeze-pending items cleared
> 2026-06-08). (1) `bd create` **VERIFIED** against Beads primary source (Go source on
> `steveyegge/beads` HEAD) · (2) the `verified`-vs-warnings fix · (3) the reserve-ahead additions
> (`critique_ref` / `coverage_override` / `needs_rework`) · (4) the M-5 ready-queue decision — all
> closed. The **markdown** fields (id grammar, kind, status enum, edges, quality-brain superset) are
> **frozen** and are **markdown-canonical** — they do **NOT** depend on Beads' internals. A bead
> projects FROM them via the verified MAP below, so the freeze clears with **zero markdown-field
> changes**. Do **not** redesign these fields; the three sibling slices (`gate_integration` ②,
> `lifecycle_controls` ③, `safety_governor` ④) build against this exact surface in parallel.

This is **the** artifact the work_order_pipeline owns end-to-end and the three sibling slices depend
on. It is a frozen interface, not an implementation note — the DIP abstraction every sibling inverts
its dependency onto. The compiler (`work-order-compiler` skill + `wo-compile.sh` kernel) **produces**
work-orders to this contract; the build-and-collect atom (`work-order-builder` skill) **consumes**
the dispatch subset; ②/③/④ consume their seam slices (the ownership table below).

## Location

`<ddf_task_folder>/work-orders/wo-NN-<slug>.md` — beside `coverage-map.json` and `_review.json` (the
established "artifact on disk, not transcript echo" pattern). `<ddf_task_folder>` is the **leaf** DDF
task `/design` ran on (in epic → sub_epic → subtask nesting, the subtask that owns the work-orders).

A work-order is **one file per independently-gate-verifiable AC/feature**, each projectable 1:1 to a
Beads bead via the MAP below. Beads is **not built here** — only designed-projectable.

---

## Frontmatter (the machine contract)

The frozen field block. Every field's semantics are fixed; **inline comments are normative**.

```yaml
---
# ── bead-PROJECTABLE scheduling subset — structural reuse + a documented map (NOT zero-translation, H1) ──
id: local:<ddf_task>#wo-NN          # grammar: <parent-task-id>#wo-NN — the "#wo-NN" fragment is the work-order
                                    # discriminator. MARKDOWN-canonical stable id. Projects via the id MAP below.
kind: work-order                    # a documented 5th value, OUTSIDE the DDF task enum (epic/sub_epic/subtask/flat);
                                    # deliberate. Projects via the kind MAP.
schema_version: "1.0"
title: <imperative one-liner>
parent: local:<ddf_task>            # field-for-field reuse of DDF/bead `parent` (renamed from research's parent_task, H1).
status: ready | blocked | in_progress | done | needs_rework   # WO-native lifecycle (VERIFIED 2026-06-08: NOT
                                    # bead-aligned — Beads has no ready/done/needs_rework; the MAP translates), distinct
                                    # from the DDF task enum (draft/in_progress/blocked/completed). needs_rework = built
                                    # but a verdict requires rework (M1). ALL status transitions are owned by ③ (H-3
                                    # two-repo boundary) — the atom is read-only here. MARKDOWN-canonical; bead status
                                    # projects FROM this, never reverse (§6).
blocks:     [local:<ddf_task>#wo-NN, ...]   # markdown-canonical structural edge set; projects to Beads DEPENDENCY
                                    #   edges, NOT field-for-field (see the MAP). id VALUES remap via external_ids.
blocked_by: [local:<ddf_task>#wo-NN, ...]   # markdown-canonical structural edge set; projects to Beads DEPENDENCY
                                    #   edges, NOT field-for-field (see the MAP). The DAG acyclicity invariant (H3)
                                    #   holds over THIS set. ③ derives dispatch readiness via a READY-QUEUE (a WO is
                                    #   ready when all blocked_by are `done`, à la `bd ready` — M-5); no topo order is
                                    #   persisted. Acyclicity is what guarantees the ready-queue always terminates.
children: null                      # work-orders are leaves; reserved for shape-parity with DDF/bead `children`.
external_ids: {}                    # reserved back-channel (the established reserve-ahead pattern). At projection,
                                    #   L2 records the minted bead id here: external_ids: { beads: "<bd-id>" }.

# ── coverage / grounding — the MARKDOWN-ONLY "quality brain" superset (a bead NEVER sees these) ──
requirements: [AUTH-01, AUTH-02]    # GSD [CATEGORY]-NN IDs this WO satisfies (traceability).
coverage_ref: ../coverage-map.json  # the per-DDF-task recipe_loader map this slice was projected from.
coverage_aspects: [<aspect>, ...]   # the subset of the map's task_aspects this WO owns. (May be empty — see verified.)
verified: true | false              # = AND(covered-entries.verified) AND (NO poisoning warning attributable to this WO).
                                    #   Poison set = recipe_body_unverified | slug_not_in_catalog (C-1: a slug a recipe
                                    #   names but absent from the catalog surfaces as a TOP-LEVEL warning with NO entry —
                                    #   AND([true]) would be fail-OPEN). EMPTY covered set ⇒ false (C1) — never vacuous-true.
                                    #   false ⇒ HALT dispatch (fail-closed) UNLESS coverage_override is set (⇒ ③ no-auto-merge).
                                    #   SEAM: coverage-map warnings[] carry NO aspect/ref key today ⇒ a poison warning is
                                    #   treated GLOBAL (every WO in the task ⇒ false) — fail-closed but coarse; precision is
                                    #   a recipe_loader re-open to key warnings by aspect/ref (cross-task dep).
coverage_status: covered | uncovered | poisoned   # precedence poisoned > uncovered > covered. covered = ≥1 clean
                                    #   entry; uncovered = only a task-level uncovered_aspect (guides-floor); poisoned = a
                                    #   poison warning applies. verified:true ONLY when covered. uncovered/poisoned ⇒ false.
lockfile:                           # transitive closure by SHA (§10.5 / §14.6) — the §14.5 hard execution gate.
                                    #   SHA SOURCE = the navigator cache's per-line `(sha:…)` (M-3) — NOT a re-fetch, NOT
                                    #   the coverage-map entries (they carry no sha). `excerpt_sha` pins the INLINED slice so
                                    #   recompile-on-drift (N2) is mechanical; verified at COMPILE (recipe-loader step-5 gate)
                                    #   BEFORE any excerpt is inlined.
  - { ref: <recipe>@<ver>, sha: <body-sha>, excerpt_sha: <sha256-of-inlined-excerpt>, kind: recipe }
  - { ref: <guide-slug>,   sha: <body-sha>, excerpt_sha: <sha256-of-inlined-excerpt>, kind: guide }
  - { ref: <play-slug>,    sha: <body-sha>, excerpt_sha: <sha256-of-inlined-excerpt>, kind: play }
drift_guard:                        # the H2 mechanical-sufficiency RECEIPT the compiler emits (a necessary, not
  symbols_resolved: true | false | skipped   #   sufficient, floor). skipped ⇒ no codePath at compile time (N3) ⇒ soft-halt.
  acceptance_runnable: true | false # every `requirement` has a runnable (observable) acceptance, not "looks right".
collapsed_scc: false                # true ⇒ this WO merged a strongly-connected component of units (M-2). ALWAYS
                                    #   flagged for human confirm; a collapse beyond the bound HALTS at compile (no mega-WO).

# ── sibling SEAM fields — carried here, behavior built by the named sibling (frozen so they start in parallel) ──
gate_floor: [tdd, solid, dry, security, guides]   # ② reads. Set at compile = base set ∪ recipe-declared gates.
autonomy_safe: true | false         # INFORMATIONAL ONLY (§17, 2026-06-11) — NO LONGER a dispatch gate.
                                    #   Autonomy is mode-keyed RECIPE BEHAVIOR (stop-and-ask@L0 / infer-and-flag@L1-L2),
                                    #   enforced in recipe authoring, not a per-WO flag. The field may still record whether
                                    #   matched recipes declared an autonomy-safe interaction contract, but it never blocks
                                    #   dispatch. (Was: defaulted false, gated dispatch on every matched recipe declaring it.)
review_ref:   <task>/work-orders/wo-NN._review.json   | null   # RESERVED (M1): per-WO review location ② BUILDS
                                    #   (shipped /review --headless writes a TASK-level audit; ② adds the per-WO file — L-3).
critique_ref: <task>/work-orders/wo-NN._critique.json | null   # RESERVED (M1): ②'s §16.2 per-job critique verdict
                                    #   location (structural, not derivable — same logic as review_ref).
risk_tier: low | medium | high | null   # RESERVED (M1): change-impact tier for ②'s risk-scaled critique (§16.2).
                                    #   ERRATUM (within 1.0): the compiler does NOT populate this; ② derives the
                                    #   OPERATIVE tier from the realized post-build diff in its _critique.json sidecar.
size_estimate: <int> | null         # RESERVED (M1): ④ budget estimate.
coverage_override: { reason: <str>, by: <str>, at: <iso8601> } | null   # RESERVED (M1): ③/human recorded override to
                                    #   dispatch a verified:false WO. Honored like a recorded bypass ⇒ ③ MUST NOT auto-merge.
                                    #   Default null. Resolves the "proceed on verified:false" path the prose promised but the
                                    #   hard precondition forbade (the dispatch gate now checks verified OR override).

# ── provenance ──
compiled_from:
  architecture: { file: architecture.md, sha: <sha256> }
  alignment:    { file: alignment.md,    sha: <sha256> }
  research:     { file: research.md,     sha: <sha256> }
compiled_at: <iso8601>
---
```

### Field semantics, grouped

**Scheduling subset (bead-projectable).** `id` is markdown-canonical and alien to Beads' id space —
it stays markdown-only and bridges through `external_ref` / `external_ids.beads` (the MAP). `kind:
work-order` is a documented 5th value outside the DDF task enum. `parent` reuses DDF/bead `parent`
field-for-field. `status` is **WO-native** (`ready|blocked|in_progress|done|needs_rework`) and
**every** transition is owned by ③ — the compiler is born `ready` or `blocked`, the atom never
writes it. `blocks`/`blocked_by` are the structural edge set the H3 DAG invariant holds over; ③
sequences via a **ready-queue** (no persisted topo order). `children: null` (work-orders are leaves).
`external_ids: {}` is the reserve-ahead back-channel where L2 stores the minted bead id.

**Quality-brain superset (markdown-only; a bead never sees these).** `requirements` (GSD
`[CATEGORY]-NN` IDs) · `coverage_ref` / `coverage_aspects` (the recipe_loader slice this WO owns) ·
`verified` (the fail-closed verdict, below) · `coverage_status` (`poisoned > uncovered > covered`) ·
`lockfile` (the transitive SHA closure — the §14.5 hard execution gate; **the dispatch gate refuses
any WO with a null-sha `lockfile[]` entry**) · `drift_guard` (`symbols_resolved` +
`acceptance_runnable` — the H2 mechanical-sufficiency receipt; **the dispatch gate requires
`symbols_resolved == true` AND `acceptance_runnable == true`**) · `collapsed_scc` (human-confirm flag
for an SCC merge).

**Seam fields (carried here, behavior built by the named sibling).** Frozen so the siblings start in
parallel. `gate_floor` + `autonomy_safe` are **produced by the compiler**; `review_ref` /
`critique_ref` / `risk_tier` / `size_estimate` / `coverage_override` are **reserved** (M1) and
populated/consumed by ②/③/④. See the ownership table.

**Provenance.** `compiled_from` pins the SHA of each `/design` artifact; `compiled_at` is an ISO-8601
string (kept a string, never a YAML timestamp object — the kernel's loader strips the timestamp
resolver so it round-trips as text).

### The fail-closed `verified` rule (C1 + C-1) — load-bearing, two boundaries

```
verified = AND(covered-entries.verified) AND no-poison(this WO)
```

- **EMPTY covered set ⇒ `false`** (C1). The empty-set special case is checked **before** the AND, so
  `AND([]) == true` can never fail-open an ungrounded build dispatched as verified.
- **Poison ⇒ `false`** (C-1). Poison set = the coverage-map `warnings[]` matching
  `recipe_body_unverified` / `slug_not_in_catalog`. Those warnings carry **no aspect key** today, so a
  poison warning is treated **GLOBAL** — any such warning ⇒ every WO in the task `verified:false`
  (fail-closed but coarse; the precision fix is a flagged cross-task recipe_loader re-open to key
  warnings by `aspect`/`ref`).
- `coverage_status` precedence is `poisoned > uncovered > covered`; `verified:true` is legal **only**
  when `covered`.

This rule is computed by `wo-compile.sh coverage-slice` at **compile** time and re-enforced by
`wo-compile.sh assert-dispatchable` at **dispatch** time — never re-derived in prose.

### The dispatch gate (`assert-dispatchable`) — what makes a WO dispatchable

> **Dispatch gate strengthened 2026-06-08** to mechanically enforce lockfile-pinned + drift-resolved
> grounding: the `lockfile` + `drift_guard` fields are now **READ by the kernel gate**, not
> compile-time prose only. **Schema fields unchanged — a strengthening within `schema_version: "1.0"`.**

`wo-compile.sh assert-dispatchable <wo-file>` (the tested kernel — H-1, not prose) exits **0 IFF**:

```
grounding_clean = verified == true AND coverage_status == "covered"
                  AND (NO lockfile[] entry has sha == null)      # §14.5: an unpinnable ref blocks dispatch
                  AND drift_guard.symbols_resolved == true        # H2: "skipped" AND false BOTH fail
                  AND drift_guard.acceptance_runnable == true     # H2
dispatchable    = (grounding_clean OR a valid coverage_override {reason, by, at})
                  AND status == "ready"           # §17: autonomy_safe is NO LONGER a gate
override_used   = override_valid AND NOT grounding_clean
```

A valid `coverage_override` bypasses **all** grounding (coverage + lockfile + drift) — but **never**
`status`. Else non-zero. It always prints
`{"dispatchable":bool,"reason":<why>,"override_used":bool}`. `override_used` is true when the override
(not clean grounding) carried the dispatch ⇒ **③ withholds auto-merge** (a recorded bypass, like a
`--skip-<gate>`). Missing `verified` reads fail-closed as `false`. The `reason` is the
first failing clause in IFF order: `verified_false | poisoned | uncovered | unpinned_ref |
drift_skipped | drift_unresolved | acceptance_not_runnable` → `status_not_ready:<status>` →
`dispatchable`. (§17, 2026-06-11: `autonomy_safe` is no longer a dispatch gate — autonomy is mode-keyed
recipe behavior; the `autonomy_unsafe` reason is retired.)

---

## Body (all INLINED — self-containment IS the contract)

A work-order body is a **fully self-contained brief**: a fresh subagent with no parent narrative and
no slash-command reach must be able to build it from the body alone. Every section is **inlined**, not
referenced (a referencing-not-inlining work-order builds **blind → hallucinates → ships below-floor
code** — the dangerous failure, unattended). Sections, in order:

| Section | Contents |
|---|---|
| `## Goal` | A falsifiable **Current / Target / Acceptance** triplet (GSD §15). Acceptance is a **runnable observation**, never "looks right". |
| `## Scope delta` | OpenSpec `ADDED / MODIFIED / REMOVED` (§10.6). |
| `## Build context` | The architecture **slice** for this unit — responsibility / interface / data-flow / paths, **pasted not referenced** — plus bounding **Non-goals** and the load-bearing research facts ("never assume a method exists"). |
| `## Grounding` | The coverage-slice table **+ the load-bearing guide/recipe EXCERPTS the build needs, inlined at compile time** (H2 resolution; full bodies stay lazy / provenance-only in the `lockfile`). |
| `## Files to touch` | The concrete paths the build edits. |
| `## Requirements` | Each requirement → phase → status (traceability). |
| `## Dependencies` | The `blocked_by` work-orders whose output this build assumes is already in the tree. |
| `## Done =` | A checklist — **one observable check per requirement**. |

**Inline-vs-lazy (H2):** the compiler runs in an *attended-or-orchestrated* context with a degrade
path and a warm cache, so it **inlines the load-bearing excerpt at compile time** and lockfile-
references full bodies for provenance only — moving fetch-reach risk **off** the fresh builder's
critical path (a builder has no degrade contract for a mid-build cache miss).

---

## The work-order ↔ bead MAP (H1 — ✅ VERIFIED 2026-06-08 vs Beads primary source)

Projection is **markdown → bead always** (§6; a bead never writes back except its minted id into
`external_ids.beads`). It is **NOT** uniform "structural reuse": the id is minted + bridged, the
status + kind are rewritten to Beads built-ins, and the edges project to Beads' **dependency-edge**
model — only `parent` (DDF field) + `in_progress` map cleanly.

**`bd create` reality (verified, Beads HEAD 2026-06-08):** Beads **mints** the id (content-hash
`prefix-{6-8hex}[.n.n]`); the status enum is `open | in_progress | blocked | deferred | closed |
pinned | hooked` (**no `ready`/`done`/`needs_rework`** — the WO enum is WO-native, this MAP
translates); `issue_type` has **no** `work-order` (→ `task`); `blocks`/`blocked_by` are **dependency
edges** (`bd create --deps` / `bd dep add`), **NOT** columns; `--id` and `--parent` are mutually
exclusive (compatible — we mint, so `--parent` stays free).

| Concern | Work-order field | Bead projection (✅ VERIFIED vs `bd create`/`bd update`, Beads HEAD 2026-06-08) |
|---|---|---|
| **edges** | `blocks` / `blocked_by` / `children` | NOT Beads columns → **dependency edges**: at create via `bd create --deps "blocks:<bead-id>"` (blocks) / `--deps "<bead-id>"` (blocked-by, default direction); `children` = a `parent-child` edge. Post-create edge changes use `bd dep add/remove` (`bd update` does **not** mutate edges). id **values** remap through the minted ids. *(Earlier "field-for-field reuse" was wrong — corrected.)* |
| **id** | `id: local:<task>#wo-NN` | Beads **mints** the id (content-hash `prefix-{6-8hex}[.n.n]`); our `:`/`#` grammar is alien to Beads' id space ⇒ stays **markdown-only**. Bridge: WO id → Beads `external_ref`; minted `bd-…` id → WO `external_ids.beads` (N4 confirmed, bidirectional). Do **not** force `--id` (mutually exclusive with `--parent`; minting keeps `--parent` free). |
| **kind** | `kind: work-order` | → Beads `issue_type: task` (no `work-order` type; custom types UNVERIFIED ⇒ map to the built-in `task`). |
| **status** | `ready` / `blocked` / `in_progress` / `done` / `needs_rework` (WO-native) | `ready`→`open` (Beads has no `ready` — it is the computed `bd ready` query) · `blocked`→`blocked` · `in_progress`→`in_progress` · `done`→`closed` · `needs_rework`→ reopened `open` (no native equivalent). No `--status` at create (born `open`) ⇒ a non-`ready` WO = create-then-`bd update --status`. |
| **quality brain** | `requirements` / `coverage_*` / `verified` / `lockfile` / `drift_guard` / `collapsed_scc` / `gate_floor` / `autonomy_safe` / `review_ref` / `critique_ref` / `risk_tier` / `size_estimate` / `coverage_override` / body | **never projected** — markdown-only; gate verdicts never live in Beads (§6). |

**L2 importer forward-note (not built here):** the projection above is performed by the L2 Beads
importer when/if Beads is wired in. The WO file stays the source of truth; the bead is a downstream
mirror that records only its minted id back into `external_ids.beads`. Detail:
`bead-projection-map.md`.

---

## Seam-field ownership (who reads what — the freeze unblocks all three siblings in parallel)

| Field(s) | Produced by | Consumed by |
|---|---|---|
| `blocked_by` / `blocks` (DAG; ready-queue source) | compiler (here) | ③ ready-queue sequencing / no-auto-merge |
| `status` (ALL transitions) | ③ (H-3 two-repo) | `assert-dispatchable` reads (here); ② reads |
| `verified` / `coverage_status` (fail-closed) | compiler (here) | `assert-dispatchable` (kernel, here) + ③ |
| `coverage_override` | ③ / human | `assert-dispatchable` (here) ⇒ ③ no-auto-merge |
| `autonomy_safe` | compiler (here) | informational only (§17) — NOT a dispatch gate |
| `gate_floor` | compiler (here) | ② reads (tiering + which gates) |
| `review_ref` / `critique_ref` / `risk_tier` | reserved — compiler emits null; ② populates (sidecars + realized tier) | ② §16.2 critique |
| `size_estimate` / WO count | compiler (here) | ④ budget governor |

**OCP note:** the reserved fields (`review_ref` / `risk_tier` / `size_estimate` / `critique_ref` /
`coverage_override`) absorb new sibling needs **additively**, the way `external_ids: {}` reserves
ahead — no re-freeze. Each sibling reads **only its slice** (ISP); ② never depends on ④'s
`size_estimate`.

---

## The build-and-collect handle (the runtime seam ③/② consume)

The build-and-collect atom returns this **frozen** handle to ③ — built by `wo-compile.sh
collect-handle` purely from `git`/disk (no transcript echo, M-6). It is a seam like the frontmatter
fields: ③ reads it to drive sequencing + status; ② reads the tree it points at.

```json
{ "wo_id": "local:<task>#wo-NN", "dispatched": true|false, "override_used": true|false,
  "halt_reason": null | "verified_false" | "poisoned" | "uncovered" | "unpinned_ref"
               | "drift_skipped" | "drift_unresolved" | "acceptance_not_runnable"
               | "sequencing_error" | "frontmatter_unreadable" | "spawn_failed",   # §17: "autonomy_unsafe" retired
  "tree": "<worktree path>", "checkpoint_before": "<sha>", "checkpoint_after": "<sha>|null",
  "produced_changes": true|false,
  "artifacts": ["<path>", "..."], "build_returned": true|false }
```

- **No `verdict`** (②'s), **no `next`** (③'s), **no `status`** (③ owns every write — H-3). The
  omissions are the boundary made concrete.
- `halt_reason` is drawn **only** from the frozen enum above — the value ③ branches on. The atom
  **maps** the kernel's `assert-dispatchable` reason onto it (`status_not_ready:*` →
  `sequencing_error`; `frontmatter_unreadable:*` → `frontmatter_unreadable`; the grounding/autonomy
  reasons pass through) and **never** passes a raw kernel string into the handle.
- `produced_changes` is git-derived (`checkpoint_after == null ⟺ produced_changes == false`), so ③
  distinguishes a real build from a no-op/failed one without reading the transcript (M-6).

(The `halt_reason` enum was **widened 2026-06-08** alongside the dispatch-gate strengthening — the new
`unpinned_ref` / `drift_skipped` / `drift_unresolved` / `acceptance_not_runnable` grounding reasons
plus the mapped `sequencing_error` / `frontmatter_unreadable`; additive within `schema_version: "1.0"`.)

---

## Honest scope boundary (what this contract does NOT guarantee)

- `autonomy_safe` is **informational only** (§17, 2026-06-11) — it does **not** gate dispatch. Autonomy
  is mode-keyed recipe behavior (stop-and-ask@L0 / infer-and-flag@L1-L2). It never meant the build won't
  hallucinate — builder-output trust is caught by ②'s gates + the §16.2 per-job critique + human-merge.
- The **mechanical** injection boundary (transcript → shell/JSON/path) is structurally minimized on
  the load-bearing seam (the handle is built from git/disk, never the transcript). The **semantic**
  injection boundary (a judge that must READ the transcript can be steered) is **not closeable here**
  — ②'s independent fresh-context critique **narrows it (it does not close it): the judged diff is
  itself attacker-authored, so the critic stays a semantic-injection target — a probabilistic
  mitigation, not a structural close.** **Unattended operation on high-`risk_tier` / security-touching
  work-orders is below the §14.5/§16.2 bar until ② ships.**
- See `injection-boundary.md` for the mechanical-vs-semantic split in full.
