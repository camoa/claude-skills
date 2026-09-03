# Gate Hardening Prompts v1.10

**Introduced:** ai-dev-assistant v4.0.0 (v1.0); compressed v4.0.2 (v1.1, additive); v4.1.0 (v1.2, additive — adds `review-gate-fail` + `review-summary` for the new `/review` command); v4.12.0 (v1.3, additive — adds `e2e-gate-fail`); v4.13.0 (v1.4, additive — adds `visual-regression-gate-fail`); v4.14.0 (v1.5, additive — adds `visual-parity-gate-fail`); v5.20.0 (v1.6, additive — `review-summary` grows the `## Standards` / `## Spec` two-axis blocks + `spec_verdict_line` substitution, M2; also documents that `{{gates_run_table}}` excludes the `name:"spec"` entry and defines the `{{spec_verdict_line}}` format, fixing M1's spec double-render risk; template literal unchanged beyond the two-axis block additions); v5.26.0 (v1.7, additive — adds `prior-art-ask` for the internal prior-art search); v1.8 (additive — `review-summary` gains `{{spec_provenance_line}}` under `## Spec`, surfacing `criterion-provenance.sh`'s owner/designer/unrecorded counts and naming the designer-authored and unrecorded criteria; informational only, never feeds `{{spec_verdict_line}}`'s pass/fail; `{{mechanism_unresolved_line}}` under `## Standards`, GAP G's unresolved-mechanism count, was already documented here as of the prior commit on this branch and is unchanged by this edit)); v5.49.0 (v1.9, additive — `critic-dispatch` gains `{{methodology_block}}`, the test-first material the build was held to, rendered for all three lenses including `meets-ac`; no existing template or placeholder changed); v5.50.0 (v1.10, additive — `critic-dispatch` gains `{{design_block}}`, the component's design body, rendered for all three lenses; no existing template or placeholder changed).
**Owner:** This reference; consumed by command bodies.
**Consumers:** `commands/research.md` (pre-analysis + coverage-mapping), `commands/complete.md` (skill-review + plugin-validate), `commands/review.md` (review-gate-fail + review-summary, v4.1.0+), `hooks/phase-command-bypass.sh` (phase-command-bypass acknowledgment).

The framework's hardened gates use **literal mandated wording** for user prompts, and since v5.30.1 that wording is produced by `scripts/prompt-render.sh` rather than transcribed by whoever is running the command. Literal wording is the rationalization-resistance mechanism; rendering is what makes it hold, because a template that a model retypes comes out close rather than identical, and close is where the internal vocabulary gets back in. Authoring rules forbid paraphrase, reorder, pre-answer, and truncation, and rule 7 forbids retyping altogether.

The 2 deterministic gates (`dev-guides-load`, `playbook-load`) have NO user prompts; no templates here.

**Cross-file equivalence (v4.1.0+):** for templates also inlined in command bodies (`review-gate-fail`, `review-summary`), the literal block here MUST be byte-identical to the inline literal in the consuming command. Verified by `tests/gate-prompts-vs-inline.sh`.

## Templates index

| ID | Fired by | Substitutions | Default option |
|----|----------|--------------|----------------|
| `pre-analysis-decision-epic-candidate` | `/research` after `analysis-agent`, when `decision == "epic_candidate"` | `signals_used`, `reasoning`, `children_list` | **none** — no default |
| `pre-analysis-decision-keep-flat` | `/research` after `analysis-agent`, when `decision == "keep_flat"` | `signals_used`, `reasoning` | `[y]` |
| `pre-analysis-decision-insufficient-info` | `/research` after `analysis-agent`, when `decision == "insufficient_info"` | `signals_used`, `reasoning` | `[y]` |
| `coverage-mapping-fail` | `/research` end-of-phase on `verdict: fail` | `missing_questions` (multi-line) | `[a]` |
| `skill-review-decision` | `/complete` on `skills/*/SKILL.md` staged change | `skills_reviewed`, `findings` | **none** — user MUST pick |
| `plugin-validate-decision` | `/complete` on plugin file staged change | `plugins_validated`, `findings` | **none** — user MUST pick |
| `dev-guides-preflight` (v1.7+) | `/research`, `/design`, `/implement` before guides load | `task_name`, `methodology_floor`, `matched_domain_guides` | `[c]` |
| `scope-contract-offer` (v1.7+) | `/research`, `/design`, `/implement` when a scope contract is absent | `task_name`, `level` | `[n]` |
| `prior-art-ask` (v1.7+) | `/research` before the internal prior-art search | `project_name` | **none** — an unanswered ask is recorded as unasked |
| `phase-command-bypass-acknowledge` | `/audit-status` listing tasks with `_phase-command-bypass.json` | `artifact_written`, `phase_command_active`, `fired_at` | `[a]` |
| `review-gate-fail` (v1.2+) | `/review` end-of-phase on any hard-block-gate `fail` | `failed_count`, `gates_failed_verbatim` | **none** — user MUST pick |
| `review-summary` (v1.2+; two-axis v1.6+; provenance v1.8+) | `/review` end-of-phase on any verdict | `task_name`, `mode`, `overall_verdict`, `pr_ready`, `gates_run_table`, `mechanism_unresolved_line`, `spec_verdict_line`, `spec_provenance_line`, `audit_path`, `pr_body_line_or_empty` | (no prompt; informational) |
| `e2e-gate-fail` (v1.3+) | `/validate:e2e` on `verdict: fail` | `failed_count`, `failed_test_list`, `report_path` | (no default; options listed) |
| `visual-regression-gate-fail` (v1.4+) | `/validate:visual-regression` per failed surface | `surface_id`, `viewport`, `diff_percent`, `diff_pixels`, `diff_path` | `[c]` |
| `visual-parity-gate-fail` (v1.5+) | `/validate:visual-parity` per failed surface | `surface_id`, `viewport`, `diff_percent`, `css_diff_mode`, `css_diff_count`, `css_diff_list`, `diff_path` | `[c]` |
| `critic-dispatch` (v5.44.0+; `methodology_block` v1.9+; `design_block` v1.10+) | `/implement` build-critique rung and `work-order-critique` step 4, once per critic | `lens`, `worktree`, `range`, `files`, `component`, `acceptance_criteria` (multi-line), `design_block` (multi-line, ALL three lenses), `recipe_block` (multi-line, empty for `meets-ac`), `methodology_block` (multi-line, ALL three lenses), `output_path` | (no prompt; the whole dispatch) |

## Template authoring rules

1. **Literal text** — exactly as written, including punctuation, capitalization, line breaks
2. **Placeholders** — only `{{snake_case_marker}}` substitutions allowed
3. **No paraphrase** — framework refuses to "translate" or "soften"
4. **No pre-answer** — framework refuses to add "I think the answer is X" before the prompt
5. **No reorder** — option lists ([y]/[n]/[s] etc.) preserve order
6. **No truncate** — even on long content, framework shows verbatim agent output (per show-not-summarize)
7. **Rendered, never retyped (v1.7+)** — a command calls `scripts/prompt-render.sh <template-id> key=value …` and shows the user exactly what the script printed. It does not transcribe a template body into its own prose, and it does not describe the wording inline.

**Why rule 7 exists.** Rules 1–6 were the whole mechanism until v5.30.1 and they are not sufficient. On the first live run after `dev-guides-preflight`, `scope-contract-offer`, and `prior-art-ask` were written, both prompts that fired were composed fresh. One asked a person which section was missing from which file and named a numbered phase, which is what its template replaces. Nothing had malfunctioned: `dev-guides-preflight` was never wired at all — three command bodies still described the two groups inline with different labels than the template uses — and `scope-contract-offer` was cited correctly and paraphrased anyway.

An instruction to reproduce text exactly, addressed to a model, produces text that is close. Close is the failure: the labels shift, the explanation gets dropped as redundant, and the internal vocabulary the template exists to keep out comes back in through the improvised half. The renderer removes the transcription step. `tests/prompt-template-spec.sh` checks that each of these prompts is rendered rather than worded, and that a render is the file's body character for character.

## Template ID: `pre-analysis-decision-epic-candidate`

The pre-analysis verdict was one template with three `{{#if decision == ...}}` branches
until v5.30.7. The renderer substitutes `{{key}}` and evaluates nothing, so a live run
printed all three branches plus the literal `{{#if}}` and `{{/if}}` markers to a person,
who then had to be told which block applied to them. There is no template language here
and there should not be one: a template is a body that gets filled and shown. One verdict,
one template, rendered whole. The caller picks the ID from `decision`.

```
Pre-analysis verdict: epic_candidate
Signals fired: {{signals_used}}

Agent reasoning (verbatim):
{{reasoning}}

Proposed children:
{{children_list}}

Create as epic with these children?
[y]es — convert to epic via /migrate-to-epic
[n]o flat — proceed as flat task
[s]tandard — show edit list of proposed children
```

## Template ID: `pre-analysis-decision-keep-flat`

```
Pre-analysis verdict: keep_flat
Signals fired: {{signals_used}}

Agent reasoning (verbatim):
{{reasoning}}

Verdict recorded as keep_flat. Proceed as flat task.

[y]es — proceed as flat (default)
[n]o — abort and re-evaluate
```

## Template ID: `pre-analysis-decision-insufficient-info`

```
Pre-analysis verdict: insufficient_info
Signals fired: {{signals_used}}

Agent reasoning (verbatim):
{{reasoning}}

Agent had insufficient context. Verdict recorded as insufficient_info. Proceed as flat task with the option to re-run pre-analysis after research.

[y]es — proceed as flat
[n]o — abort
```

## Template ID: `dev-guides-preflight`

Cited by `/research` step 3 since v4.10.0 and never written until v5.30.0. A run that
went looking for it found nothing and composed its own wording, which is how a step
number reaches a person who has no way to know what step 3 is.

```
Guides for {{task_name}}

Always loaded:
{{methodology_floor}}

Matched to this task:
{{matched_domain_guides}}

[c]ontinue with these (default)
[a]dd — search the catalog again for more
[n]one — skip guide loading
```

## Template ID: `scope-contract-offer`

Offered by `/research`, `/design`, and `/implement` when a scope contract is absent.
`{{level}}` is one of `this task`, `the research phase`, `the architecture phase`, or
`the implementation phase`; say which one is being scoped, because the offers differ
only in scope and a person cannot tell them apart otherwise. Pass it to
`scripts/prompt-render.sh` — an unsubstituted `{{level}}` stops the render rather than
reaching a person.

```
{{task_name}} has no written scope contract for {{level}}.

A contract is four short answers — the goal, what you expect to end up with, how
you will know it worked, and what you are explicitly not doing. It takes a couple
of minutes and every later phase is checked against it.

[n]o — skip, decide later (default)
[y]es — answer the four questions now
```

## Template ID: `prior-art-ask`

The question at `/research` step 5a. It is asked rather than assumed on purpose: an
unanswered question is recorded as nobody having been asked, never as nothing existing.
Ask it plainly, and never pre-answer it — a suggested answer is what makes a person
agree with a search that has not happened yet.

```
Before searching {{project_name}} for earlier work on this: do you already know
of any?

An abandoned branch, a script someone wrote, a half-finished attempt, notes in a
ticket. Anything you remember is worth more than what the search will turn up,
because it points at work that was never committed.

If you do not know of any, say so — that is a real answer and it gets recorded.
The search runs either way.
```

## Template ID: `coverage-mapping-fail`

```
Phase 1 incomplete: missing coverage mapping in research.md.

The framework requires a `## Coverage Mapping` H2 section that maps each Research Question to the section(s) of research.md that address it.

Missing or unaddressed questions:
{{missing_questions}}

To complete Phase 1, add the section to research.md and re-run /research, OR pass --skip-coverage-check <reason> to bypass (recorded in audit).

[a]bort — leave Phase 1 incomplete; fix research.md and re-run
[s]kip — bypass with reason (you'll be prompted for the reason)
```

## Template ID: `skill-review-decision`

```
Skill quality review for {{skills_reviewed}}:

{{findings}}

[a]ccept — findings are acceptable; proceed with /complete
[r]emediate — fix the findings now (you'll edit the skills, then return here)
[b]ypass — skip with reason (you'll be prompted for the reason; recorded in audit)
```

## Template ID: `plugin-validate-decision`

```
Plugin validation for {{plugins_validated}}:

{{findings}}

[a]ccept — findings are acceptable; proceed with /complete
[r]emediate — fix the findings now (you'll edit, then return here)
[b]ypass — skip with reason (you'll be prompted for the reason; recorded in audit)
```

## Template ID: `phase-command-bypass-acknowledge`

```
Phase-command bypass detected:
  Artifact: {{artifact_written}}
  Time: {{fired_at}}
  Phase command active: {{phase_command_active}}

The framework expected a /research / /design / /implement slash command to be active when this artifact was written. Direct Write means the phase command's gates (pre-analysis, dev-guides preflight, alignment retrofit, traceability walkthrough) did not fire.

[a]cknowledge — note the bypass and continue (recorded in audit)
[r]e-run — invoke the proper phase command now to retroactively fire the gates
```

## Bypass-reason capture

When a user picks the bypass option (`[s]kip` on coverage-mapping; `[b]ypass` on skill-review or plugin-validate; `[r]e-run` is NOT a bypass), the framework prompts:

```
Reason for bypass: <free-text>
```

The free-text is stored verbatim in the audit file's `bypass_reason` field. Empty string is allowed but discouraged.

## Versioning policy

- **Major bumps** are breaking: template ID rename, placeholder rename, option-list reorder.
- **Minor bumps** are additive: new templates, new optional placeholders. Existing template IDs and shape preserved.

## Non-goals

- **No i18n.** v1 ships English-only. Translating risks losing rationalization-resistance unless per-locale literal templates ship with their own anti-paraphrase guarantee.
- **No template inheritance / composition.** Each template is standalone literal text.
- **No conditional UX modes** (no "verbose" vs "compact"). The literal wording is the wording.
- **No template authoring tool.** Templates live in this markdown reference, hand-edited.

## Template ID: `review-gate-fail`

```
Review failed: {{failed_count}} hard-block gate(s) reported fail.

Per-gate findings (verbatim envelopes):
{{gates_failed_verbatim}}

How would you like to proceed?
[r]emediate — exit /review; fix and re-run
[s]kip — bypass each failed gate with explicit reason; sets overall_verdict: "bypassed", pr_ready: false
[a]bort — exit /review without writing _review.json; no audit recorded

No default. You MUST pick one.
```

## Template ID: `review-summary`

```
/review {{task_name}} complete.
Mode: {{mode}}    Overall verdict: {{overall_verdict}}    PR ready: {{pr_ready}}
## Standards
{{gates_run_table}}
{{mechanism_unresolved_line}}
## Spec
{{spec_verdict_line}} — never merged into the Standards score above
{{spec_provenance_line}}
Audit: {{audit_path}}
{{pr_body_line_or_empty}}
```

`{{mechanism_unresolved_line}}` renders the count of mechanisms whose disposition is `unresolved`, meaning the resolver cascade never ran for them, and is empty when that count is zero. It is informational and never changes a verdict: `not_searched` is non-blocking by design.

`{{gates_run_table}}` renders every `gates_run[]` entry **EXCEPT** `name:"spec"` — that entry is excluded from the Standards table and renders ONLY via `{{spec_verdict_line}}`, never duplicated into both blocks. `{{spec_verdict_line}}` format: `Spec: <pass|fail|skipped> — <N> missing requirement(s), <M> scope-creep warning(s)[; skipped: <reason>]`, where `<N>` is `missing_requirements[]` length and `<M>` is `scope_creep[]` length (both read from `_spec.json`'s `gate_specific`), and the trailing `; skipped: <reason>` clause is present only when `verdict == "skipped"` (using `skip_reason`).

`{{spec_provenance_line}}` renders `_spec.json`'s `gate_specific.provenance` object, written whenever `/review` step 5.0d ran `scripts/criterion-provenance.sh` — unconditionally, as the first action of that step, not only when the Spec reviewer is dispatched. Seven facts, six rendered forms plus one omit; no two ever render the same:

1. `gate_specific.provenance` key absent (a record from before this field existed) — omit the line. The only state that is genuinely "never checked."
2. `status: "no_return"` (the kernel exited non-zero: a bad `--task-folder`, a malformed flag) — `Spec provenance: check did not run — <reason>`.
3. `status: "no_criteria"` (no `alignment.md`, no Task-Level `### Success criteria`, or an empty section) — `Spec provenance: no criteria recorded for this section`.
4. `status: "criteria_unreadable"` (criteria exist but did not parse as a checklist) — `Spec provenance: criteria present but not readable as a checklist (success_criteria_not_checklist)`, naming the reader's own warning code.
5. No criterion records an author — `counts.owner`, `counts.designer`, and `counts.unrecognized` all zero — `Spec provenance: no criterion records an author (<T> total)`, `<T>` = `counts.total`. Do not enumerate; every criterion is in the same state and the count says so.
6. A mix (at least one recorded author, or an unrecognized-but-attempted marker) — `Spec provenance: <O> owner, <D> designer, <U> unrecorded (<R> unrecognized) of <T> criteria[; designer: <name>[, <name>...][, and <N> more]][; unrecorded: <name>[, <name>...][, and <N> more]]`. `<O>`/`<D>`/`<U>`/`<R>`/`<T>` = `counts.owner`/`counts.designer`/`counts.unrecorded`/`counts.unrecognized`/`counts.total`; `<R>` always shown, including zero, and is a subset of `<U>`, never added to `<T>`; each `<name>` = the first 60 characters of a `designer_authored[]`/`unrecorded[]` entry, quoted; each list capped at 5 names, then `, and <N> more`; a clause is omitted when its list is empty.
7. `status: "all_owner"` — `Spec provenance: all <T> criteria owner-confirmed`. The case a reader most needs to tell apart from silence.

Forms 5–7 are exhaustive and never overlap: form 5 needs zero recorded/attempted authors, form 7 needs zero unrecorded, form 6 is everything between them. Informational only, like `{{mechanism_unresolved_line}}`: none of the seven forms feeds `{{spec_verdict_line}}`'s own pass/fail.

## Template ID: `e2e-gate-fail`

Used by `commands/validate-e2e.md` when verdict is `fail`.

```
E2E gate: {{failed_count}} test(s) failed.

Failed tests:
{{failed_test_list}}

Playwright HTML report: `{{report_path}}`

Options:
- **Fix and re-run:** Address the failures and run `/ai-dev-assistant:validate:e2e` again.
- **Skip (with reason):** Run `/ai-dev-assistant:validate:e2e --skip "<your reason>"` to bypass and record the reason in the audit.

The E2E gate is **soft** — it signals but does not block. Bypassing is recorded in `_e2e.json` and visible via `/ai-dev-assistant:audit-status`.
```

Variables: `{{failed_count}}` (integer), `{{failed_test_list}}` (one `- <title> (<file>)` line per failure), `{{report_path}}` (relative path to HTML report).

## Template ID: `visual-regression-gate-fail`

Used by `commands/validate-visual-regression.md` — emitted once per failed
surface, before the regression/intentional/cancel classification.

```
A Visual Regression diff was detected for {{surface_id}} at viewport {{viewport}}.

Diff: {{diff_percent}}% pixels changed ({{diff_pixels}} px).
Diff image: {{diff_path}}

Classify this change:

  [r] Regression — this is a bug; leave the baseline unchanged
  [i] Intentional change — update the baseline to reflect the new design
  [c] Cancel — skip this surface; revisit later

Choice (default [c]):
```

Variables: `{{surface_id}}` (the registry surface id), `{{viewport}}` (viewport name), `{{diff_percent}}` (percentage, may be unknown), `{{diff_pixels}}` (pixel count, may be unknown), `{{diff_path}}` (path to the Playwright diff image — Playwright writes diff images under `test-results/`; may be unknown if the run produced none). The command substitutes `unknown` for any value it cannot resolve.

## Template ID: `visual-parity-gate-fail`

Used by `commands/validate-visual-parity.md` — emitted once per failed surface,
before the build-gap/intentional/cancel classification. The CSS-actionable diff
list IS the fix list the AI acts on.

```
A visual-parity gap was detected for {{surface_id}} at viewport {{viewport}}.

Pixel diff: {{diff_percent}}% ({{css_diff_mode}} CSS comparison).
Diff image: {{diff_path}}

CSS-actionable differences ({{css_diff_count}}):
{{css_diff_list}}

Classify this gap:

  [g] Build gap — the build does not match the design; fix the build (the list above is the fix list)
  [i] Intentional deviation — the build is correct; the design comp is out of date
  [c] Cancel — skip this surface; revisit later

Choice (default [c]):
```

Variables: `{{surface_id}}` (the registry surface id), `{{viewport}}` (viewport name), `{{diff_percent}}` (pixel-diff percentage, may be unknown), `{{css_diff_mode}}` (`full` for renderable references, `build-only` for static `figma`/`image` references), `{{css_diff_count}}` (number of CSS-actionable differences), `{{css_diff_list}}` (one `- <selector> { <property> }: <build> → <reference>` line per difference, or `(none — pixel diff only)` when the list is empty), `{{diff_path}}` (path to the pixel-diff image under `parity-results/`; may be unknown). The command substitutes `unknown` for any value it cannot resolve.

## Changelog

- **v1.10 (v5.50.0):** additive; `critic-dispatch` gains `{{design_block}}`, the component's own
  design, rendered for every lens. A critic that never sees the design cannot tell a finding whose
  remedy fits the named mechanism from one whose only fix is a different mechanism, and the second
  kind is not the builder's to settle. Existing templates and placeholders byte-identical to the
  v1.9 baseline.
- **v1.9 (v5.49.0):** additive; `critic-dispatch` gains `{{methodology_block}}`, rendered for every
  lens including `meets-ac`. Existing templates and placeholders byte-identical to the v1.8 baseline.
- **v1.6 (v5.20.0):** additive; `review-summary` grows the `## Standards` / `## Spec` two-axis blocks + `spec_verdict_line` substitution (M2); also documents that `{{gates_run_table}}` excludes the `name:"spec"` gates_run[] entry (rendered only via `{{spec_verdict_line}}`) and defines `{{spec_verdict_line}}`'s format, fixing M1 (spec entry double-rendering into both the Standards table and the Spec block). The M1 documentation addition is prose-only — no template literal changed beyond the two-axis block additions.
- **v1.5 (2026-05-21, v4.14.0):** additive; adds `visual-parity-gate-fail` template for `/validate:visual-parity` (Task D). Existing 9 templates byte-identical to v1.4 baseline.
- **v1.4 (2026-05-21, v4.13.0):** additive; adds `visual-regression-gate-fail` template for `/validate:visual-regression` (Task C). Existing 8 templates byte-identical to v1.3 baseline.
- **v1.3 (2026-05-21, v4.12.0):** additive; adds `e2e-gate-fail` template for `/validate:e2e` (Task B). Existing 7 templates byte-identical to v1.2 baseline.
- **v1.2 (2026-04-26, v4.1.0):** additive; adds `review-gate-fail` + `review-summary` for `/review` Phase 4. Templates byte-identical to inline literals shipped in `commands/review.md` PR #138 (verified by `tests/gate-prompts-vs-inline.sh`). Existing 5 templates byte-identical to v1.1 baseline (verified by `tests/gate-prompts-literal.sh`).
- **v1.1 (2026-04-25, v4.0.2):** additive; added Templates index table consolidating defaults + substitutions + fire conditions; trimmed per-template prose. ALL literal blocks preserved byte-for-byte (verified by `tests/gate-prompts-literal.sh`).
- **v1.0 (2026-04-25, v4.0.0):** initial; 5 templates covering all v4.0.0 user-prompt surfaces.

## Template ID: `critic-dispatch`

The whole of a critic dispatch at the build-critique rung: the acceptance criteria, the resolved
recipe, the range and the lens, and nothing else. Written after this plugin's own build measured
what a hand-written dispatch does: with the retired hostile lens gone, every prompt grew a six-to-eight
item list of things to try and a posture to hold, rebuilding that lens by hand, and each bought
a repair round. The lens definition lives in `agents/wo-critic.md`; the dispatch names the lens.
`recipe_block` is the delimited block from `references/recipe-resolution.md` step 4 for `security`
and `correctness`, and the empty string for `meets-ac`. Rendered by `scripts/prompt-render.sh
critic-dispatch …` and handed to the Task tool exactly as printed.

`methodology_block` (v1.9+) is the sibling of `recipe_block` and it goes to **all three** lenses,
`meets-ac` included: the test-first material the build was held to, inside
`=== METHODOLOGY (source=dev-guides, refs=…) === … === END METHODOLOGY ===`. A critic that cannot
tell a repair from a redefinition of the standard is a critic nobody gave the standard to, and
`meets-ac` — the lens that would have to judge a test rewritten to match the code it was meant to
constrain — is the one lens `recipe_block` deliberately empties. Its content, its source boundary
(dev-guides and plugin methodology refs, never the task folder) and its untrusted-upstream-data
standing are defined in `skills/work-order-critique/references/critic-prompt-contract.md`, and
both dispatch paths compose it from that one rule.

`design_block` (v1.10+) is the third sibling and it also goes to **all three** lenses: the
component's own design — everything in `architecture/<component>.md` above its `## Acceptance
criteria`, or a work-order's `## Build context`, which is the architecture slice pasted in — inside
`=== COMPONENT DESIGN (source=…) === … === END COMPONENT DESIGN ===`. Without it a critic receives
the *what* and never the *how*, so it cannot tell a finding whose remedy fits the mechanism the
design names from one whose only fix is to build the component another way. The second kind is a
`design_change` finding: it opens no repair round and is carried to `/review`. The extraction is a
fixed range rather than a summary for the same reason the methodology cut is a fixed heading — an
orchestrator choosing what to keep would be deciding what the critic may hold the build to, and it
sits in the builder's context. Rule:
`skills/work-order-critique/references/critic-prompt-contract.md`.

```
Lens: {{lens}}.
Worktree: {{worktree}}
Range: {{range}}
Files: {{files}}
review_ref: null. There is no per-component /review record, and its absence is not a clean one.
Output path: {{output_path}}
If you run anything, run the component's own spec; never the plugin suite or a make target.

Component: {{component}}. Acceptance criteria:
{{acceptance_criteria}}

{{design_block}}

{{recipe_block}}

{{methodology_block}}
```

