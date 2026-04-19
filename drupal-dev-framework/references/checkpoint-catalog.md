# Checkpoint Catalog

Canonical checkpoint sequences per phase. Each task.md frontmatter `checkpoints` key references these IDs.

## Phase 1: Research (7 checkpoints)

| ID  | Name | Entry Condition | Evidence |
|-----|------|-----------------|----------|
| 1.1 | Load user project constraints | Task folder exists | Constraints referenced in research.md or "none defined" noted |
| 1.2 | Identify task domain + expected guides | 1.1 done/skipped | Expected-guides list in research.md |
| 1.3 | Load guides via guide-integrator | 1.2 done | Loaded guide names listed in research.md |
| 1.4 | Contrib research | 1.3 done/skipped | Contrib modules evaluated in research.md |
| 1.5 | Core pattern research | 1.3 done/skipped | Core patterns cited in research.md |
| 1.6 | Write research.md with guide citations | 1.4, 1.5 done/skipped | research.md exists, cites guides from 1.3 |
| 1.7 | Verify all expected guides cited | 1.6 done | Citations match 1.2 expected list |

## Phase 2: Architecture (6 checkpoints)

| ID  | Name | Entry Condition | Evidence |
|-----|------|-----------------|----------|
| 2.1 | Re-inject loaded-guides summary | Phase 1 complete | Active guide list in context at phase start |
| 2.2 | Load SOLID/DRY/architecture guides | 2.1 done | Architecture-domain guides loaded |
| 2.3 | Draft architecture.md | 2.2 done | architecture.md created with Components section |
| 2.4 | SOLID self-check | 2.3 done | All 5 principles addressed or N/A-justified in architecture.md |
| 2.5 | DRY self-check | 2.3 done | Reusable pieces identified, duplication risks noted |
| 2.6 | Cite guides for each decision | 2.3, 2.4, 2.5 done | Every major decision in architecture.md references a guide or notes "no guide applies" |

## Phase 3: Implementation (8 checkpoints, 3–5 loop per acceptance criterion)

| ID  | Name | Entry Condition | Evidence |
|-----|------|-----------------|----------|
| 3.1 | Load all prior phase context | Phase 2 complete | research.md + architecture.md referenced in implementation.md |
| 3.2 | Load security + coding-standards guides | 3.1 done | Security/standards guides loaded |
| 3.3 | **Red** — write failing test (per AC) | 3.2 done, AC not yet done | Failing test exists in repo |
| 3.4 | **Green** — implement minimum to pass | 3.3 done for current AC | Test passes |
| 3.5 | **Refactor** — SOLID/DRY cleanup | 3.4 done for current AC | Code refactored, test still passes |
| —   | *Loop 3.3–3.5 per acceptance criterion* | — | — |
| 3.6 | All acceptance criteria complete | 3.3–3.5 done for every AC | Every AC in task.md marked done |
| 3.7 | Security review | 3.6 done | Security check noted in implementation.md (SQL, XSS, access) |
| 3.8 | Constraint citations in implementation.md | 3.6, 3.7 done | Implementation cites guides + user patterns applied |

## Status Values

- `pending` — not yet started, entry conditions may or may not be met
- `in_progress` — actively being worked on
- `done` — evidence produced, entry conditions met for dependents
- `skipped` — deliberately not applicable; **REQUIRES a non-empty `justification` field**. A `skipped` entry without `justification` is treated as `pending` by checkpoint-gate (does NOT satisfy phase-entry checks).

Status values are **case-insensitive**. `Done`, `DONE`, `done` are equivalent. Canonical form for writing is lowercase.

## Frontmatter Schema

Checkpoints live in task.md YAML frontmatter under the `checkpoints` key:

```yaml
---
task: <task_name>
phase: 1
checkpoints:
  phase_1:
    - {id: "1.1", status: done, evidence: "research.md#constraints"}
    - {id: "1.2", status: done}
    - {id: "1.3", status: in_progress}
    - {id: "1.5", status: skipped, justification: "meta-task, no Drupal core applies"}
  phase_2: []
  phase_3: []
---
```

## Grandfather Mode (pre-MVP tasks)

Tasks without a `checkpoints` key in frontmatter fall back to the legacy Phase Status checklist. Existing completed tasks are unaffected. New tasks and tasks resumed after v3.9.0 should adopt the checkpoint schema.
