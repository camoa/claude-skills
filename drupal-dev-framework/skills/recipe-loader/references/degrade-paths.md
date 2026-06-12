# Degrade Paths

`recipe-loader` **never blocks**. Every miss yields a non-empty, honest coverage map (worst case:
residual guides + flagged uncovered aspects). The methodology floor a phase loads is independent of
this skill, so a task is never left with zero grounding.

| Condition | Behavior |
|---|---|
| **0 recipes match** | Clean + common (the catalog is small today). The navigator's own rule: *recipe-search misses defer to guide search*. recipe-loader → pure residual guide coverage. No warning needed. |
| **Recipe matched, no `requires_*` frontmatter** | Match it (the routing block is present), contribute **0** machine-resolvable guides, fall to residual guide-search for its aspect, surface the recipe's prose `## References` to the human (do not machine-parse it). Emit `recipe_matched_no_machine_deps:<capability>`. A recipe that declares no `requires_*` falls here (e.g. an older or partially-authored recipe). |
| **Recipe body fails the integrity gate** (cached body sha ≠ index-line sha, or body missing) | Emit `recipe_body_unverified:<name>`; **skip the body and its declared deps**; the aspect falls to residual guide-search. (SKILL.md step 5 `[ ]` gate; catches index↔body drift, not a self-consistent forged cache.) |
| **Recipe cache missing** (cwd-derived path absent) | The navigator populates it on first recipe-search. If offline / it cannot, skip the recipe layer and degrade to guides; emit `recipe_cache_missing`. **Never glob-fallback to another project's cache** — a foreign project's recipes are the wrong catalog and an attacker-seeding vector; the cwd-derived path is the only valid cache. |
| **Navigator unavailable / skill errors** | Skip the recipe layer entirely; produce a guides-only map (or just flagged uncovered aspects); emit `navigator_unavailable`. Never invent recipes or fetch directly. |
| **Dangling `requires_guides` slug** (recipe names a guide absent from the catalog) | **Surface**, do not repair. Emit `slug_not_in_catalog:<slug>`; do not fetch-to-fix (the cross-catalog link-checker in dev-guides CI owns that). The aspect falls to residual guide-search. |
| **Over-match** (too many low-relevance recipes/guides) | Not an error — rank by `relevance` and **surface for confirm/prune**. Never auto-load everything. |

## Invariant
Whatever degrades, the emitted map still satisfies the contract (`coverage-map-contract.md`):
`uncovered_aspects[]` lists every aspect with no source, entries are ranked, and `provenance`/
`verified` are present. "Never silently under-cover" means uncovered aspects are *always listed*,
never omitted — a degrade is visible, not silent.
