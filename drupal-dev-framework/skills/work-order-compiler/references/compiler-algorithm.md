# Compiler Algorithm — the step-by-step C1 keeps lean by referencing

The exact walk of Data Flow A: the JSON payloads you assemble for each `wo-compile.sh` sub-command,
how to read each verdict, and how to handle every halt. `[model]` = your judgment; `[kernel]` =
delegated to the tested script. The frozen field shapes are in `work-order-contract.md`; do not
restate the schema, apply it.

Throughout: assemble **every** stdin payload with `jq` (so untrusted values are escaped), read
**every** verdict with `jq`, and **Write** output files with the Write tool. Never `echo`/heredoc a
work-order, never `eval` artifact content. Invoke the kernel as:

```bash
KERNEL="${CLAUDE_PLUGIN_ROOT}/scripts/wo-compile.sh"
```

## Inputs (read in full — Type-B reading, no grep-first)

| Artifact | Why |
|---|---|
| `<task>/architecture.md` | Components table → units; Data Flow → edges; the slice to inline. |
| `<task>/alignment.md` | Success criteria → falsifiable acceptances. |
| `<task>/research.md` | Load-bearing facts ("never assume a method exists") to inline. |
| `<task>/coverage-map.json` | `recipe_loader` output — sliced per unit for `verified`. |
| project `codePath` | drift-guard resolves cited paths against it. Read via `project-state-reader`; never hardcode. |

Resolve `<task>` and `codePath` before step 1. If `codePath` is null, expect step 8 to return
`skipped` ⇒ soft-halt (re-run post-`/worktree`).

---

## Step 1 — Decompose → candidate units `[model]`

Read `architecture.md` fully. Each Components-table row seeds a candidate unit; **split** a row that
carries two independently-gate-verifiable ACs, **merge** rows that share one AC. Granularity target:
**one unit = one independently-gate-verifiable AC/feature a single subagent can build with no
sub-delegation.** A unit that would need to fan out to sub-agents is a compile-time **over-size halt**
(the builder is a LEAF — depth-2 spawn is unsupported): split it, or escalate.

Give each candidate a working id (`wo-01`, `wo-02`, …). The final WO id is `local:<task>#wo-NN`.

## Step 2 — Acceptance + requirement IDs `[model]`

From `alignment.md` Success criteria, attach each unit's **Current / Target / Acceptance** triplet.
Acceptance must be a **runnable observation** (a command, a gate verdict, an asserted output) — never
"looks right". Assign `[CATEGORY]-NN` requirement IDs (e.g. `AUTH-01`); each maps requirement → phase
→ status. Record, per requirement, whether its acceptance is runnable — step 8 asserts it.

## Step 3 — Derive dependency edges `[model]`

From `architecture.md`'s **structured Data Flow** (the arrows/consumes relationships, not free
prose): *unit B consumes unit A's output* ⇒ **`wo-B blocked_by wo-A`**. Populate each unit's
`blocked_by` (and the mirror `blocks`). Only encode edges the Data Flow actually states — a missed
real edge is N1 (the cycle detector only sees edges you encoded; residual risk → ② critique).

## Step 4 — Build the graph `[kernel]`

Assemble the units payload with `jq` (working ids; `ac` is the unit's acceptance, any JSON the
kernel can hash):

```bash
UNITS=$(jq -n '{units: [
  {id:"wo-01", ac:"AUTH-01", blocked_by:[],        blocks:["wo-02"]},
  {id:"wo-02", ac:"AUTH-02", blocked_by:["wo-01"], blocks:[]}
]}')                                        # build this from your unit list via --argjson, never by hand
GRAPH=$(printf '%s' "$UNITS" | bash "$KERNEL" build-graph); RC=$?
```

**On `RC != 0`** (exit 1): read `halt_reason` and **halt-and-escalate** — do not emit work-orders.

| `halt_reason` prefix | Meaning | Your action |
|---|---|---|
| `self_dependency:<id>` | a unit blocks itself | fix the edge in step 3 |
| `uncollapsible_cycle:size_N_exceeds_bound` | an SCC of > 2 units | the units are too entangled — re-decompose (step 1) |
| `uncollapsible_cycle:spans_N_acs` | a 2-cycle across distinct ACs | split the shared concern so the cycle is within one AC, or escalate |
| `duplicate_unit_id:<id>` | two units share an id | fix step 1 ids |
| `malformed_edge_field` / `malformed_units_field` | a non-list edge/units field | a payload bug — rebuild via `jq` |

**On `RC == 0`**, the output `units[]` is the **condensation** (input-appearance order, **not** a
topo sort). Each entry: `{id:<rep>, members:[…], collapsed_scc:bool, ac, blocked_by:[<rep>,…]}`.

```bash
echo "$GRAPH" | jq -r '.collapsed'                 # how many SCCs collapsed
echo "$GRAPH" | jq -c '.units[] | select(.collapsed_scc)'   # each needs human confirm (step 10)
```

Derive `blocks` as the **inverse** of the collapsed `blocked_by` over the final unit set (for each
unit U, for each V in `U.blocked_by`, append U to `V.blocks`) so both arrays stay consistent
post-collapse. Then **translate every id to the `local:<task>#wo-NN` grammar — the unit's own `id`
AND every value inside its `blocked_by` / `blocks` arrays** (the kernel emits working ids like
`wo-01`; the frontmatter stores the full grammar). A stale working id left inside an edge array would
break ③'s ready-queue resolution.

## Step 5 — Map units → coverage aspects + the minimal slice `[model]`

For each surviving unit, judge which of `coverage-map.json`'s `task_aspects` it owns (semantic match —
the unit's responsibility against the aspect names). Then decide the **minimal self-contained slice**
of architecture + grounding to inline: the *slice this unit needs*, not the whole task, not bare
references. This is the hard judgment of the task — a referencing-not-inlining work-order builds
blind, hallucinates, and ships below-floor code, unattended.

## Step 6 — Coverage slice + fail-closed `verified` `[kernel]`

Per unit, pass the **whole** coverage-map plus the unit's aspects:

```bash
CMAP=$(cat "$TASK/coverage-map.json")
ASPECTS=$(jq -n --argjson a "$UNIT_ASPECTS" '$a')         # a JSON array of strings, built via jq
SLICE=$(jq -n --argjson m "$CMAP" --argjson a "$ASPECTS" '{coverage_map:$m, aspects:$a}' \
        | bash "$KERNEL" coverage-slice)                  # always exit 0
VERIFIED=$(echo "$SLICE" | jq -r '.verified')             # true|false — CARRY VERBATIM
CSTATUS=$(echo "$SLICE" | jq -r '.coverage_status')       # covered|uncovered|poisoned — CARRY VERBATIM
```

`verified = AND(covered) AND no-poison`; **empty covered set ⇒ false**; **poison ⇒ false** (global,
fail-closed-but-coarse). Put `verified` / `coverage_status` straight into the WO frontmatter; use the
returned `covered_entries` to build the `## Grounding` body table (**`covered_entries` is NOT a
frontmatter field** — it lives only in the body). **Never re-judge `verified` / `coverage_status`** —
the empty-set special case and the poison AND are the kernel's, and re-deriving them in prose is the
safety bug the kernel prevents.

### Step 6b — `autonomy_safe` + `gate_floor` `[kernel+model]`

- `autonomy_safe` **defaults `false`**. Set `true` **only** if **every** matched recipe for the unit
  explicitly declares the machine-readable autonomy-safe frontmatter field (a cross-task
  recipe-catalog dependency — never inferred from prose). When in doubt, `false` (fail-closed).
- `gate_floor` = base `[tdd, solid, dry, security, guides]` ∪ any recipe-declared gates. Build the
  union with `jq` (`unique`).

## Step 7 — Assemble the body `[model]`

Inline every section from the contract's body list. **Decide the candidate excerpts** for `##
Grounding` here (the load-bearing guide/recipe slices) — but do not finalize them until step 9
confirms each is pinnable (a null-sha ref's **excerpt** is pulled back out of the body, though its
**lockfile entry stays**). Keep full bodies out of the body; they live as provenance in the lockfile.

## Step 8 — Drift-guard gate `[kernel]`

Assemble the citation payload. `cited_paths` = every path the body's `## Files to touch` /
`## Build context` names; `cited_symbols` = `{path, pattern}` pairs the body asserts exist
(`pattern` is a **fixed string**, matched with `grep -F`); `requirements` = `{id, runnable}` per
requirement from step 2.

```bash
GUARD=$(jq -n --arg cp "$CODE_PATH" \
  --argjson paths "$CITED_PATHS" --argjson syms "$CITED_SYMBOLS" --argjson reqs "$REQS" \
  '{code_path:$cp, cited_paths:$paths, cited_symbols:$syms, requirements:$reqs}' \
  | bash "$KERNEL" drift-guard)                            # always exit 0
SR=$(echo "$GUARD" | jq -r '.drift_guard.symbols_resolved')      # true|false|"skipped"
AR=$(echo "$GUARD" | jq -r '.drift_guard.acceptance_runnable')   # true|false
```

| Result | Meaning | Action |
|---|---|---|
| `symbols_resolved: "skipped"` | no/absent codePath (N3) | **soft-halt-and-escalate** — do not emit dispatchable WOs; re-run post-`/worktree` |
| `symbols_resolved: false` | a cited path missing / symbol unresolved (`missing_paths`, `unresolved_symbols`) | fix the citation or the architecture slice, re-run |
| `acceptance_runnable: false` | a requirement lacks a runnable acceptance (or zero requirements) | rewrite the acceptance as an observable check (step 2) |
| both true | the mechanical floor is met (necessary, not sufficient — N1 residual → ② critique) | proceed |

Record the receipt into the WO `drift_guard` field verbatim. **This receipt is now read by the
dispatch gate:** a `skipped` (`drift_skipped`), a `false` (`drift_unresolved`), or a non-runnable
acceptance (`acceptance_not_runnable`) each make the WO **non-dispatchable** in the kernel — so even an
emitted-anyway WO cannot build blind. Recording it honestly is what arms the gate.

## Step 9 — Lockfile, provenance, emit `[kernel]`

Compute the navigator cache path (cwd-derived, same contract recipe-loader reads — never glob to
another project's cache):

```bash
DASHED=$(printf '%s' "$PWD" | sed 's/[^a-zA-Z0-9]/-/g')
CACHE="$HOME/.claude/projects/${DASHED}/memory/dev-guides-recipes-cache.json"
```

Assemble `refs[]` — one per candidate excerpt, with `name` = the cache key (recipe name / guide
slug), `ref` = the display ref (`<recipe>@<ver>` or `<slug>`), `kind`, and `excerpt` = the exact text
you intend to inline. Add `compiled_from` paths:

```bash
LOCK=$(jq -n --arg cf "$CACHE" --argjson refs "$REFS" \
  --arg arch "$TASK/architecture.md" --arg algn "$TASK/alignment.md" --arg res "$TASK/research.md" \
  '{cache_file:$cf, refs:$refs, compiled_from:{architecture:$arch, alignment:$algn, research:$res}}' \
  | bash "$KERNEL" lockfile-sha)                           # always exit 0
```

**Null-sha handling (the §14.5 dispatch gate now enforces this mechanically):**

```bash
NULL_REFS=$(echo "$LOCK" | jq -c '[.lockfile[] | select(.sha == null)]')           # the UNPINNED refs
ALL_NULL=$(echo "$LOCK" | jq -r '(.lockfile|length>0) and (all(.lockfile[]; .sha==null))')
```

For **every** entry with `sha == null` (cache miss — also surfaced as a `sha_not_in_cache:<name>`
warning): **do NOT inline that ref's excerpt** into `## Grounding` (an unpinnable body must not ship)
— but **KEEP the null-sha entry in the WO `lockfile` field**. The dispatch gate refuses any WO with a
`lockfile[].sha == null` (the `unpinned_ref` reason), so the kept entry is exactly what makes the unit
non-dispatchable. **Do NOT drop it, and do NOT touch `verified`** — carry the kernel's coverage
verdict verbatim; the grounding gate reads the separate `lockfile` / `drift_guard` fields, so there is
**no contradiction** with "carry verified verbatim." A human may record a `coverage_override` to
dispatch anyway (⇒ ③ no-auto-merge). Surface the unpinned refs (+ any drift failure) for confirm/prune.

**cwd amplifier — an all-null-sha batch is almost always a cache-cwd mismatch, not real drift.** The
cache path is `$PWD`-dasherized: if the compiler runs in a **different cwd** than recipe_loader's
populate run, the lookup misses on *every* ref ⇒ every WO blocks (`unpinned_ref`). That is
fail-closed-correct, but do **not** present it as N WOs each "below the grounding floor." When
`$ALL_NULL` is `true`, escalate as *"cache cwd mismatch — run the compiler in the same project
workspace as recipe_loader (the cwd whose dasherized form is `$DASHED`)"*, not a silent all-block.
Always compute `$CACHE` from the same cwd recipe_loader populated.

Then assemble the **full frontmatter object** with `jq` (every field from `work-order-contract.md`,
in contract order) and emit the YAML block:

```bash
FM_OBJ=$(jq -n \
  --arg id "local:$TASK_ID#wo-01" --arg title "..." --arg parent "local:$TASK_ID" \
  --arg status "$STATUS" --argjson blocks "$BLOCKS" --argjson blocked_by "$BLOCKED_BY" \
  --argjson requirements "$REQS_IDS" --arg coverage_ref "../coverage-map.json" \
  --argjson coverage_aspects "$UNIT_ASPECTS" --argjson verified "$VERIFIED" \
  --arg coverage_status "$CSTATUS" --argjson lockfile "$(echo "$LOCK" | jq -c '.lockfile')" \
  --argjson drift_guard "$(echo "$GUARD" | jq '.drift_guard')" \
  --argjson collapsed_scc "$COLLAPSED" --argjson gate_floor "$GATE_FLOOR" \
  --argjson autonomy_safe "$AUTONOMY_SAFE" \
  --argjson compiled_from "$(echo "$LOCK" | jq '.compiled_from')" --arg compiled_at "$(date -u +%FT%TZ)" \
  '{ id:$id, kind:"work-order", schema_version:"1.0", title:$title, parent:$parent, status:$status,
     blocks:$blocks, blocked_by:$blocked_by, children:null, external_ids:{},
     requirements:$requirements, coverage_ref:$coverage_ref, coverage_aspects:$coverage_aspects,
     verified:$verified, coverage_status:$coverage_status, lockfile:$lockfile, drift_guard:$drift_guard,
     collapsed_scc:$collapsed_scc, gate_floor:$gate_floor, autonomy_safe:$autonomy_safe,
     review_ref:null, critique_ref:null, risk_tier:null, size_estimate:null, coverage_override:null,
     compiled_from:$compiled_from, compiled_at:$compiled_at }')
FM_YAML=$(printf '%s' "$FM_OBJ" | bash "$KERNEL" emit-frontmatter)   # ---…--- block
```

`status` is `ready` when `blocked_by` is empty, else `blocked` (③ flips it later). The reserved seam
fields (`review_ref`/`critique_ref`/`risk_tier`/`size_estimate`/`coverage_override`) are emitted
`null` — ②/③/④ populate them. `emit-frontmatter` exits 2 only if stdin is not an object (a payload
bug); otherwise it always returns valid YAML.

## Step 10 — Write + surface `[model+kernel]`

Compose the file = the emitted YAML block + the inlined body, and **Write** it with the Write tool to
`<task>/work-orders/wo-NN-<slug>.md` (the slug from the title, kebab-case). Never write via a shell
heredoc/`echo` — the Write tool does not shell-parse untrusted content.

Then **surface the set for confirm/prune**: list each WO with its `verified` / `coverage_status` /
`collapsed_scc`. **Every `collapsed_scc: true` WO requires explicit human confirm** before it is
treated as dispatchable. Rank by relevance, guard over-matching, and flag any unit the dispatch gate
will block — a null-sha `lockfile` entry (`unpinned_ref`, step 9) or a `drift_guard` that is
`skipped`/`false` (step 8).

## Idempotency (N2 recompile-on-drift)

The compiler is idempotent on `compiled_from` / lockfile SHAs. A re-run recomputes each `sha` (body,
from the cache) and `excerpt_sha` (the inlined slice); when they diverge the excerpt drifted from its
pinned body — re-sync by re-inlining from the current body and re-emitting. The inlined excerpt is
the build-time truth; recompile-on-drift is the resolution.
