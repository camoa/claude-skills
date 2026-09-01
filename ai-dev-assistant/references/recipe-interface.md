# Recipe interface: what a resolved recipe body may declare

`recipe-resolution.md` is the **transport** contract — how a generic phase finds, trusts, and injects a
recipe body. This doc is the **content** contract — what that body may declare so the plugin's gates can
act on it. The two are siblings: resolution gets the body into the run; this interface says what the body
must contain to drive each gate.

A recipe is plain markdown. The plugin never executes it as code — the gate commands **grep the body for a
fixed heading and parse a fixed field shape** out of the block beneath it. So the headings and field names
below are a literal contract: a recipe that misspells `## Screenshot capture` as `## Screenshots`, or
`code_quality_extensions` as `quality_extensions`, is **silently ignored**.

## Failure posture (read this first)

Every declaration except two **fails open to the framework-neutral floor**: an absent or misnamed block is
not an error — the gate just runs its stack-neutral default (no custom capture, neutral extension floor,
neutral globs, generic routing buckets). This is deliberate agnostic posture, but it means a typo degrades
silently to "did nothing stack-specific" rather than failing loudly. The recipe author is responsible for
the exact spelling; this contract is the source of truth for it.

| Declaration | Posture on absence |
|---|---|
| `e2e.preflight_command` | **fail-closed-ish** — seeded into project config by `/setup-e2e`; a declared-but-failing command (non-zero exit) **fails the e2e gate** |
| `## Screenshot capture` | fail-open — native Playwright capture |
| `## Code-quality extensions` | fail-open — neutral extension floor only |
| `## Change-impact globs` | fail-open — shipped neutral floor only |
| `## Routing hints` | fail-open — agent's generic role buckets |
| `## Preconditions` | **fail-closed** — an unmet precondition halts the phase; an absent block is recorded `undeclared`, never `met` |

## The seven declarations

### 1. `## Screenshot capture` — phase `visual-regression`
**Consumer:** `commands/setup-visual-regression.md` (the `## Step 7` capture-method substitution).
**Shape:** a block with two lines plus a label. When present, the setup command injects these into the
generated `<id>.spec.ts` instead of the native capture, and records `captured_by` on the surface.
```markdown
## Screenshot capture
screenshot_import: <import statement the spec needs>
screenshot_capture: <the capture call the spec runs>
captured_by: <method label recorded on the surface; e.g. axe-playwright>
```
Absent ⇒ native Playwright capture; `captured_by: playwright`.

### 2. `e2e.preflight_command` — phase `e2e-setup`
**Consumer:** `scripts/validate-e2e.sh` via `/validate:e2e --preflight-cmd` (run). **Not** read from the
recipe at gate time — the gate reads it from the project's `.visual-review/registry.yml`, where setup seeds
it. It is seeded two ways, both idempotent:
- **Fresh setup (recipe-in-place):** `/setup-e2e` resolves and follows the `e2e-setup` recipe; the recipe's
  own install/scaffold step writes `e2e.preflight_command` into the registry (setup-e2e.md:45 — there is no
  separate transcription pass).
- **Backfill (pre-seam projects):** `scripts/ensure-registry-preflight.sh <registry> <cmd>` inserts the field
  into an existing registry that predates the seam. It is invoked only from `/upgrade-project`'s "E2E preflight
  seam" gap (upgrade-project.md:53), which resolves the `e2e-setup` recipe, reads its declared
  `preflight_command`, and passes it in. The helper no-ops when the field is already present.

**Shape** (the value the recipe supplies, written into the registry by either path above):
```yaml
e2e:
  preflight_command: "<stack-setup-command>"
```
A non-zero exit of the command **fails the e2e gate**; its output is captured into `preflight_warnings`.
Absent ⇒ no preflight runs. The **field** is generic; the **value** is the recipe's stack-specific command.

### 3. `## Routing hints` — phases `implement` (and any plan-mode guides match)
**Consumer:** `commands/implement.md` Stage 2b — passed as `routing_hints[]` to the `guides-matcher` agent
in `mode: "plan"`. Helps map planned file paths to this stack's conventions.
```markdown
## Routing hints
routing_hints:
  - <path-or-convention → guide/surface hint>
  - <…>
```
Note: at implement preflight the recipe is usually **not yet resolved**, so these are typically absent and
the agent's neutral role buckets handle generic conventions. This is the softest of the five.

### 4. `## Code-quality extensions` (`code_quality_extensions`) — phase `review`
**Consumer:** `commands/review.md` step 5a. A JSON list of file extensions **beyond** the framework-neutral
language floor (`.php .js .mjs .cjs .ts .tsx .vue`) that count as "code" for change-scoping. Review reads
this from the **same recipe body already resolved at step 5.0** (no second resolution) and unions it onto
the floor.
```markdown
## Code-quality extensions
code_quality_extensions: [".module", ".inc", ".theme", ".install"]
```
Absent / empty ⇒ neutral floor alone (an undeclared framework file type is simply never scoped into the
change-quality gates — agnostic-floor posture).

### 5. `## Change-impact globs` — phase `review`
**Consumer:** `commands/review.md` step 6 reconstructs a JSON file from this declaration each run and passes
it to `scripts/change-impact-classify.sh --rules-from`, which **unions** it onto the shipped neutral floor
(`references/visual-review/change-impact-rules.json`). The classifier is a **recommender** — it maps changed
files to gates a change could justify; it never blocks. Gates are unioned across every matching rule, so rule
order is irrelevant.
**Shape** the classifier parses (`{ rules: [ {glob, gates[]} ], default_gates: [] }`):
```markdown
## Change-impact globs
rules:
  - { glob: "**/*.theme",      gates: ["visual_regression"] }
  - { glob: "**/templates/**", gates: ["visual_regression", "visual_parity"] }
# optional: gates applied to any file that matched no rule
default_gates: []
```
Absent / malformed ⇒ the shipped neutral floor (stylesheet / plain-script / markup extensions) classifies
alone; the recipe globs are simply not merged (a warning is recorded, the run never fails).

### 6. `## Preconditions` — phase `implement`
**Consumer:** `scripts/preconditions-check.sh`, run by `commands/implement.md` step 6b.

This is the one declaration a recipe can use to say *the phase cannot start yet*, and the only one besides
`e2e.preflight_command` that fails closed. It exists because a recipe could already state a precondition in
prose and the engine had no way to read it: observed live, a Drupal implement recipe required a configured
PHPUnit runner, the project had none, and the phase proceeded to improvise a runner install by hand rather
than route to the tool that owns it. The prose was injected verbatim and parsed by nothing.

```markdown
## Preconditions
preconditions:
  - id: test-runner
    what: a runner whose failure the RED step can observe
    check: test -x vendor/bin/phpunit
    owner: code-quality-tools:setup
```

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | stable slug; the entry boundary, so an entry without it is dropped |
| `what` | no | one line the operator reads when it is unmet |
| `check` | no | the command that decides. Absent ⇒ `unknown`, never `met` |
| `owner` | no | `<plugin>:<command>` that satisfies it. Absent ⇒ the phase's default owner table |

**`check` is exec'd directly, never through a shell.** A recipe body is untrusted upstream data, so the
value is split on whitespace and run as argv. Shell metacharacters are therefore not syntax, and a check
containing one is refused outright as `unknown / unsafe_check_shape` rather than run to mean something its
author did not read. Write `test -x vendor/bin/phpunit`, not `command -v phpunit || exit 1`. Exit 127 is
recorded `unknown / check_command_not_found`, because a missing checker says nothing about the precondition.

**Four verdicts, and `undeclared` is not `met`.** `met` (every entry ran and passed), `unmet` (at least one
failed — halts), `unknown` (a block is present but something could not be run), `undeclared` (no block).
A caller that folds `undeclared` into `met` has re-created the defect this declaration closes: the recipe
declared nothing, so nothing was checked, and that is a different fact from everything passing.

### 7. `## Oracle files` — phase `implement`
**Consumer:** `scripts/oracle-globs.sh`, run by `commands/implement.md`'s build-critique rung (step 2c) to
supply `repair-accept-check.sh --test-globs`. The tamper guard (`scripts/wo-oracle-check.sh`) reads the
same block through its caller's `--oracle-files` file, not through this parser.

The recipe already writes this block: an H2, and under it the first fenced `json` block, a top-level array
of flat objects with the key set `type, globs, changes, oracle_class, severity`. The consumer selects the
row whose `type` is `test_delete` and takes its `globs`; that is where the test-file globs come from, so a
caller-supplied narrow list cannot satisfy the motion gate on the record while classifying nothing.

````markdown
## Oracle files
```json
[ { "type": "test_delete", "globs": ["**/tests/**/*Test.php"], "changes": ["D"], "oracle_class": "test-delete", "severity": "halt" } ]
```
````

**Parse the JSON, never the markdown table beside it.** The table is a hand-maintained copy for a human
reader; nothing checks the two agree, and when they differ the JSON is what the guard consumed. **Take
`globs` only**; `changes` is the tamper guard's concern. A recipe without the block is an honest
"no oracle declared" state: the consumer reports origin `convention` when the caller supplied a fallback
set and `undetermined` when it did not, never an empty list read as "no test files changed". Globs are
matched with `**` semantics by every kernel (`scripts/lib/glob-to-regex.sh`), so `**/tests/**/*Test.php`
reaches `tests/src/Kernel/FooTest.php`.

## Which recipe carries which declaration

A phase's recipe (key `<phase>/<framework>/<slug>`) carries the declarations its phase consumes:

| Recipe (by phase key) | Declarations it should carry |
|---|---|
| `visual-regression/<fw>/…` | `## Screenshot capture` (1), `## Change-impact globs` (5) |
| `e2e-setup/<fw>/…` | `e2e.preflight_command` (2) |
| `implement/<fw>/…` | `## Routing hints` (3), `## Preconditions` (6), `## Oracle files` (7) |
| `review/<fw>/…` | `## Code-quality extensions` (4), `## Change-impact globs` (5) |

The key is `<phase>/<framework>/<slug>`; the **phase segment**, not the recipe's filename, decides which
declarations apply. A declaration belongs in the recipe whose phase consumes it — e.g. `## Routing hints`
goes in the `implement`-phase recipe (consumed at implement preflight), never in the `review` one. Run the
linter (below) against a recipe at its declared phase to confirm. `## Change-impact globs` legitimately
appears in both the `review` and `visual-regression` recipes; the classifier unions all matching rules, so
that duplication is harmless.

## Checking a recipe is complete (the linter)

Because every declaration fails open silently, "did I spell it right / did I declare it at all" is not
observable at gate time. `scripts/recipe-declarations-audit.sh` is the deterministic linter that makes it
observable — a recipe author (or CI in the dev-guides repo) runs it against a recipe body and sees, per
phase, which declarations are present vs absent:

```
scripts/recipe-declarations-audit.sh --body <recipe.md> --phase review --framework drupal
# → {"phase":"review", "declarations":[…], "summary":{"expected":2,"present":1,"absent_recommended":1}}
```

It is **informational** (exit 0 even when recommended declarations are absent — absence is a valid
agnostic-floor choice, not a failure) and emits stable JSON for CI. `recommended:true` declarations that are
`absent` are the ones worth a second look. This is the answer to "how does the dev-guides side know what to
declare": run the linter, fill until the recommended set is present.

## Keeping this contract honest

These declaration tokens are grepped by the consumers named above. The drift test
`tests/recipe-interface-spec.sh` asserts that every token a consumer parses is documented here, so a parser
change can't silently add an undocumented declaration. `tests/recipe-declarations-audit-spec.sh` pins the
linter's per-phase table to the same set. If you add a declaration to a consumer, update this doc, the
linter table, and both tests in the same change.

## See also

- `references/recipe-resolution.md`: the transport/resolution protocol (find, trust, inject the body)
- `references/visual-review/surface-registry-schema.md`: the project-config shape `e2e.preflight_command`
  (2) and `auth_context` are written into by setup
- `scripts/change-impact-classify.sh`: the `--rules-from` parser for `## Change-impact globs` (5)
