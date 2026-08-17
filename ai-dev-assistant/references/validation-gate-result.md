# Validation Gate Result Envelope v1.1

**Introduced:** ai-dev-assistant v3.13.0
**Owner:** `scripts/validation-envelope-write.sh`
**Producers:** `commands/validate-*.md`, by calling that script
**Consumers (as of v3.13.0):** `commands/validate-all.md`, `commands/complete.md` (future, when v2 batch-approval lands)

Every `/validate:*` command emits and persists a JSON result object with this shape, regardless of whether it wraps a `code-quality-tools` skill or implements its own check (guides, visual-parity, visual-regression). A shared envelope keeps consumers (`/validate:all`, future reports, `/complete` hooks) simple.

## 0. Cross-plugin field names (v1.1)

`code-quality-tools` and `code-paper-test` report results as `status`, `findings`, and `timestamp`. This envelope used `verdict`, `messages`, and `run_at` for the same three ideas, so a tool reading both plugins needed two code paths.

As of v1.1 every envelope carries **both** sets. The pairs hold the same information:

| Shared name | ai-dev-assistant name | Relationship |
|---|---|---|
| `status` | `verdict` | Same string, always equal |
| `timestamp` | `run_at` | Same ISO-8601 UTC string, always equal |
| `findings` | `messages` | `findings` is the structured form. See below |

`messages[]` holds human-readable strings. `findings[]` holds one object per message: `{"severity": <string>, "title": <the message string>}`. Severity comes from the verdict: `fail` → `HIGH`, `warning` → `MEDIUM`, `pass` and `skipped` → `INFO`. `findings` is always an array, never `null` and never absent, so `jq '.findings[]'` is safe on a clean run.

The ai-dev-assistant names are **not** deprecated in v1.1. Anything reading `verdict`, `messages`, or `run_at` keeps working unchanged. Prefer the shared names in new code.

One difference remains: this envelope's `status` can be `skipped`, which the other two plugins do not emit. Treat an unknown status as non-blocking.

## 1. Shape

```json
{
  "schema_version": "1.1",
  "gate": "tdd",
  "task": "dev_framework_granular_validation",
  "run_at": "2026-04-24T15:00:00Z",
  "timestamp": "2026-04-24T15:00:00Z",
  "verdict": "pass",
  "status": "pass",
  "details": {
    "source": "code-quality-tools:tdd",
    "raw_output_path": "/abs/path/.reports/tdd.json"
  },
  "messages": [
    "Red-Green-Refactor cycle observed across 3 commits",
    "All new logic has tests"
  ],
  "findings": [
    {"severity": "INFO", "title": "Red-Green-Refactor cycle observed across 3 commits"},
    {"severity": "INFO", "title": "All new logic has tests"}
  ]
}
```

## 2. Field contracts

| Field | Type | Values / constraints |
|---|---|---|
| `schema_version` | string | `"1.1"`, unchanged since v5.22.0. JSON string. Consumers match on major (`^1\.`) |
| `gate` | string | Gate identifier: `tdd` \| `solid` \| `dry` \| `security` \| `guides` \| `playbook-adherence` \| `e2e` \| `visual-parity` \| `visual-regression`. Matches the `/validate:<gate>` command name. The list is a closed set in `scripts/validation-envelope-write.sh`; anything else is rejected |
| `task` | string | Task folder name the run was scoped to |
| `run_at` | string | ISO-8601 UTC with `Z` suffix |
| `timestamp` | string | Same value as `run_at`. The cross-plugin name |
| `verdict` | enum | `"pass"` \| `"warning"` \| `"fail"` \| `"skipped"` |
| `status` | enum | Same value as `verdict`. The cross-plugin name |
| `details` | object | Gate-specific detail structure. See the gate details section |
| `messages` | array of string | Human-readable findings. Shown in CLI output. Non-empty for warning/fail; usually present for pass too (e.g., "3 checks passed") |
| `findings` | array of object | One `{severity, title}` per entry in `messages`. Always an array, never `null`, never absent. The cross-plugin name |

## 3. Verdict semantics

| Verdict | Meaning | Exit behavior |
|---|---|---|
| `pass` | Gate's criteria met. Nothing to fix | Command prints summary + exits 0 |
| `warning` | Gate passes but with observations worth surfacing (e.g., "TDD followed but 1 commit lacks a test"). Not blocking | Command prints summary + exits 0 |
| `fail` | Gate's criteria NOT met. Action required | Command prints summary + exits 1 (signals failure; user/AI can see + fix) |
| `skipped` | Gate was invoked but not run (e.g., user passed `--skip`, or the underlying tool is unavailable) | Command prints reason + exits 0 |

All gates are advisory by default — `fail` does NOT block the user's workflow (soft-nudge posture). The exit code communicates the result to invokers that want to chain (e.g., CI, `/validate:all` orchestration).

## 4. `details` — gate-specific structures

The `details` object's shape depends on `gate`. Consumers reading it should guard on `gate` field first.

### Wrapper gates (tdd, solid, dry, security)

```json
"details": {
  "source": "code-quality-tools:tdd",
  "raw_output_path": "/abs/path/.reports/tdd.json",
  "code_quality_tools_version": "3.0.0"
}
```

- `source` — the underlying skill invoked (always `code-quality-tools:<gate>`)
- `raw_output_path` — absolute path to the unmodified output from the wrapped tool, for deep diagnosis
- `code_quality_tools_version` — version of the dependency at run time

### Guides gate (framework-owned)

```json
"details": {
  "source": "framework:guides",
  "checked_artifacts": [
    "/abs/path/task/research.md",
    "/abs/path/task/architecture.md"
  ],
  "guides_cited": ["<framework>/forms/config-forms", "<framework>/caching/cache-api"],
  "guides_expected_min": 1,
  "code_inference": {
    "source": "session+implementation_md+git",
    "sources_used": ["session", "implementation_md", "git"],
    "changed_files_count": 12,
    "matcher_output": {
      "schema_version": "1.0",
      "mode": "validation",
      "matched_guides": [
        {"slug": "<framework>/services/dependency-injection", "reason": "...", "confidence": "high", "triggered_by": ["src/Service/DataService.php"]}
      ],
      "unmatched_files": [],
      "warnings": []
    },
    "inferred_slugs": ["<framework>/services/dependency-injection"],
    "domain_coverage_gaps": ["<framework>/services/dependency-injection"]
  }
}
```

- `source` — always `framework:guides`
- `checked_artifacts` — files inspected for guide citations
- `guides_cited` — guide slugs found in the artifacts (via dev-guides-navigator markers)
- `guides_expected_min` — minimum guide count for the gate to pass (default 1; configurable)
- `code_inference` — (v4.3.0+) catalog-grounded inference from `guides-matcher` agent. `source: "none"` when no files surfaced; `suppressed_by_flag: true` when `--no-code-inference` was passed; `matcher_output.warnings: ["catalog_cache_missing"]` when the dev-guides cache is unavailable (no penalty applied). `domain_coverage_gaps != []` demotes `pass` → `warning`. See `references/guides-matcher-schema.md` for the agent contract.

### Visual gates (visual-parity, visual-regression)

```json
"details": {
  "source": "framework:visual-regression",
  "component": "home-hero",
  "viewport": "1920x1080",
  "reference_path": "/abs/path/.screenshots/home-hero/1920x1080.png",
  "capture_path": "/abs/path/.validations/tmp/home-hero-1920x1080.png",
  "diff_path": "/abs/path/.validations/tmp/home-hero-1920x1080.diff.png",
  "diff_percent": 0.03,
  "diff_tolerance": 0.001,
  "classification": "regression",
  "baseline_updated": false
}
```

- `component`, `viewport` — which baseline was compared
- `reference_path` — baseline for regression; imported parity reference for parity
- `capture_path` — the fresh screenshot captured this run
- `diff_path` — diff image (present only when diff > 0)
- `diff_percent` — fraction of pixels different (0.0 = identical; 1.0 = completely different)
- `diff_tolerance` — hard-coded 0.1% (0.001) in v1; v2 candidate for per-image tuning
- `classification` — `null` if no diff; otherwise `"regression"` (user said it's a bug) \| `"intentional"` (user approved update) \| `"cancelled"` (user aborted)
- `baseline_updated` — true only when `classification: "intentional"` AND writer rotation succeeded

## 5. Persistence

`scripts/validation-envelope-write.sh` writes the result to TWO locations in the
task folder. A `/validate:*` command does not write these files itself; it calls
the script:

```
<task>/validations/
├── latest/
│   └── <gate>.json          # overwritten on each run — fast lookup of most recent
└── history.jsonl            # appended on each run — one JSON object per line
```

- `latest/<gate>.json` — most recent result per gate, written via temp file + rename. `/validate:all` reads these to aggregate. `/complete` (future) may check for pending updates
- `history.jsonl` — full run log, newest at the bottom. JSONL (one object per line) makes append cheap and git-diff legible

`/validate:all` ALSO writes an aggregate `<task>/validations/latest/_all.json` with a summary envelope (see the aggregate envelope section), through the same script in its `aggregate` mode.

## 6. Aggregate envelope (`/validate:all`)

```json
{
  "schema_version": "1.1",
  "run_at": "2026-04-24T15:30:00Z",
  "timestamp": "2026-04-24T15:30:00Z",
  "task": "dev_framework_granular_validation",
  "verdict": "warning",
  "status": "warning",
  "gates": [
    {"gate": "tdd", "verdict": "pass", "status": "pass", "messages": []},
    {"gate": "solid", "verdict": "warning", "status": "warning", "messages": ["1 class exceeds 200 lines"]},
    {"gate": "visual-regression", "verdict": "pass", "status": "pass", "messages": []}
  ],
  "summary": {
    "pass": 2,
    "warning": 1,
    "fail": 0,
    "skipped": 0,
    "total": 3
  },
  "messages": [
    "solid: 1 class exceeds 200 lines"
  ],
  "findings": [
    {"severity": "MEDIUM", "title": "solid: 1 class exceeds 200 lines"}
  ],
  "discoverability_hint": "See also: /code-quality:lint, :coverage, :review, :audit, :ultrareview"
}
```

The aggregate's own `status` is the worst gate status present: `fail` if any gate
failed, else `warning` if any warned, else `pass` if any passed. **A run in which
every gate was skipped aggregates to `skipped`, not `pass`** — a run that checked
nothing must not read like a run that found nothing wrong. Its `findings[]`
collects every gate's messages, each `title` prefixed with the gate name and its
severity taken from that gate's own verdict, so one failing gate's findings stay
HIGH inside a `warning` aggregate.

The aggregate carries no top-level `gate` field; it is identified by its `gates[]`
array and by its `_all.json` filename. It does carry `verdict` alongside `status`,
like every other envelope. Optional `source` and `run_id` fields appear when the
caller supplies them (`/validate:team` sets both).

Every example in this file was produced by running the emitter, not typed. What
matches is the field set and the values; the whitespace does not, because these
examples keep short arrays on one line for reading and `jq` expands them. A
reader comparing an example against live output should compare values, not bytes.
`tests/validation-envelope-contract-spec.sh` re-derives this aggregate's
`summary`, `status`, `messages` and `findings` from its own `gates[]` using the
emitter's rules, so an example that stops agreeing with the code fails the suite.

## 7. Invariants

1. `schema_version` is always present and matches `^1\.`
2. `gate` matches one of the 9 known IDs: `tdd`, `solid`, `dry`, `security`, `guides`, `playbook-adherence`, `e2e`, `visual-parity`, `visual-regression`. The aggregate has no `gate` field — it is identified by `gates[]` and by its `_all.json` filename
3. `verdict` is one of the 4 enum values
4. `details.source` prefix identifies provenance: `code-quality-tools:*` for wrappers, `framework:*` for owned gates
5. `messages[]` is always an array (possibly empty); never absent
6. `findings[]` is always an array (possibly empty); never absent, never `null`
7. `status == verdict` and `timestamp == run_at` in every envelope
8. `findings[]` has exactly one entry per `messages[]` entry, in the same order, each `title` repeating its message and each `severity` derived from the verdict

### How much of that is enforced, and where the gap still is

`scripts/validation-envelope-write.sh` is the only place an envelope is built.
It takes a gate, a task, a verdict, zero or more messages and the gate's own
`details`, and **derives** the rest: `status` is written from the same variable
as `verdict`, `timestamp` from the same clock read as `run_at`, and `findings[]`
is generated from `messages[]` by one jq expression that applies the single
severity mapping in the file. Invariants 5 through 8 hold because there is no
code path that can produce anything else — not because a template says so.
Invariants 2 and 3 are checked against closed lists and rejected with exit 2,
so a typo fails loudly instead of writing a malformed envelope. Every value
reaches jq through `--arg` / `--argjson`, so a finding containing quotes,
newlines or shell metacharacters cannot corrupt the output.

**How far the guarantee reaches into `details`.** Not far, and the limit is
worth stating exactly. `details` is the gate's own object and every gate has
its own shape, so the emitter does not validate that shape. It enforces two
things: `details` must be a JSON object, and it must carry no duplicate key at
any depth. The second is not cosmetic — jq resolves a duplicate key by keeping
the last one and reporting nothing, and two of the three drifts that motivated
this script were duplicate keys inside `details.surfaces[]`. The emitter now
parses the raw text with a parser that refuses duplicates before jq sees it,
and rejects with exit 2. That check needs python3; where python3 is missing the
script prints on stderr that it did not run, so the absence is never silent.

What remains yours: everything else about `details`. A per-surface
`verdict`/`status` pair inside `details.surfaces[]` is the command's to keep
consistent — the emitter pairs the envelope's own top-level `verdict`/`status`
and no others, and it will not notice a surface whose two disagree. The same
key appearing in two sibling objects is ordinary data and is accepted.

`scripts/gate-audit-write.sh` is a different artifact and not a variant of this
one: it writes `<task>/_<gate>.json` against `references/gate-audit-schema.md`
from an already-built payload, keyed on `gate_type` and requiring `fired_at` and
`gate_specific`. `scripts/wo-review-snapshot.sh` only copies envelopes that
already exist. `scripts/validate-e2e.sh`, `scripts/visual-parity-gate.sh` and
`scripts/visual-regression-gate.sh` measure — they take a code path and a
registry, know nothing of a task folder, and their per-surface output is not a
verdict until the calling command has classified it. Their stdout becomes the
envelope's `details`; they do not call the emitter.

**The gap that remains:** nothing forces a gate to call the emitter. Each
`validate-*.md` command *instructs* a model to invoke the script, and a model
that ignores the instruction and writes a file by hand produces an envelope with
no guarantees at all. `tests/validation-envelope-contract-spec.sh` narrows this
from the other side — it fails if any command file hand-types an envelope — but
that is a check on the instructions, not on a run. The shape is guaranteed; the
calling is not.

A consumer can rely on the paired names agreeing in any envelope the emitter
produced. Reading defensively still costs nothing: prefer `status`, `timestamp`
and `findings`, and fall back to `verdict`, `run_at` and `messages`. Envelopes
written before this script existed are still on disk in older task folders and
carry only the conventions of their day.

## 8. Versioning policy

Matches `code-paper-test`'s policy so both plugins version the same way.

- Adding fields — bump the minor (`1.0` → `1.1`). Back-compatible
- Adding new `gate` values — additive within v1.x
- Adding new `verdict` / `status` values — additive within v1.x; treat unknown values as non-blocking
- Adding new `details.source` values — additive
- Removing any field, or changing what one means — major bump

Pin with `^1\.`, not `== "1.1"`:

```bash
jq -e '.schema_version | test("^1\\.")' <envelope> >/dev/null || exit 1
```

## 9. Examples by gate

### tdd (wrapper), pass

```json
{
  "schema_version": "1.1",
  "gate": "tdd",
  "task": "fix_login_redirect",
  "run_at": "2026-04-24T15:00:00Z",
  "timestamp": "2026-04-24T15:00:00Z",
  "verdict": "pass",
  "status": "pass",
  "details": {
    "source": "code-quality-tools:tdd",
    "raw_output_path": "/abs/path/.reports/tdd.json",
    "code_quality_tools_version": "3.0.0"
  },
  "messages": ["Red-Green-Refactor cycle observed across 3 commits"],
  "findings": [
    {"severity": "INFO", "title": "Red-Green-Refactor cycle observed across 3 commits"}
  ]
}
```

### solid (wrapper), warning

```json
{
  "schema_version": "1.1",
  "gate": "solid",
  "task": "settings_form_refactor",
  "run_at": "2026-04-24T15:01:00Z",
  "timestamp": "2026-04-24T15:01:00Z",
  "verdict": "warning",
  "status": "warning",
  "details": {
    "source": "code-quality-tools:solid",
    "raw_output_path": "/abs/path/.reports/solid.json",
    "code_quality_tools_version": "3.0.0"
  },
  "messages": [
    "SettingsForm::submit violates SRP (mixes validation + persistence + notification)",
    "Consider splitting into SettingsFormValidator + SettingsFormPersister"
  ],
  "findings": [
    {"severity": "MEDIUM", "title": "SettingsForm::submit violates SRP (mixes validation + persistence + notification)"},
    {"severity": "MEDIUM", "title": "Consider splitting into SettingsFormValidator + SettingsFormPersister"}
  ]
}
```

### guides (framework-owned), fail

```json
{
  "schema_version": "1.1",
  "gate": "guides",
  "task": "data_model_refactor",
  "run_at": "2026-04-24T15:02:00Z",
  "timestamp": "2026-04-24T15:02:00Z",
  "verdict": "fail",
  "status": "fail",
  "details": {
    "source": "framework:guides",
    "checked_artifacts": ["/abs/path/research.md", "/abs/path/architecture.md"],
    "guides_cited": [],
    "guides_expected_min": 1
  },
  "messages": [
    "No dev-guides citations found in research.md or architecture.md",
    "Data-model work typically loads <framework>/entities/* guides; consider /dev-guides-navigator"
  ],
  "findings": [
    {"severity": "HIGH", "title": "No dev-guides citations found in research.md or architecture.md"},
    {"severity": "HIGH", "title": "Data-model work typically loads <framework>/entities/* guides; consider /dev-guides-navigator"}
  ]
}
```

### visual-regression, intentional change approved

```json
{
  "schema_version": "1.1",
  "gate": "visual-regression",
  "task": "hero_cta_update",
  "run_at": "2026-04-24T15:03:00Z",
  "timestamp": "2026-04-24T15:03:00Z",
  "verdict": "pass",
  "status": "pass",
  "details": {
    "source": "framework:visual-regression",
    "component": "home-hero",
    "viewport": "1920x1080",
    "reference_path": "/abs/path/.screenshots/home-hero/1920x1080.png",
    "capture_path": "/tmp/fresh.png",
    "diff_path": "/tmp/diff.png",
    "diff_percent": 0.042,
    "diff_tolerance": 0.001,
    "classification": "intentional",
    "baseline_updated": true
  },
  "messages": [
    "Diff detected (4.2%). User classified as intentional; baseline rotated",
    "Previous baseline archived as .previous.png (prior_hash: 42936883...)"
  ],
  "findings": [
    {"severity": "INFO", "title": "Diff detected (4.2%). User classified as intentional; baseline rotated"},
    {"severity": "INFO", "title": "Previous baseline archived as .previous.png (prior_hash: 42936883...)"}
  ]
}
```

## 10. See also

- `scripts/validation-envelope-write.sh` — the emitter that owns this shape
- `tests/validation-envelope-contract-spec.sh` — runs the emitter, checks the invariants above against its real output, and fails if a command file hand-types an envelope
- `references/screenshot-store-schema.md` — the `.meta.json` schema referenced by visual gate details
- `commands/validate-all.md` — the orchestrator that consumes per-gate envelopes and emits the aggregate
- `commands/validate-tdd.md` (et al) — the per-gate commands that produce envelopes
- `dev_framework_granular_validation/architecture.md`
