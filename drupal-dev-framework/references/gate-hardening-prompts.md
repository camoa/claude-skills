# Gate Hardening Prompts v1.0

**Introduced:** drupal-dev-framework v4.0.0
**Owner:** This reference; consumed by command bodies
**Consumers:** `commands/research.md` (pre-analysis + coverage-mapping prompts), `commands/complete.md` (skill-review + plugin-validate prompts), `hooks/phase-command-bypass.sh` (phase-command-bypass acknowledgment)

The framework's hardened gates use **literal mandated wording** for user prompts. The literal-wording requirement IS the rationalization-resistance mechanism — agents trained on English are constrained from paraphrasing English templates, which removes the "I'll soften this for the user" failure mode the original critique called out.

This reference defines all 5 user-prompt templates. Command bodies reference templates by ID (e.g., `prompt-template: pre-analysis-decision`); the framework refuses to deviate from the literal wording. Substitutions are limited to `{{placeholder}}` markers documented per template.

The 2 deterministic gates (`dev-guides-load`, `playbook-load`) have NO user prompts and therefore NO templates here.

## Template authoring rules

1. **Literal text** — exactly as written, including punctuation, capitalization, line breaks
2. **Placeholders** — only `{{snake_case_marker}}` substitutions allowed; documented per template
3. **No paraphrase** — framework refuses to "translate" or "soften" the text
4. **No pre-answer** — framework refuses to add "I think the answer is X" or similar before the prompt
5. **No reorder** — option lists ([y]/[n]/[s] etc.) preserve order
6. **No truncate** — even on long content, the framework shows verbatim agent output (per the show-not-summarize mechanism)

## Template ID: `pre-analysis-decision`

Fired by `/research` after `analysis-agent` returns. Substitutions: `{{decision}}`, `{{signals_used}}`, `{{reasoning}}`, `{{children_list}}` (multi-line; only present when decision == "epic_candidate").

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

Default for keep_flat / insufficient_info: `[y]`. For epic_candidate: no default — user MUST pick.

## Template ID: `coverage-mapping-fail`

Fired by `/research` at end-of-phase when `coverage-mapping-check.sh` returns `verdict: fail`. Substitutions: `{{missing_questions}}` (multi-line list).

```
Phase 1 incomplete: missing coverage mapping in research.md.

The framework requires a `## Coverage Mapping` H2 section that maps each Research Question to the section(s) of research.md that address it.

Missing or unaddressed questions:
{{missing_questions}}

To complete Phase 1, add the section to research.md and re-run /research, OR pass --skip-coverage-check <reason> to bypass (recorded in audit).

[a]bort — leave Phase 1 incomplete; fix research.md and re-run
[s]kip — bypass with reason (you'll be prompted for the reason)
```

Default: `[a]`.

## Template ID: `skill-review-decision`

Fired by `/complete` when `git diff --cached --name-only` shows `skills/*/SKILL.md` changes. Substitutions: `{{skills_reviewed}}` (comma-list), `{{findings}}` (multi-line agent output).

```
Skill quality review for {{skills_reviewed}}:

{{findings}}

[a]ccept — findings are acceptable; proceed with /complete
[r]emediate — fix the findings now (you'll edit the skills, then return here)
[b]ypass — skip with reason (you'll be prompted for the reason; recorded in audit)
```

Default: no default — user MUST pick.

## Template ID: `plugin-validate-decision`

Fired by `/complete` when `git diff --cached --name-only` shows plugin file changes. Substitutions: `{{plugins_validated}}` (comma-list), `{{findings}}` (multi-line slash-command output).

```
Plugin validation for {{plugins_validated}}:

{{findings}}

[a]ccept — findings are acceptable; proceed with /complete
[r]emediate — fix the findings now (you'll edit, then return here)
[b]ypass — skip with reason (you'll be prompted for the reason; recorded in audit)
```

Default: no default — user MUST pick.

## Template ID: `phase-command-bypass-acknowledge`

Fired post-hoc by `/audit-status` when listing tasks with `_phase-command-bypass.json` audit files. NOT fired at Write time (the hook is non-blocking; it just records). Substitutions: `{{artifact_written}}`, `{{phase_command_active}}`, `{{fired_at}}`.

```
Phase-command bypass detected:
  Artifact: {{artifact_written}}
  Time: {{fired_at}}
  Phase command active: {{phase_command_active}}

The framework expected a /research / /design / /implement slash command to be active when this artifact was written. Direct Write means the phase command's gates (pre-analysis, dev-guides preflight, alignment retrofit, traceability walkthrough) did not fire.

[a]cknowledge — note the bypass and continue (recorded in audit)
[r]e-run — invoke the proper phase command now to retroactively fire the gates
```

Default: `[a]` — non-blocking acknowledgment.

## Bypass-reason capture

When a user picks the bypass option (`[s]kip` on coverage-mapping; `[b]ypass` on skill-review or plugin-validate; `[r]e-run` is NOT a bypass), the framework prompts:

```
Reason for bypass: <free-text>
```

The free-text is stored verbatim in the audit file's `bypass_reason` field. Empty string is allowed but discouraged.

## Versioning policy

- **Major bumps** are breaking: template ID rename, placeholder rename, option-list reorder.
- **Minor bumps** are additive: new templates (e.g., when a new hardened surface ships), new optional placeholders. Existing template IDs and shape preserved.

v1.0 covers all 5 v4.0.0 user-prompt surfaces.

## Non-goals

- **No i18n.** v1 ships English-only. Translating risks losing rationalization-resistance unless per-locale literal templates ship with their own anti-paraphrase guarantee.
- **No template inheritance / composition.** Each template is standalone literal text. Reuse via DRY would obscure what the user actually sees.
- **No conditional UX modes.** No "verbose" vs "compact" prompts. The literal wording is the wording.
- **No template authoring tool.** Templates live in this markdown reference, hand-edited. No generator script in v1.
