# Degrade Paths

`recipe-loader` **never blocks**. Every miss yields a non-empty, honest coverage map (worst case:
residual guides + flagged uncovered aspects). The methodology floor a phase loads is independent of
this skill, so a task is never left with zero grounding.

| Condition | Behavior |
|---|---|
| **0 recipes match** | Clean + common (the catalog is small today). The navigator's own rule: *recipe-search misses defer to guide search*. recipe-loader → pure residual guide coverage. No warning needed. |
| **Recipe matched, no `requires_*` frontmatter** | Match it (the routing block is present), contribute **0** machine-resolvable guides, fall to residual guide-search for its aspect, surface the recipe's prose `## References` to the human (do not machine-parse it). Emit `recipe_matched_no_machine_deps:<capability>`. A recipe that declares no `requires_*` falls here (e.g. an older or partially-authored recipe). |
| **Recipe body missing / malformed sha** (no shared-store blob for the index-line sha8, or the sha8 isn't exactly 8 lowercase-hex) | Emit `recipe_body_unverified:<name>`; **skip the body and its declared deps**; the aspect falls to residual guide-search. (SKILL.md step 5 reads the content-addressed blob `~/.claude/dev-guides-store/blobs/<sha8>` — a present blob is the body for that exact upstream version, so index↔body drift is structurally impossible; a missing blob means the navigator body-fetch didn't populate it; a non-hex sha is never built into a path. Still does not catch a self-consistent forged blob.) |
| **Recipe index unavailable** (shared store `indexes/agentic-recipes.json` absent/empty) | The navigator populates the shared store on its step-2 revalidate. If offline / it cannot, skip the recipe layer and degrade to guides; emit `recipe_cache_missing` **and set `recipe_lookup_status: index_unavailable`** so the orchestrator reads it as *"couldn't check"*, not a terminal `no_match`. The shared store is a **single global catalog** (no per-project/cwd keying), so there is no foreign-project cache to mis-resolve — the old cwd-derived-path hazard is gone by construction. |
| **Navigator unavailable / skill errors** | Skip the recipe layer entirely; produce a guides-only map (or just flagged uncovered aspects); emit `navigator_unavailable` **and set `recipe_lookup_status: navigator_unavailable`** (inconclusive, not a terminal `no_match`). Never invent recipes or fetch directly. |
| **Dangling `requires_guides` slug** (recipe names a guide absent from the catalog) | **Surface**, do not repair. Emit `slug_not_in_catalog:<slug>`; do not fetch-to-fix (the cross-catalog link-checker in dev-guides CI owns that). The aspect falls to residual guide-search. |
| **Over-match** (too many low-relevance recipes/guides) | Not an error — rank by `relevance` and **surface for confirm/prune**. Never auto-load everything. |

## Invariant
Whatever degrades, the emitted map still satisfies the contract (`coverage-map-contract.md`):
`uncovered_aspects[]` lists every aspect with no source, entries are ranked, and `provenance`/
`verified` are present. "Never silently under-cover" means uncovered aspects are *always listed*,
never omitted — a degrade is visible, not silent.
