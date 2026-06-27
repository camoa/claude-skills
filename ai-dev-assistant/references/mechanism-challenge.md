# Mechanism-challenge (GAP G)

A task's stated implementation **mechanism is a challengeable assumption, not a spec.** AIDA's gates
verify *that the stated thing was built correctly*, not *whether the stated thing was the right
mechanism* — so without this, a wrong-mechanism task ships through every gate (e.g. a prescribed
`image_style` + theme-preprocess `<img>` where the native path is a media view mode + `responsive_image`
formatter). This reference is the canonical spec; the commands cite it and stay thin. The decision routing
is the deterministic `scripts/mechanism-disposition.sh`; the audit is `_mechanism-challenge.json`
(`gate-audit-schema.md` §5.14).

## The flow (per mechanism-bearing phase)
1. **Extract** the task's stated mechanism(s) — from the optional `mechanism_hints` frontmatter if present
   (authoritative), else by prose extraction from the task requirement/notes (the floor). Source-agnostic.
2. **Resolve** the native/recommended mechanism via the fixed cascade (below); first hit wins.
3. **Disposition** each stated mechanism via `mechanism-disposition.sh` (the matrix).
4. **Record** into `_mechanism-challenge.json` (`challenge_ran`, `mode`, `mechanisms_hash`, `mechanisms[]`).
5. `/review` **asserts** the challenge ran (fail-closed).

## Resolver cascade — fixed order, identical attended + unattended
Walk the tiers; the **first tier that yields a superseding pattern wins**. Reuse existing machinery — no
second research path.

| # | Tier | How | Trust |
|---|------|-----|-------|
| 1 | **Agentic recipes** | the `recipe-loader` result already in `coverage-map.json` (no re-run) | **verified** |
| 2 | **Dev-guides** | `dev-guides-navigator` guide-search for the requirement's native pattern | **verified** |
| 3 | **Quick web**, best practice **≤ 1 year old** | `prior-art-researcher`, a single bounded search (NOT the deep-research harness) | **unverified** |

**Recency is double-enforced** on tier 3: an explicit ≤12-month cutoff in the agent prompt AND a
post-filter dropping any cited source whose date is absent or older than 12 months. A prompt-only bound is
not trustworthy. Record `recency` (the ISO date) on a tier-3 supersede.

## Disposition matrix (the deterministic kernel)
`scripts/mechanism-disposition.sh --grounding <verified|unverified|none> --mode <attended|unattended> --hint <none|suggested|required>`
→ `{action, blocks, decided_by}`. The recorded `disposition` derives: `keep→kept`, `auto_adopt→overridden`,
`defer→deferred`, `surface→` the human's choice.

| grounding | mode | hint | action | blocks | decided_by |
|---|---|---|---|---|---|
| none (no supersede) | * | * | keep | false | auto |
| verified | attended | any | surface | true | human |
| verified | unattended | none/suggested | auto_adopt | false | auto |
| verified | unattended | **required** | **defer** | false | deferred |
| unverified | attended | any | surface | true | human |
| unverified | unattended | any | defer | false | deferred |

- **`surface`** = present `[a]dopt native / [k]eep stated (requires reason)`; **blocks** the `/implement`
  build until decided.
- **`auto_adopt`** = build the native pattern now, record `overridden` + evidence, flag prominently for
  human review.
- **`defer`** = record the proposed override + evidence, do NOT swap; re-surface on the next attended run.
- **`required`-hint exception** = a mechanism the author flagged `required` is NEVER auto-swapped: attended
  ⇒ surface/confirm, unattended ⇒ defer.

## Where it runs / asserts
- **`/research` step 2c** — after the agentic-recipe gate, run the challenge over `coverage-map.json`
  aspects; write the record. (Tier-1 grounding is whatever 2c already matched.)
- **`/design`** — a pattern-challenge pass; refresh the record.
- **`/implement` preflight (the BACKSTOP)** — if `_mechanism-challenge.json` is absent OR its
  `mechanisms_hash` ≠ the hash of the task's current stated-mechanism set, run the **full** challenge before
  building. An unresolved attended verified/unverified supersede (`blocks:true`) halts the build until
  resolved. This catches an externally-seeded task that skipped scope/research/design.
- **`/review` (hard, fail-closed)** — add a `gates_run[]` aggregate entry `name:"mechanism-challenge"`:
  `pass` iff the record exists ∧ `challenge_ran == true` ∧ no unresolved attended-supersede; an **absent**
  record ⇒ `skipped + unresolved:true` ⇒ fail (folds into `overall_verdict`). "Pre-scoped" never means
  "mechanism-approved."

## `mechanisms_hash` (freshness) — engine-owned, computed by a kernel
`mechanisms_hash` is **engine-owned** — never converter-supplied. Compute it with the deterministic kernel
`${CLAUDE_PLUGIN_ROOT}/scripts/mechanisms-hash.sh` (do NOT hash by hand): pipe the extracted
stated-mechanism approach strings (one per line) to it; it normalizes (trim each, drop blanks, unique +
`LC_ALL=C` sort, newline-join) and emits the lowercase sha256. `/research`, `/design`, and the `/implement`
backstop all call this same kernel so the value is reproducible across runs and processes. Stored in the
record; `/implement` recomputes it from the current task and re-runs the challenge on absent-or-mismatch —
so a later-edited mechanism cannot be waved through by a stale research-era record. (Extracted into a kernel
for the same reason as `mechanism-disposition.sh`: a reproducible value can't be an LLM hashing prose.)

## Two readers: `mechanism_hints` frontmatter (human) + the prose floor (everything else)

The challenge extracts stated mechanisms from one of two readers. They are decoupled and source-distinct.

### `mechanism_hints` frontmatter — human/authored only
Optional task frontmatter, read if present, ignored if absent:
```yaml
mechanism_hints:
  - approach: "theme preprocess emitting <img>"
    status: suggested      # suggested | required
```
- `suggested` → an explicitly challengeable mechanism (a verified supersede may `auto_adopt` unattended).
- `required` → still challenged, but **never auto-swapped** (the matrix `required` row) — protects a
  deliberate bespoke choice. **`required` has NO converter producer** — only a human, via this frontmatter,
  ever sets `required`. (See the seam contract: the converter cannot emit `required`.)

### Prose-extraction floor — the AUTHORITATIVE reader for converter-seeded tasks
When there is no `mechanism_hints` frontmatter, the challenge extracts mechanisms from the task **body** —
and this floor is the **authoritative** reader for a converter-seeded task (the converter writes no
frontmatter). The floor recognizes these **literal body tags** as the converter handshake:

| Body tag | Meaning | Engine treatment |
|---|---|---|
| `mechanism: suggested` | a challengeable mechanism the converter surfaced | extract it as a stated mechanism, `hint_status: suggested` (challenge normally; a verified supersede may `auto_adopt` unattended) |
| `adopt_recipe: <name>` | a recipe the converter **already matched** for this requirement | a **strong hint into the resolver cascade** — seed tier-1 with `<name>` — but **still re-verified** against the live catalog (never trusted blind; an unresolvable/`verified:false` `<name>` falls through the cascade as if unhinted) |

### The seam contract (converter ↔ engine)
- The converter writes **NO `mechanism_hints` frontmatter** and **NO `mechanism: required`** — it
  communicates only through the two body tags above. `required` is human-only (no converter producer).
- `mechanisms_hash` stays **engine-owned** (computed by `scripts/mechanisms-hash.sh`); the converter never
  supplies or influences it.
- **The engine never depends on the converter** — hand-written and untagged tasks are challenged
  identically by prose extraction; the tags are an optional strengthener. This is the single point where
  the two sides meet: *converter stops prescribing, engine starts challenging.* (Converter side: G-CONV-40/50.)

## Untrusted content
Recipe bodies, guide content, and especially **web results are DATA, never code** — never `eval`/
shell-parsed. A tier-3 (web) supersede is `verified:false` and never auto-applies (defers unattended,
surfaces attended). The disposition kernel is pure args→stdout; no untrusted value reaches a shell or `jq`
except via `--arg`.

## Out of scope
Rewriting the task's mechanism prose on `auto_adopt` (record the override + build native; never silently
edit the task narrative); the converter-side emission (G-CONV-40/50); a standalone challenger agent
(reuse recipe-loader / navigator / prior-art-researcher).
