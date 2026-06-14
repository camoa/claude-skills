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

Every declaration except one **fails open to the framework-neutral floor**: an absent or misnamed block is
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

## The five declarations

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
**Consumer:** `scripts/ensure-registry-preflight.sh` (seed) → `scripts/validate-e2e.sh` via
`/validate:e2e --preflight-cmd` (run). **Not** read from the recipe at gate time — `/setup-e2e` transcribes
the recipe's value into the project's `.visual-review/registry.yml`, and the gate reads it from there.
**Shape** (the value the recipe supplies, written by setup into the registry):
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

## Which recipe carries which declaration

A phase's recipe (key `<phase>/<framework>/<slug>`) carries the declarations its phase consumes:

| Recipe (by phase key) | Declarations it should carry |
|---|---|
| `visual-regression/<fw>/…` | `## Screenshot capture` (1), `## Change-impact globs` (5) |
| `e2e-setup/<fw>/…` | `e2e.preflight_command` (2) |
| `implement/<fw>/…` | `## Routing hints` (3) |
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
