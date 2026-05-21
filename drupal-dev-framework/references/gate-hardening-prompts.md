# Gate Hardening Prompts v1.2

**Introduced:** drupal-dev-framework v4.0.0 (v1.0); compressed v4.0.2 (v1.1, additive); v4.1.0 (v1.2, additive — adds `review-gate-fail` + `review-summary` for the new `/review` command).
**Owner:** This reference; consumed by command bodies.
**Consumers:** `commands/research.md` (pre-analysis + coverage-mapping), `commands/complete.md` (skill-review + plugin-validate), `commands/review.md` (review-gate-fail + review-summary, v4.1.0+), `hooks/phase-command-bypass.sh` (phase-command-bypass acknowledgment).

The framework's hardened gates use **literal mandated wording** for user prompts. Literal-wording IS the rationalization-resistance mechanism — agents trained on English are constrained from paraphrasing English templates, which removes the "soften this for the user" failure mode. Authoring rules (§"Template authoring rules") forbid paraphrase, reorder, pre-answer, and truncation.

The 2 deterministic gates (`dev-guides-load`, `playbook-load`) have NO user prompts; no templates here.

**Cross-file equivalence (v4.1.0+):** for templates also inlined in command bodies (`review-gate-fail`, `review-summary`), the literal block here MUST be byte-identical to the inline literal in the consuming command. Verified by `tests/gate-prompts-vs-inline.sh`.

## Templates index

| ID | Fired by | Substitutions | Default option |
|----|----------|--------------|----------------|
| `pre-analysis-decision` | `/research` after `analysis-agent` | `decision`, `signals_used`, `reasoning`, `children_list` (epic_candidate only) | `[y]` for keep_flat / insufficient_info; **none** for epic_candidate |
| `coverage-mapping-fail` | `/research` end-of-phase on `verdict: fail` | `missing_questions` (multi-line) | `[a]` |
| `skill-review-decision` | `/complete` on `skills/*/SKILL.md` staged change | `skills_reviewed`, `findings` | **none** — user MUST pick |
| `plugin-validate-decision` | `/complete` on plugin file staged change | `plugins_validated`, `findings` | **none** — user MUST pick |
| `phase-command-bypass-acknowledge` | `/audit-status` listing tasks with `_phase-command-bypass.json` | `artifact_written`, `phase_command_active`, `fired_at` | `[a]` |
| `review-gate-fail` (v1.2+) | `/review` end-of-phase on any hard-block-gate `fail` | `failed_count`, `gates_failed_verbatim` | **none** — user MUST pick |
| `review-summary` (v1.2+) | `/review` end-of-phase on any verdict | `task_name`, `mode`, `overall_verdict`, `pr_ready`, `gates_run_table`, `audit_path`, `pr_body_line_or_empty` | (no prompt; informational) |

## Template authoring rules

1. **Literal text** — exactly as written, including punctuation, capitalization, line breaks
2. **Placeholders** — only `{{snake_case_marker}}` substitutions allowed
3. **No paraphrase** — framework refuses to "translate" or "soften"
4. **No pre-answer** — framework refuses to add "I think the answer is X" before the prompt
5. **No reorder** — option lists ([y]/[n]/[s] etc.) preserve order
6. **No truncate** — even on long content, framework shows verbatim agent output (per show-not-summarize)

## Template ID: `pre-analysis-decision`

```
Pre-analysis verdict: {{decision}}
Signals fired: {{signals_used}}

Agent reasoning (verbatim):
{{reasoning}}

{{#if decision == "epic_candidate"}}
Proposed children:
{{children_list}}

Create as epic with these children?
[y]es — convert to epic via /migrate-to-epic
[n]o flat — proceed as flat task
[s]tandard — show edit list of proposed children
{{/if}}
{{#if decision == "keep_flat"}}
Verdict recorded as keep_flat. Proceed as flat task.

[y]es — proceed as flat (default)
[n]o — abort and re-evaluate
{{/if}}
{{#if decision == "insufficient_info"}}
Agent had insufficient context. Verdict recorded as insufficient_info. Proceed as flat task with the option to re-run pre-analysis after research.

[y]es — proceed as flat
[n]o — abort
{{/if}}
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
Gates run:
{{gates_run_table}}
Audit: {{audit_path}}
{{pr_body_line_or_empty}}
```

## Template ID: `e2e-gate-fail`

Used by `commands/validate-e2e.md` when verdict is `fail`.

```
E2E gate: {failed_count} test(s) failed.

Failed tests:
{failed_test_list}

Playwright HTML report: `{report_path}`

Options:
- **Fix and re-run:** Address the failures and run `/drupal-dev-framework:validate:e2e` again.
- **Skip (with reason):** Run `/drupal-dev-framework:validate:e2e --skip "<your reason>"` to bypass and record the reason in the audit.

The E2E gate is **soft** — it signals but does not block. Bypassing is recorded in `_e2e.json` and visible via `/drupal-dev-framework:audit-status`.
```

Variables: `{failed_count}` (integer), `{failed_test_list}` (one `- <title> (<file>)` line per failure), `{report_path}` (relative path to HTML report).

## Changelog

- **v1.3 (2026-05-21, v4.12.0):** additive; adds `e2e-gate-fail` template for `/validate:e2e` (Task B). Existing 7 templates byte-identical to v1.2 baseline.
- **v1.2 (2026-04-26, v4.1.0):** additive; adds `review-gate-fail` + `review-summary` for `/review` Phase 4. Templates byte-identical to inline literals shipped in `commands/review.md` PR #138 (verified by `tests/gate-prompts-vs-inline.sh`). Existing 5 templates byte-identical to v1.1 baseline (verified by `tests/gate-prompts-literal.sh`).
- **v1.1 (2026-04-25, v4.0.2):** additive; added Templates index table consolidating defaults + substitutions + fire conditions; trimmed per-template prose. ALL literal blocks preserved byte-for-byte (verified by `tests/gate-prompts-literal.sh`).
- **v1.0 (2026-04-25, v4.0.0):** initial; 5 templates covering all v4.0.0 user-prompt surfaces.
