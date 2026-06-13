# Visual Parity Tests

Committed visual-**parity** checks powered by
[`@lullabot/playwright-drupal`](https://www.npmjs.com/package/@lullabot/playwright-drupal),
Playwright, and `pixelmatch`. Set up by `/ai-dev-assistant:setup-visual-parity`.

> This file is scaffolded by `/setup-visual-parity`. Edit freely — it is a
> normal project file once written.

## Parity vs regression — the difference

| | Visual **regression** (`tests/visual/`) | Visual **parity** (`tests/parity/`) |
|---|---|---|
| Compares the build against | its own committed **baseline** | an **external design reference** |
| Reference lives | in the repo (`*.spec.ts-snapshots/`) | a Figma export, prod URL, or HTML/React template |
| "Truth" updates by | `--update-baselines` (re-capture) | re-exporting the reference + editing `registry.yml` |
| The actionable output | a pixel diff vs the baseline | a **structured CSS-actionable diff** — *which* properties drift |

Parity answers *"does the build match the design intent?"* — not *"did the build
change since last time?"*

## Quick start

```bash
# Run parity for the default viewport (fast iteration):
/ai-dev-assistant:validate:visual-parity

# All viewports:
/ai-dev-assistant:validate:visual-parity --all-viewports
```

Parity also auto-runs (soft) inside `/ai-dev-assistant:review` on
design-implementation tasks — see the change-impact dispatcher.

## Directory layout

```
tests/parity/
├── README.md                  — this file
├── parity-compare.mjs          — the comparison engine (copied by /setup-visual-parity; do not edit lightly)
├── parity-surfaces.json        — per-surface config (build URL, reference type/uri, selectors) — DATA
├── <surface-id>.spec.ts        — one spec per surface; copied VERBATIM (every copy is identical)
└── references/                 — committed static design references (figma / image PNGs)
    └── <surface-id>.png         — one comp per surface

parity-results/                 — GITIGNORED — each run drops a timestamped folder of
                                   <surface>-<viewport>.parity.json + .diff.png artifacts
```

Each `<surface-id>.spec.ts` is a **verbatim** copy — it carries no per-surface data; it
derives its surface id from its own filename and reads `parity-surfaces.json` at run
time. Untrusted registry values never enter spec source.

`tests/parity/` (specs, `parity-compare.mjs`, `references/`) **is committed**.
`parity-results/` is **gitignored** — every run produces a throwaway timestamped
folder; nothing there is a source of truth.

## DO NOT RENAME THE TEST

Every generated spec names its test exactly `'visual parity'` and its file
`<surface-id>.spec.ts`. `parity-compare.mjs` writes its result to
`parity-results/<run>/<surface-id>-<viewport>.parity.json`, which
`visual-parity-gate.sh` merges by that exact name. Renaming the test or the
surface stem breaks the join. If you need a second comparison, use a separate
spec file.

## There is no baseline machinery

Parity has **no committed "truth"** to rotate. A design reference is updated by
re-exporting it (e.g. a fresh Figma PNG) and editing the surface's
`parity_reference` in `.visual-review/registry.yml` — then
`/validate:visual-parity --update-reference-hash` to accept the new file hash.
`/validate:visual-parity` never rewrites a reference.

## The two-layer diff

1. **Coarse pixel diff** (`pixelmatch`, loose tolerance ~`0.05`) — a yes/no
   "something is off" signal. The tolerance is deliberately loose: cross-render
   antialiasing noise would swamp a tight one, and the pixel ratio is *not* the
   actionable signal.
2. **Structured CSS-actionable diff** (`getComputedStyle`) — the real output:
   `{selector, property, build, reference}` rows naming *what* drifted
   (`font-weight 400 vs 500`, `gap 12px vs 16px`). The AI gets a fix list.

Tune the pixel threshold with the `PARITY_MAX_DIFF_RATIO` env var (default
`0.05`).

## CSS-actionable diff is tiered by reference type

| `reference_type` | Reference has a DOM? | CSS diff |
|---|---|---|
| `html-template` / `react-template` / `prod-url` | yes — rendered headless | **Full** — computed styles compared on both sides |
| `figma` / `image` | no — a flat PNG | **build-only** — build-side computed styles only, honestly labelled |

A PNG export has no CSS. For `figma`/`image` references the gate reports the
coarse pixel diff plus the *build's own* computed styles — never a fake
reference comparison. Prefer `html-template`/`react-template` references when
CSS precision matters.

## `compare_selectors`

Each surface's `parity_reference.compare_selectors` in `registry.yml` lists the
elements whose computed styles are compared. Absent → a sensible default set
(`h1`–`h3`, `button`/`.button`/`.cta`, `main`). Keep the list short and
specific to the surface's key elements.

## `react-template` v1 scope

A `react-template` reference must be a **pre-rendered HTML file** (static
export / Storybook build) or a **served URL**. A raw `.jsx`/`.tsx` source path
is skipped with guidance — headless React rendering needs a build step, out of
v1 scope.

## References

- VR/parity workflow: https://camoa.github.io/dev-guides/testing/visual-regression/workflow/
- Playwright: https://camoa.github.io/dev-guides/testing/visual-regression/playwright/
- pixelmatch: https://camoa.github.io/dev-guides/testing/visual-regression/pixelmatch/
- Full walkthrough: `references/visual-parity-walkthrough.md` (in the plugin)
