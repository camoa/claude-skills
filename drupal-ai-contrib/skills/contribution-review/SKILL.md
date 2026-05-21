---
name: contribution-review
description: "Runs honest fresh-context review of a Drupal contribution — dispatches isolated reviewer agents with no session narrative to check the work against scope, coding standards, security, and the AI policy. Use when the user runs /drupal-ai-contrib:review or asks for an honest review, a fresh-eyes review, or a pre-submission review of a Drupal contribution. A builder cannot objectively review its own work."
version: 0.1.0
model: sonnet
user-invocable: false
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

### 2. Dispatch the fresh-context reviewer

Use the Task tool to invoke the `drupal-ai-contrib:fresh-context-reviewer` agent. Pass
it the diff, the scope contract, and the issue — but **not** the build narrative. The
agent reviews against:
- **Scope** — does the change deliver exactly the contract, nothing beyond it?
  Over-delivery is a finding (it is review burden the maintainer did not ask for).
- **Standards** — Drupal coding standards, Drupal + PHP best practices.
- **Security** — AI-specific risks (see the security-considerations dev-guide).
- **AI policy** — is AI use above the "significant portion" threshold disclosed?

For a large or security-critical change, dispatch multiple reviewer agents for
perspective diversity, or delegate to `code-paper-test` for line-by-line paper testing.

### 3. Delegate the philosophy review

Hand the SOLID / DRY / architecture review to `code-quality-tools`. This skill owns the
*honest-validation* concern; `code-quality-tools` owns the philosophy review. Do not
re-implement it here.

### 4. Synthesize — honest verdicts only

Collect the agents' verdicts. Report findings by severity (blocker / should-fix /
suggestion), each tied to a **file:line** and a concrete fix. The verdict is the
agent's — never soften it because the builder explained the intent. If reviewers
disagree, surface the disagreement; do not paper over it.

### 5. Report

A findings report: per-finding severity, location, fix. State plainly whether the
contribution is ready for `submit` or needs another development pass. An honest "not
ready" is the correct output when the work is not ready.

## Examples

### Example 1: over-delivery caught
**Trigger:** `/drupal-ai-contrib:review`
**Actions:**
1. The `fresh-context-reviewer` agent compares the diff to the scope contract.
2. It finds a refactor of an unrelated class — outside the contract's non-goals.
**Result:** Logged as a blocker — review burden the maintainer did not ask for.

### Example 2: a security-critical change
**Trigger:** `/drupal-ai-contrib:review` on a diff touching access control.
**Actions:**
1. Dispatch multiple reviewer agents for perspective diversity.
2. Delegate line-by-line paper testing to `code-paper-test`.
**Result:** A synthesized findings report; reviewer disagreement surfaced, not hidden.

## Troubleshooting

| Situation | Handling |
|-----------|----------|
| No diff to review | Report it and stop — there is nothing to review. |
| No scope contract exists | Surface the gap — scope review needs a contract; ask for one or note it unassessable. |
| Builder pushes back on a finding | The agent's verdict stands — do not soften it because intent was explained. |
| Reviewer agents disagree | Surface the disagreement in the report; do not paper over it. |
