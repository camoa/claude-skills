---
name: contribution-review
description: "Runs honest fresh-context review of a Drupal contribution — dispatches isolated reviewer agents with no session narrative to check the work against scope, coding standards, security, and the AI policy. Use when the user runs /drupal-ai-contrib:review or asks for an honest review, a fresh-eyes review, or a pre-submission review of a Drupal contribution. A builder cannot objectively review its own work."
version: 0.1.0
model: inherit
user-invocable: false
disallowed-tools: Edit, Write
---

# Contribution Review (worker skill)

Honest validation. A builder carries a session narrative — the story of why each
choice was made — and cannot objectively review its own work. This skill dispatches
**fresh-context agents** that have none of that narrative.

Backs `/drupal-ai-contrib:review`. Load the knowledge layer via `dev-guides-navigator`:
`drupal/contributing-with-ai/ai-code-review-checklist`,
`drupal/contributing-with-ai/human-review-requirements`,
`drupal/contributing-with-ai/security-considerations`,
`drupal/contributing-with-ai/issue-review-guidelines`.

## Procedure

### 1. Establish the review inputs

Gather, without editorializing:
- the **scope contract** — goal / expected result / success criteria / non-goals
- the **diff** under review — produce it explicitly with
  `git diff <target-branch>...<issue-fork-branch>` (the three-dot form shows only the
  contribution's own changes). The reviewer agent must receive a real, non-empty diff;
  if `git diff` returns nothing, there is nothing to review — report that and stop.
- the issue and its acceptance criteria
- the **verify-staleness state** — run `${CLAUDE_PLUGIN_ROOT}/scripts/reverify-list.sh`;
  if it prints any path, note in the report that those files changed since `verify`
  last passed, so reviewers know the gate evidence may not cover the current diff.

### 2. Dispatch the fresh-context reviewer

Use the Task tool to invoke the `drupal-ai-contrib:fresh-context-reviewer` agent. Pass
it the diff, the scope contract, and the issue — but **not** the build narrative. The
agent reviews against:
- **Scope** — does the change deliver exactly the contract, nothing beyond it?
  Over-delivery is a finding (it is review burden the maintainer did not ask for).
- **Standards** — Drupal coding standards, Drupal + PHP best practices.
- **Security** — AI-specific risks (see the security-considerations dev-guide).
- **AI policy** — is AI use above the "significant portion" threshold disclosed?

For a **large** change, dispatch multiple reviewer agents for perspective diversity. For
a **security-critical** change, the security sub-review in §3 is **mandatory** — an
explicit Task dispatch whose output is captured in the artifact, not an optional aside.

**Complementary security layer.** The `security-guidance` plugin and this skill cover
*different* scopes and do not compete. `security-guidance` runs automatically on
**Claude's own in-session edits** — a deterministic per-edit string match (no model
involved) plus a fresh-context, security-focused review of the diff at end-of-turn and on
commit. The `fresh-context-reviewer` agent here is **per-contribution** and **explicitly
dispatched**, reviewing the whole contribution diff against scope, standards, security,
and the AI policy. Run both: in-session guidance catches vulnerabilities as Claude writes
them; the contribution review catches what survives into the diff. Neither replaces the
other, and neither blocks — both surface findings as instructions. Install the in-session
layer with `/plugin install security-guidance@claude-plugins-official`.

### 3. Security-critical contributions — mandatory Task dispatch

A contribution is **security-critical** when the issue is **security-tagged** *or* the
diff touches any of: permission / access callbacks, entity or field access, `#access`
form keys, user-input sanitization or output escaping, SQL / database queries built from
input, file or path handling, or other XSS-/injection-adjacent code. When **none** of
these apply, skip this step.

When it applies, the security sub-review is **not advisory** — dispatch it explicitly with
the **Task tool** (the subagent's isolated context is the evidence, not this skill's
narrative): run `/code-quality-tools:security` on the diff, and/or the `code-paper-test`
paper-test skill, passing the diff plus the security checklist from the
`security-considerations` dev-guide. **Append the Task's returned findings to the review
artifact (§6) before this skill returns its verdict.** A security-critical review is not
complete until that sub-review output is captured in the artifact — never on an assertion
that it "was run".

### 4. Delegate the philosophy review

Hand the SOLID / DRY / architecture review to `code-quality-tools`. This skill owns the
*honest-validation* concern; `code-quality-tools` owns the philosophy review. Do not
re-implement it here.

### 5. Synthesize — honest verdicts only

Collect the agents' verdicts. Report findings by severity (blocker / should-fix /
suggestion), each tied to a **file:line** and a concrete fix. The verdict is the
agent's — never soften it because the builder explained the intent. If reviewers
disagree, surface the disagreement; do not paper over it.

### 6. Report

A findings report: per-finding severity, location, fix. For a security-critical
contribution, the §3 sub-review findings must already appear here. State plainly whether
the contribution is ready for `submit` or needs another development pass. An honest "not
ready" is the correct output when the work is not ready.

After producing the report, record that a review ran against the current tree:
`${CLAUDE_PLUGIN_ROOT}/scripts/review-mark.sh --set`. `submit` reads this marker to detect
contribution files edited **after** this review (the review-staleness gate, parallel to
the `verify` reverify ledger). Re-running `review` after fixes re-stamps it.

## Examples

### Example 1: over-delivery caught
**Trigger:** `/drupal-ai-contrib:review`
**Actions:**
1. The `fresh-context-reviewer` agent compares the diff to the scope contract.
2. It finds a refactor of an unrelated class — outside the contract's non-goals.
**Result:** Logged as a blocker — review burden the maintainer did not ask for.

### Example 2: a security-critical change
**Trigger:** `/drupal-ai-contrib:review` on a diff touching access control (`#access`,
an entity-access callback).
**Actions:**
1. Flag it security-critical; dispatch the fresh-context reviewer **and** the §3 Task
   sub-review (`/code-quality-tools:security` + `code-paper-test`) on the diff.
2. Append the sub-review findings to the artifact; stamp `review-mark.sh --set`.
**Result:** A synthesized report with the security sub-review captured in it (not merely
asserted); reviewer disagreement surfaced, not hidden.

## Troubleshooting

| Situation | Handling |
|-----------|----------|
| No diff to review | Report it and stop — there is nothing to review. |
| No scope contract exists | Surface the gap — scope review needs a contract; ask for one or note it unassessable. |
| Builder pushes back on a finding | The agent's verdict stands — do not soften it because intent was explained. |
| Reviewer agents disagree | Surface the disagreement in the report; do not paper over it. |
