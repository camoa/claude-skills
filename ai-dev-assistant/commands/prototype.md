---
description: "Build a disposable spike to answer ONE design/logic question before committing to a real approach — a runnable terminal program for a state/logic question, or >=2 radically different toggleable variants for a UI/shape question. Trigger: 'spike this', 'prototype this', 'try both approaches', 'quick throwaway test', 'which way should this work', 'test this behavior before building', 'prove this out first'. The output is explicitly throwaway code, isolated from the real build, discarded once it answers the question — never promoted to production. Feeds /design and mechanism-challenge as prose evidence, without editing them."
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: <design-question>
---

# Prototype

Answer ONE design or logic question by building small, disposable, **runnable** code — before
committing to a real implementation. Borrows the `prototype` pattern from mattpocock/skills,
adapted framework-agnostic for AIDA. A prototype is a spike, not a deliverable: it exists to
produce evidence for a decision, then it is discarded.

## Usage

```
/ai-dev-assistant:prototype <design-question>
```

## The one question

Before writing anything, restate the ONE design/logic question being answered, taken from
`$ARGUMENTS`:

> **Question:** <the one question, verbatim or lightly sharpened>

A prototype answers exactly one question. It is not a feature build, not an exploration of
several unrelated problems, and not a first draft of the real implementation. If `$ARGUMENTS`
is vague or bundles multiple questions, ask ONE clarifying question to narrow it to a single,
falsifiable question (e.g., "does approach A handle the concurrent-write case, yes or no") before
building anything.

## Step 0 — Resolve where the spike lives

Run `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parse
`codePath` + its warnings per `references/code-path-detection.md`:

- `code_path_unknown` warning → run the standard detect+confirm flow before proceeding (do not
  guess a location).
- `codePath: null` with no warning (docs-only project) → there is no code tree to anchor a scratch
  dir to; ask the user for a base directory to spike in (defaults to `$PWD`).
- `codePath` set → use it as the base for Step 2.

## Step 1 — Classify the question: logic/state vs UI/shape

- **LOGIC/STATE** — "how should this behave," "does this algorithm handle X," "which state shape
  avoids bug Y," "what happens under race/edge condition Z" → build a runnable terminal program
  (Step 3a).
- **UI/SHAPE** — "how should this look/lay out," "which component structure," "which interaction
  pattern reads better" → build >=2 radically different toggleable variants (Step 3b).

If a question mixes both, split it and prototype the logic/state half first — it usually gates
the UI decision (state shape constrains what the UI can render).

## Step 2 — Build in an ISOLATED, disposable location

All spike files go under **`<codePath>/.prototypes/<slug>/`** — never inside `src/`, `app/`, or
any real build path. `<slug>` is a short kebab-case slug derived from the question. Before using
it in a path, sanitize it: strip/reject any `/`, `..`, or leading `.` so the slug cannot escape
`.prototypes/`.

**Disposable-location choice: a gitignored scratch directory, not a throwaway branch.** A branch
forces a checkout switch, which drops or stashes whatever the current branch is mid-way through —
a spike is frequently run mid-task, and the user should not have to leave the task's working tree
to get an answer. A gitignored directory sits alongside whatever branch is currently checked out,
is inspectable with plain file tools (no git state change), and is trivially deletable with a bare
`rm -rf` — it never touches git history, never needs a merge or a branch cleanup, and can still
`require`/`import` real project modules for a realistic runnable spike when that's useful.

Ensure it's disposable at the git level — append `.prototypes/` to `.gitignore` if it isn't
already ignored; the working-tree ignore takes effect immediately, and unlike `/worktree`'s
gitignore-verify step, there is no commit to make (a gitignored scratch dir never enters git
history):

```bash
git -C "<codePath>" check-ignore -q ".prototypes/" || echo ".prototypes/" >> "<codePath>/.gitignore"
```

**Hard rule:** never commit spike files, never open a PR from `.prototypes/`, never reference a
path under `.prototypes/` from `research.md`, `architecture.md`, or `implementation.md` as if it
were real code. It is evidence, not a deliverable.

## Step 3a — Logic/state path: one runnable terminal program

Write a single small entry-point program under `<codePath>/.prototypes/<slug>/` (pick the
project's language — `spike.js`, `spike.py`, `spike.php`, `spike.rb`, ...) that:

- Demonstrates the specific behavior in question with realistic inputs
- Runs standalone from the terminal (`node spike.js`, `python spike.py`, `php spike.php`, ...) —
  no test framework, no build step, no UI
- Prints its result/verdict to stdout so the answer is directly observable, not inferred

Run it (Bash). Show the actual output — the answer comes from what ran, not from what the code
is expected to do.

## Step 3b — UI/shape path: >=2 radically different variants, one entry point

Scaffold >=2 variants that are **radically different from each other** — different layout
structure, different interaction model, or different component decomposition, not a color/spacing
tweak of the same shape. Wire them behind ONE toggleable entry point so they can be flipped
between without editing code:

- `<codePath>/.prototypes/<slug>/index.html` with a `?variant=a|b|c` switch, or
- `<codePath>/.prototypes/<slug>/{variant-a,variant-b,...}/` + one router/switcher entry file

Render or run each variant and describe (screenshot only if a browser tool is already available
and genuinely useful) what concretely distinguishes them — not just "variant B feels nicer," but
the structural difference that drives the recommendation.

## Step 4 — State the answer, then discard

Every `/prototype` run ends with an explicit answer block:

```markdown
## Prototype answer

Question: <the one question>
Answer:   <the concrete finding the spike produced, e.g. "the reducer shape handles the
           concurrent-write case correctly; three independent stores lose the second write">
Evidence: <the terminal output / variant comparison that supports it>

This code is throwaway. It stays in .prototypes/<slug>/, is NOT wired into the real build, and is
NOT to be promoted or merged as-is. If the answer implies real work, that work gets designed
properly next via /design -> /implement (rebuilt clean, not lifted from the spike).
```

Never say "promote this to production," "merge this in," or "keep this file as-is." If a spike is
worth keeping as a reference, copy the *idea* forward — the real implementation is authored fresh
in `/design` -> `/implement`, under the framework's normal SOLID/DRY/TDD gates, not by graduating
throwaway code.

## How this feeds the rest of the lifecycle (pointer only)

`/prototype` is a pre-`/design` (or mid-task, when a question surfaces during `/implement`)
exploration step. It does not edit `research.md`, `architecture.md`, or run any validation gate.
It hands its answer forward as **prose evidence** for two existing surfaces — neither of which
this command touches:

- **`/design`** — when architecture commits to the approach it settled, cite the prototype's
  answer as grounding (paste the answer block, or summarize it, into the design conversation).
- **Mechanism-challenge** (`references/mechanism-challenge.md`) — a prototype's finding can serve
  as tier-3 (or corroborate tier-1/2) evidence when a stated mechanism is being challenged. It is
  empirical evidence to weigh, not a substitute for the resolver cascade, and it does not itself
  write to `_mechanism-challenge.json`.

Neither integration is automatic — the user or a later command carries the answer forward by
hand; `/prototype` only produces the evidence.

## Cleanup

Spikes are meant to accumulate briefly, not indefinitely. Once a question is answered and its
answer has been carried forward (or the direction is abandoned), delete the directory:

```bash
rm -rf "<codePath>/.prototypes/<slug>/"
```

`.prototypes/` as a whole is never expected to be long-lived; `rm -rf "<codePath>/.prototypes/"`
between unrelated spikes is safe and expected.

## Error cases

| Scenario | Behavior |
|---|---|
| No design question given | Ask for one; refuse to build until a single question is stated |
| Question bundles logic and UI concerns | Split it; prototype the logic/state half first |
| `codePath` unknown (`code_path_unknown` warning) | Run detect+confirm before writing any file |
| `codePath` docs-only | Ask the user for a scratch base directory (default `$PWD`) |
| User asks to keep/merge/wire in the spike | Refuse; redirect to `/design` -> `/implement` for a properly-authored version |

## Related

- `/ai-dev-assistant:design` — where a prototype's answer gets designed properly, if it implies
  real work
- `/ai-dev-assistant:pattern` — pattern recommendation without writing runnable code; use
  `/prototype` when a recommendation alone isn't enough evidence to decide
- `/ai-dev-assistant:worktree` — an isolated git worktree for real, mergeable work; NOT what this
  command uses (see Step 2's disposable-location rationale)
- `references/mechanism-challenge.md` — the mechanism-challenge contract this command can feed
  with empirical evidence, without writing to its audit file
