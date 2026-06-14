# AI Test Selector — Output Schema v1.0

**Introduced:** ai-dev-assistant (ATC slice)
**Owner:** `agents/ai-test-selector.md`
**Consumers:** gate-dispatch layer; WO-02 contract spec (`tests/ai-test-selector-contract-spec.sh`)

The `ai-test-selector` agent emits a single JSON object per invocation. Schema is versioned via
`schema_version`. Future fields may be added at v1.x without breaking v1.0 consumers.

## Output Object

```json
{
  "schema_version":      "1.0",
  "gate":                "e2e | visual_regression",
  "candidate_surfaces":  ["<id>", "..."],
  "selected_surfaces":   ["<id>", "..."],
  "skipped_surfaces":    [
    { "id": "<id>", "reason": "<high-confidence exclusion rationale>" }
  ],
  "degraded":            false,
  "selection_model":     "sonnet",
  "diff_files_analyzed": 7
}
```

## Field Contracts

| Field | Type | Contract |
|---|---|---|
| `schema_version` | string | Always `"1.0"` (quoted). Never a number. |
| `gate` | string | Echoes the input `gate` value: `"e2e"` or `"visual_regression"`. |
| `candidate_surfaces` | string[] | Every registry surface whose `gates[]` contains `<gate>`. Order matches registry order. May be empty only when the registry is unreadable (→ `degraded: true`). |
| `selected_surfaces` | string[] | The affected subset to RUN. Always `⊆ candidate_surfaces`. When `degraded: true`, equals `candidate_surfaces` exactly. |
| `skipped_surfaces` | object[] | One entry per surface in `candidate_surfaces` that is NOT in `selected_surfaces`. Shape: `{id: string, reason: string}`. When `degraded: true`, this array MUST be `[]`. |
| `skipped_surfaces[].id` | string | Surface ID matching a registry entry in `candidate_surfaces`. |
| `skipped_surfaces[].reason` | string | Concrete, evidence-anchored exclusion rationale (see the "Reason Contract" section below). |
| `degraded` | bool | `true` iff the full candidate set was selected due to thin evidence (see the "Degraded Semantics" section below). |
| `selection_model` | string | The model used for selection reasoning. Always `"sonnet"` for the current agent version. |
| `diff_files_analyzed` | int | Count of files in the input `diff_files` list that were considered. MUST equal `len(diff_files)`. |

## `skipped_surfaces[].reason` Contract

A valid reason MUST:
- Cite a specific file, route, hook, service, or template boundary that was checked.
- State what was NOT found (e.g., "no route/hook for `/checkout`").
- Be verifiable by re-running the same grep/read against the worktree.

**Acceptable example:**
> "diff is entirely in `modules/custom/foo/foo.module` which registers no route, hook, or service
> for `/checkout` (Grep confirmed no references to checkout path)."

**Not acceptable:**
> "Looks unrelated." / "foo.module seems backend-only." / "URL path doesn't match."

If a concrete reason cannot be stated, the surface MUST be selected, not skipped.

## Degraded Semantics

`degraded: true` means the agent fell back to the full candidate set due to insufficient evidence
for selective exclusion. This occurs when ANY of:

1. The registry file at `registry_path` is missing, unparseable, or returns 0 surfaces for `<gate>`.
2. `gate == "e2e"` AND `spec_plans_dir` is null or yields no readable plan files AND the surface
   URLs are uninformative (cannot be matched to diff scope).

When `degraded: true`:
- `selected_surfaces` equals `candidate_surfaces` exactly.
- `skipped_surfaces` is `[]` (no exclusions when evidence is thin).
- Consumers MUST treat this as a signal that ALL candidate surfaces should run and that the agent
  lacked the evidence to narrow further. This is the safe fallback — better to over-test than to
  miss a regression.

When `degraded: false`:
- The agent had sufficient evidence to reason about each candidate surface.
- At least one surface was either excluded (appears in `skipped_surfaces`) OR all candidates were
  selected with high confidence (no skips, `degraded: false`).

## Invariants (consumer-enforceable)

1. **Subset:** `selected_surfaces ⊆ candidate_surfaces`. Consumers MUST reject output where a
   selected ID does not appear in `candidate_surfaces`.
2. **Partition:** `candidate_surfaces = selected_surfaces ∪ {s.id for s in skipped_surfaces}`.
   Every candidate is either selected or skipped — no surface is silently dropped.
3. **Skip completeness:** `len(skipped_surfaces) == len(candidate_surfaces) - len(selected_surfaces)`.
4. **Degraded consistency:** if `degraded == true` then `skipped_surfaces == []` AND
   `selected_surfaces == candidate_surfaces`.
5. **Reason required:** every entry in `skipped_surfaces` has a non-empty `reason`.
6. **diff_files_analyzed:** equals the count of files provided in the input `diff_files` list.

## Non-Goals (what this schema does NOT cover)

- **`visual_parity` gate:** out of scope. `visual_parity` is reference-driven, not diff-driven.
  The agent and this schema handle only `"e2e"` and `"visual_regression"`.
- **Dependency graph:** the schema records which surfaces were selected and why, not a computed
  dependency index. Reasoning happens at invocation time from the registry + plan prose.
- **Test execution results:** this schema is for selection only. Test outcomes are recorded by the
  gate executor, not this agent.

## Versioning

Schema version `"1.0"`. New fields may be added at `1.x` without breaking consumers that ignore
unknown fields. A change to any field's semantics (type, required-ness, invariant) requires a
major version bump and a corresponding agent version bump.
