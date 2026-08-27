# Framework resolution: how a project's stack is identified and what happens when nothing supports it

Until v5.32.0 the set of frameworks this plugin could recognize was a property of a plugin release.
`scripts/detect-frameworks.sh` held one hand-written block per framework (drupal, nextjs,
claude-code-plugins) and returned `[]` for everything else. dev-guides published complete four-phase
process-recipe families for `go` and `php-cli` while detection returned `[]` on both: the recipes
existed and no project could be routed to them. The fallback made it worse, not better. The operator
was asked to type a framework id as a free token with no allowlist, so `golang` instead of `go`
resolved no recipe at any phase and explained nothing about why.

Two fixes were considered and rejected. Moving the list into a table in the same script is still a
plugin release per framework. Declaring a detection-signal block in each recipe still requires
someone to author an entry before a project is recognizable at all. Both keep the same property:
a project is invisible until a human wrote its entry somewhere.

A model reading a repository needs no entry. So identification moved to the model, and no framework
list exists anywhere in the plugin. Two scripts supply facts and hold no opinions:

| Script | Answers | Holds a framework list |
|---|---|---|
| `scripts/framework-evidence.sh <codePath>` | what is in the repository | no |
| `scripts/framework-support.sh <slug>` | what the dev-guides catalogs carry for a slug the model already named | no |

This doc is the cascade that runs between them: identify, look up support, ask the user, research the
web, record once. `references/recipe-resolution.md` is the sibling protocol for resolving one recipe
at one phase boundary; this doc is what decides which framework that protocol is even asking about.

## Step 1: identify (the model, not a script)

Run `scripts/framework-evidence.sh "<codePath>"`. It returns one JSON object:

| Field | What it is |
|---|---|
| `top_level[]` | the repository's top-level entries |
| `extensions[]` | an extension histogram over a bounded walk, most frequent first |
| `readable_root_files[]` | root files under 256 KiB, so you know what is cheap to Read |
| `nested_project_dirs[]` | subdirs holding `composer.json`, `package.json`, `go.mod` or `pyproject.toml` |

It prunes `.git`, `node_modules`, `vendor`, `.ddev`, `dist`, `build`, `.next` and `target`, so the
histogram describes this project rather than its dependencies. `status:"unknown"` with a `reason`
means the arguments were unusable (`code_path_missing_or_not_a_directory`, `jq_missing`), which is
not the same fact as a repository with nothing in it.

Then Read whichever root files matter and name the framework. There is no allowlist, so any slug is
sayable. More than one is allowed: a monorepo legitimately yields several, and each gets its own
support lookup and its own entry in the record.

**Record the evidence you actually used.** Each identified framework carries `evidence[]`, the list
of files you Read and the signals you took from them (`composer.json requires drupal/core-recommended`,
`go.mod module line`). Identification without evidence is an assertion, and a later phase reading the
record has no way to tell a read from a guess.

**Thin or contradictory evidence is `undetermined`, not a guess.** A repository with a `package.json`
carrying one dev dependency and 400 `.md` files is not a Next.js project because `package.json`
exists. Say `undetermined`, record what you saw, and let the cascade continue with no framework
rather than routing every phase to a stack the project is not built with. A wrong slug is worse than
no slug: it resolves recipes that confidently describe the wrong work.

**A non-empty `nested_project_dirs[]` may mean the codePath is wrong.** A repository whose root holds
only a `docroot/` or `web/` containing the real manifest is usually a signal that `codePath` points
one level too high, not that the framework is unclear. Check the nested dir before concluding
anything about the stack, and offer `/set-code-path` when the nested dir is plainly the project.

## Step 2: look up support

For each identified framework run `scripts/framework-support.sh <slug>`. It is handed the slug you
decided on and reports what the three dev-guides catalogs carry. Exit is always 0: the verdict is the
answer, not the exit code.

| Verdict | Means | Observed today |
|---|---|---|
| `full` | process recipes and guides both found | `drupal`: 6 phases, 60 guide topics |
| `partial` | one of the two found | `go`, `php-cli`: recipes for design/implement/research/review, guides `none`. `nextjs`: guides found (4 topics), process recipes `none` |
| `none` | neither found, both catalogs readable | `rust` |
| `unknown` | a catalog could not be read | uncached index, `jq` missing |

Use what exists, per class:

- **`process_recipes`** drives each phase. `phases[]` is the definitive per-phase yes or no. Hand each
  phase to `references/recipe-resolution.md` as usual; that protocol has not changed.
- **`guides`** feeds the guides preflight. `topics[]` is what the dedicated-guide match draws from.
- **`agentic_recipes`** is judged by you, not by the script. Its `status` is **always** `unknown`,
  with reason `catalog_carries_no_framework_key`. That index genuinely has no framework field:
  framework-ness appears only in prose `when-to-use` text. The script returns `candidates[]`, the
  lines mentioning the slug, for you to judge, and never reports `none`, because "cannot be queried
  this way" and "there are none" are different facts. An empty `candidates[]` is not evidence of
  absence. Gate whatever you adopt through `references/agentic-recipe-resolution.md`.

**`partial` is normal and usable.** `go` with four process-recipe phases and no guides is a routable
project, not a gap. Do not treat a `partial` verdict as a reason to skip to step 3 for the classes
that did resolve; the gap is per class, and step 3 fires only for the missing one.

**`unknown` is never recorded as "nothing exists".** An unreadable or uncached catalog means the
question went unanswered. Recording it as absence turns a cache miss into a permanent conclusion that
later phases read as settled. Surface it, retry the catalog if you can, and record `unknown`.

## Step 3: gap, so ask the user for another source

When a needed class is missing, ask once whether the user has it somewhere else: a local filesystem
path, a URL, another repository. Two mechanisms already exist and this cascade uses them rather than
inventing a third:

- `project_state.md` carries a `**Local Guides Path:**` line, surfaced by
  `scripts/project-state-read.sh` as `localGuidesPath` (`null` when absent). A local guides tree goes
  here.
- Process-recipe source order is already repo-local, then machine-local, then dev-guides, per
  `references/recipe-resolution.md`. A user-supplied recipe becomes a `local` source and is recorded
  in `project_state.md`, so the next phase run short-circuits.

**Record the answer durably, including a decline.** An unrecorded "no, I don't have one" is asked
again at the next phase, and then at the next task. The decline belongs in the record (step 5) as an
`unresolved[]` entry, so the cascade knows it already asked.

Ask once per gap, not once per phase. In an unattended run do not prompt at all: record the gap and
continue, exactly as the attended-mode gate in `references/recipe-resolution.md` does.

## Step 4: still a gap, so research the web

This is the last resort and it produces something weaker than the three steps above. Web-researched
method has unverified provenance: nobody reviewed it, it is not versioned with the catalog, and it
was assembled for this one run.

So it is tagged `verified: false` and surfaced for an explicit human go-ahead before it is followed,
which is the same gate the plugin already applies to any `local`, `machine-local` or researched
recipe body (`references/recipe-resolution.md` step 4). The execute-or-halt decision stays the
orchestrator's.

Record it as what it is. `method_source: web-research` in the record below is not interchangeable
with `process-recipe`; a reviewer reading the record should be able to tell that a phase followed
something assembled from a web search rather than a published recipe, without re-deriving it.

## Step 5: record once, read by every phase

The outcome lands in `<task>/_framework.json`, and the identified slugs go into the flat
comma-separated `**Frameworks:**` line in `project_state.md` (the format
`scripts/project-state-read.sh` parses into `frameworks[]`).

| Field | Contents |
|---|---|
| `frameworks[]` | one entry per identified framework |
| `frameworks[].slug` | the slug handed to `framework-support.sh` |
| `frameworks[].confidence` | `high` / `medium` / `low` / `undetermined` |
| `frameworks[].evidence[]` | the files Read and the signals taken from them |
| `frameworks[].support` | the `verdict` plus the three per-class statuses from step 2 |
| `frameworks[].method_source` | one of `process-recipe`, `guides`, `user-supplied`, `web-research`, `none` |
| `identified_by` | `model` (with the evidence script named), or `recorded` on a re-read |
| `cascade_step_reached` | 1 to 5, so a run that stopped early is legible |
| `unresolved[]` | each gap that survived the cascade, including a user decline and its reason |

**Idempotent.** Later phases read the record instead of re-identifying. The cascade re-runs only when
the record is absent or the operator asks for it. Re-identifying per phase would cost a repository
walk per phase boundary and, worse, could yield a different answer at step 3 than the one the user
already answered.

An `undetermined` framework is still recorded. A record saying the stack could not be determined and
naming what was read is a different artifact from no record at all, and only the first stops the next
phase from repeating the same inconclusive walk.

## How the outcome guides each stage

Every phase reads `_framework.json` and `frameworks[]` rather than re-deriving. What each does with
it, limited to what the phases already do today:

| Phase | With `method_source: process-recipe` | With `partial` or `none` support |
|---|---|---|
| `research` | resolves the `research` recipe per `recipe-resolution.md` and injects the body into `prior-art-researcher` | runs the stack-neutral prior-art flow, and the internal prior-art pass over the project's own record is unaffected |
| `design` | resolves the `design` recipe; `method_fit` is assessed and recorded as usual | drafts against the neutral architecture principles (SOLID, DRY, business logic out of the UI layer) with no stack specifics |
| `implement` | resolves the `implement` recipe, so `## Preconditions` and `## Routing hints` can fire | no `## Preconditions` block exists, so the verdict is `undeclared`, which is not `met` |
| `review` | resolves the `review` recipe, so `## Code-quality extensions` and `## Change-impact globs` union onto the neutral floor | the neutral extension floor and the shipped change-impact rules classify alone |

A `method_source` of `user-supplied` or `web-research` changes the trust posture, not the routing:
the body is `verified: false`, so it is surfaced for go-ahead before it is followed, and the phase
proceeds identically once the operator agrees. `method_source: none` means the phase runs its
framework-neutral floor, which is a valid outcome and is recorded rather than left silent.

## See also

- `references/recipe-resolution.md`: resolving one process recipe at one phase boundary, including the
  source order, the trust model, and the ask-user miss
- `references/recipe-interface.md`: what a resolved recipe body may declare so the gates can act on it
- `references/agentic-recipe-resolution.md`: gating a capability recipe, which is what the
  `candidates[]` from step 2 feed into
- `scripts/framework-evidence.sh`, `scripts/framework-support.sh`: the two fact-supplying scripts
- `scripts/project-state-read.sh`: emits `frameworks`, `codePath`, `localGuidesPath`, `processRecipes`
