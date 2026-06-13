# Bead Projection Map — the verified work-order ↔ bead projection

The detail behind the MAP in `work-order-contract.md`. Projection is **markdown → bead always** (§6):
the work-order file is the source of truth, a Beads bead is a downstream mirror, and a bead **never**
writes back to the work-order **except** its own minted id into `external_ids.beads`. Beads is **not
built here** — this is the designed-projectable shape so a future L2 importer is mechanical.

> **VERIFIED 2026-06-08** against Beads primary source (Go source on `steveyegge/beads` HEAD): the
> `Issue` struct, the `Status` / `IssueType` / `DependencyType` enums, and `create.go` /
> `create_input.go` / `update.go` / `ready.go`. **Residual UNVERIFIED (does NOT block — the design
> maps only to built-ins):** custom Beads statuses/types beyond the built-in enums (we never emit a
> custom value); the verifier read HEAD, not the `v1.0.4` tag.

## Why it is NOT uniform "structural reuse"

An earlier draft assumed field-for-field reuse across the board. Verification corrected that: only
`parent` (an ai-dev-assistant field Beads also has) and the `in_progress` status value map cleanly. Everything else
is **minted**, **rewritten to a built-in**, or **projected to Beads' dependency-edge model**.

## Field-by-field projection

### `id` — minted by Beads, bridged both ways

Beads **mints** every id as a content-hash `prefix-{6-8hex}[.n.n]`. The work-order grammar
`local:<task>#wo-NN` (with `:` and `#`) is alien to Beads' id space, so it stays **markdown-only**.
The bridge is bidirectional and was confirmed (N4):

- work-order `id` → Beads `external_ref` (the bead records where it came from).
- Beads' minted `bd-…` id → work-order `external_ids.beads` (the work-order records its mirror).

**Do not force `--id`** at create: `--id` and `--parent` are mutually exclusive, and we want
`--parent` free. Letting Beads mint keeps both available.

### `kind` — `work-order` → `task`

Beads' `IssueType` enum has **no** `work-order`. Project `kind: work-order` → `issue_type: task`.
Custom issue types are UNVERIFIED, so we never emit one — `task` is the built-in floor.

### `status` — WO-native, the map translates

The work-order status enum is **WO-native** and does not match Beads (Beads:
`open | in_progress | blocked | deferred | closed | pinned | hooked` — no `ready`/`done`/`needs_rework`).

| Work-order `status` | Bead status | Note |
|---|---|---|
| `ready` | `open` | Beads has no `ready` — `bd ready` is a *computed query*, not a stored value |
| `blocked` | `blocked` | clean map |
| `in_progress` | `in_progress` | the one value that maps field-for-field |
| `done` | `closed` | |
| `needs_rework` | reopened `open` | no native equivalent — re-open the bead |

A bead is **born `open`** (no `--status` at create). A non-`ready` work-order therefore projects as
**create-then-`bd update --status`**. Direction is always markdown → bead; the bead's status is never
read back into the work-order (③ owns every work-order `status` transition — H-3).

### `parent` — clean reuse

`parent: local:<ddf_task>` reuses the ai-dev-assistant/bead `parent` field directly. Because we mint the id
(above), `--parent` stays available at `bd create`.

### `blocks` / `blocked_by` / `children` — dependency EDGES, not columns

These are **not** Beads columns. They project to Beads' **dependency-edge** model:

- At create: `bd create --deps "blocks:<bead-id>"` (a `blocks` edge) / `--deps "<bead-id>"` (a
  `blocked_by` edge, the default direction).
- `children` projects to a `parent-child` edge.
- **Post-create** edge changes use `bd dep add` / `bd dep remove` — **`bd update` does not mutate
  edges.**
- id **values** remap through the minted ids (resolve each `local:<task>#wo-NN` to its
  `external_ids.beads` before emitting the edge).

The work-order DAG (the H3 acyclicity invariant) is what guarantees these edges import as a valid
Beads dependency graph.

### The quality brain — never projected

`requirements` / `coverage_*` / `verified` / `lockfile` / `drift_guard` / `collapsed_scc` /
`gate_floor` / `autonomy_safe` / `review_ref` / `critique_ref` / `risk_tier` / `size_estimate` /
`coverage_override` / the body are **markdown-only**. Gate verdicts and grounding never live in Beads
(§6). A bead carries only the scheduling skeleton; the work-order file carries the truth.

## L2 importer forward-note (not built here)

When/if Beads is wired in (an L2 concern, out of this slice's scope), a Beads importer performs the
projection above:

1. For each work-order file, `bd create` (let Beads mint) with `--parent` + `issue_type: task` +
   `external_ref = <work-order id>`; record the minted id back into the work-order's
   `external_ids.beads`.
2. Resolve and emit the dependency edges (`--deps` at create where possible, `bd dep add` after).
3. Apply the non-`open` status via `bd update --status` per the table.

The importer reads the work-order files; it does **not** change the contract. Because the projection
targets only built-in Beads enums, the `external_ids` back-link absorbs either outcome of any residual
Beads-internals question (N4) — the freeze holds regardless. The compiler in this slice emits
contract-conformant work-orders and stops; it never calls `bd`.
