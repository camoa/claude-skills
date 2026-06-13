# Visual + E2E Review — Walkthrough

> _Drupal-flavored component — a stack-neutral version is in progress. The Drupal specifics below are the current reference implementation._

**Introduced:** ai-dev-assistant v4.11.0 (epic `visual_and_e2e_review_gates`)
**Audience:** maintainers and users of the framework's rendered-output review gates.
**Status after Task A:** foundation only — see "What ships when" below.

This walkthrough explains the three-surface / two-runtime / opt-in model the
`visual_and_e2e_review_gates` epic adds to ai-dev-assistant. It is reference
material — loaded only when explicitly read; no hook or skill auto-loads it.

## 1. Why — `/review` should check rendered output, not just source

Through v4.10.0, `/review` validates that *source* follows the rules — TDD, SOLID,
DRY, security, guides, playbook adherence. It does not check that the *page still works
and still looks right*. This epic adds three rendered-output review surfaces:

| Surface | Question it answers | Truth source | Runtime |
|---|---|---|---|
| **E2E** (behavioral) | Does the flow still *work*? | Behavioral assertions | ATK + Playwright |
| **Visual regression** | Did anything *change* vs. last green? | Committed baselines | `@lullabot/playwright-drupal` |
| **Visual parity** | Does this match the *design intent*? | An external design reference | Lullabot (shared with VR) |

**Dual purpose.** Humans use the gates to confirm a change didn't break anything; AI
uses them as feedback loops — to drive parity with a design and to catch and fix its
own regressions.

## 2. This is an EVOLVE epic, not greenfield

ai-dev-assistant **already ships** visual regression and visual parity gates —
introduced in **v3.13.0** (`validate-visual-regression`, `validate-visual-parity`),
built on ad-hoc Playwright MCP capture. The epic does **not** start fresh. It:

- **KEEPS** what is sound — the `.meta.json` provenance model, the
  `validation-gate-result.md` envelope, the regression-vs-intentional and
  parity-miss-vs-deviation classification UX.
- **REPLACES** capture (ad-hoc MCP → committed Playwright test files), invocation
  (one-component-per-call → registry-driven batch), and diff tooling.
- **ADDS** the ATK-backed E2E gate (no behavioral testing existed), the change-impact
  dispatcher, a11y baseline pairing, and mask/ignore regions.

## 3. Two runtimes, one infrastructure

E2E and visual review use **different test libraries** but **one Playwright install,
one `playwright.config.ts`, one DDEV `playwright` service, one surface registry**:

```
codePath/
├── playwright.config.ts        ← one base config (references/visual-review/playwright-base.config.ts)
├── tests/
│   ├── e2e/                    ← ATK-backed behavioral tests   (Task B)
│   └── visual/                 ← Lullabot VR + parity tests    (Task C, D)
```

The split is only at the test-library layer. `playwright.config.ts` carries one
`projects[]` entry per runtime (`e2e-*` `testDir: tests/e2e`, `visual-*`
`testDir: tests/visual`). Each `/setup-*` command appends only its own entry — setup is
idempotent and order-independent.

## 4. Opt-in — a project has zero review surface until set up

Nothing runs implicitly. A project gains visual/E2E review only when a `/setup-*`
command runs (Task B/C/D). Setup is **guided surface/journey discovery**, not generic
auto-seeding — the user curates which URLs and journeys are covered.

- `project_state.md` carries one pointer field — `**Visual Review:** enabled <path>`.
  Absent ⇒ not set up.
- The **surface registry** (`<project>/.visual-review/registry.yml`) records the
  covered surfaces — see `references/visual-review/surface-registry-schema.md`.
- `/review` on a project with no registry runs **zero** new gates and prints
  `no visual-review surfaces configured; run /setup-* to opt in`.
- `/ai-dev-assistant:new` will offer setup as an optional step.

## 5. The change-impact dispatcher — a RECOMMENDER

`/review` step 6 (v4.11.0+) classifies the diff and **recommends** gates — it does not
force them. The user opts in **per task**, once, via a `## Review Gates` block in
`task.md`; the choice is remembered and never re-asked.

- CSS / SCSS / Twig changed → `visual_regression` recommended.
- JS / TS / PHP / YAML changed → `e2e` + `visual_regression` recommended.
- Docs / tests / CI-only → nothing recommended.
- `visual_parity` is **not** part of the opt-in question — it auto-runs (soft) on
  design-implementation tasks (a task with registered parity references).

Forcing a heavy VR/E2E run on every CSS tweak would make users disable the feature;
the recommender model keeps the gates wanted, not resented. Full procedure:
`references/visual-review/change-impact-dispatch.md`. Rule table:
`references/visual-review/change-impact-rules.md`.

## 6. Baseline lifecycle (Task C territory — summarized here)

- **Bootstrap** — the first run on a surface has no baseline; the gate captures one
  loudly, never silently.
- **Loud failure on missing** — a regression run with no baseline fails clearly rather
  than passing vacuously.
- **Reason-required regeneration** — `--update-baselines "<reason>"` is mandatory.
  Legitimate non-code triggers (prod DB refresh, contrib/core update, fixture change)
  are recognized alongside an intentional UI change.
- **`baseline-history.jsonl`** records every regeneration — no silent writes.

## 7. DDEV-first

The gates assume a **DDEV-hosted Drupal site**. `/setup-*` checks for
`<codePath>/.ddev/config.yaml` and the base config reads `DDEV_PRIMARY_URL`. With no
`.ddev/` directory, setup stops with a clear message and points here. A
**bring-your-own-container** runner is supported as an appendix only — set
`PLAYWRIGHT_BASE_URL` to your site URL and ensure a Playwright-capable container; DDEV
is the first-class, documented path.

## 8. What ships when

| Subtask | Ships | Status |
|---|---|---|
| **A — Foundation** | Surface registry schema, change-impact dispatcher in `/review`, gate-audit schema additions, the shared `playwright-base.config.ts` template, this walkthrough | **This release (v4.11.0).** Plumbing only — zero new commands, zero runtime files in any project. |
| **B — ATK E2E** | `/setup-atk`, `/validate:e2e` | Blocked by A. |
| **C — Visual Regression v2** | Reworked `validate-visual-regression` on Lullabot — batch, masks, a11y | Blocked by A. |
| **D — Visual Parity v2** | Reworked `validate-visual-parity` on Lullabot | Blocked by A + C. |

Until B/C/D merge, `/review`'s dispatcher produces a `dispatch_plan` but runs no new
gates — opted-in gates whose subtask has not shipped record `verdict:
"skipped-not-shipped"`. The v3.13.0 `/validate:visual-regression`,
`/validate:visual-parity`, and `/validate:all` commands remain invocable and unchanged
in the interim.

## 9. Pointers

- `references/visual-review/surface-registry-schema.md` — the coverage manifest.
- `references/visual-review/change-impact-rules.md` — diff → gate rule table.
- `references/visual-review/change-impact-dispatch.md` — `/review` step 6 procedure.
- `references/visual-review/playwright-base.config.ts` — shared config template.
- `references/gate-audit-schema.md` v1.2 — `e2e` / `visual_regression` gate_types,
  `dispatch_plan`.
- `references/screenshot-store-schema.md` — the v3.13.0 baseline store (Task C decides
  its fate).
