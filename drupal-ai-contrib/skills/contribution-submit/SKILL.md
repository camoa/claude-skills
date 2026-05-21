---
name: contribution-submit
description: "Creates or updates a Drupal merge request and generates the AI-disclosure comment at the policy threshold. Use when the user runs /drupal-ai-contrib:submit or asks to submit, open, or update a Drupal merge request or patch. Wraps drupalorg-cli; surfaces status and RTBC guidance."
version: 0.1.0
model: sonnet
user-invocable: false
---

# Contribution Submit (worker skill)

Creates or updates the merge request and prepares the required AI disclosure.

Backs `/drupal-ai-contrib:submit`. Load the knowledge layer via `dev-guides-navigator`:
`drupal/contributing-with-ai/merge-request-workflow`,
`drupal/contributing/issue-forks-merge-requests`,
`drupal/contributing-with-ai/commit-messages`,
`drupal/contributing-with-ai/disclosure-checkboxes`,
`drupal/contributing/contribution-etiquette-rtbc-credit`.

## Preconditions — point, never refuse

`submit` runs whatever the prior state. But before creating the MR, check and surface:
- Has `verify` been run, with its gates green? If not, say so — submitting unverified
  work is exactly the drive-by behavior the AI policy lists as unacceptable.
- Has `review` been run? Surface it if not.
- **Is the green `verify` still valid?** Run `${CLAUDE_PLUGIN_ROOT}/scripts/reverify-list.sh`.
  If it prints any path, those files were edited **after** `verify` last passed — the
  green is stale. Surface the stale paths and recommend re-running `verify` before
  submitting. A pre-edit green is not evidence for the current code (guardrails Rule 3).

If a precondition is unmet, **report it and let the contributor decide** — do not
silently block. The contributor may have evidence from another path.

## Procedure

### 1. Confirm the branch and target

The issue-fork branch (issue-number in the name) and the **target branch** — the most
recent development branch (`main` for core; per-project for contrib). Draft vs. ready:
open as draft while work continues; mark ready when the issue moves to Needs review.

### 2. The AI-disclosure decision — policy-driven

Determine whether AI generated a **significant portion** — whole functions, classes,
architectural scaffolding, or extensive docblocks. Single-line autocomplete is exempt.
(These examples are illustrative — the live policy fetched below is authoritative.)

- If **yes**: prepare the disclosure in **both** places the policy requires — the issue
  **disclosure checkboxes** (AI Assisted Code / AI Generated Code / Vibe Coded, as
  applicable) **and** the MR description, including the `AI-Generated: Yes (...)`
  comment in the policy's format.
- If **no**: record that the threshold was assessed and not crossed.

Fetch the **current** policy state via the `drupal-ai-contrib:ai-policy-checker` agent
(Task tool) — do not rely on hard-coded thresholds; the policy moves.

### 3. Commit messages

Attribute AI involvement in commit messages per the commit-messages dev-guide. Keep the
contributor as the responsible author — "the AI wrote it" is never a defense.

### 4. Create or update the MR — via drupalorg-cli

Wrap `mglaman/drupalorg-cli` with **fixed, validated subcommands**. Before any
shell-out, validate identifiers against an explicit pattern — issue IDs `^[0-9]+$`,
project machine-names `^[a-z][a-z0-9_]*$` — and reject non-matching values; never
interpolate unsanitized input. Credentials are the contributor's own — never stored or
transmitted.

The MR description states: what the change does, the issue it resolves, the AI
disclosure (§2), and how it was verified (cite the captured `verify` artifacts).

### 5. Status & RTBC guidance — dual-mode

Set the issue status correctly (Needs review when the MR is ready). Surface RTBC
discipline: RTBC asserts the **full checklist** (tests pass, phpcs clean, threads
resolved, gates passed for core) — never just a code read, never self-RTBC. drupal.org
classic queue and GitLab `state::*` labels differ — handle the project's actual system.

### 6. Report

Summarize: the MR URL, target branch, the disclosure decision and where it was placed,
the issue status set, and the next step (`pipeline` — the real pipeline is the
authoritative final gate).

## No overclaiming

Never imply Drupal "endorses AI contributions", never guarantee MR acceptance, never
make GPL or provenance guarantees. The contributor is fully responsible for the
submission, including copyright and licensing.

## Examples

### Example 1: significant AI portion → disclosure required
**Trigger:** `/drupal-ai-contrib:submit 3456789`
**Actions:**
1. Assess: AI generated a whole service class → over the "significant portion" threshold.
2. Prepare the issue disclosure checkboxes **and** the `AI-Generated: Yes (...)` comment
   in the MR description; fetch the current policy via `drupal-ai-contrib:ai-policy-checker`.
**Result:** The MR opens with disclosure in both required places.

### Example 2: submitting before verify
**Trigger:** `/drupal-ai-contrib:submit` with no green `verify` run.
**Actions:**
1. Surface that `verify` has not produced green gates.
2. Report it plainly; let the contributor decide whether to proceed.
**Result:** No silent block — but the drive-by risk is named.

## Troubleshooting

| Situation | Handling |
|-----------|----------|
| `verify` / `review` not run | Surface it; report, do not refuse — the contributor decides. |
| `drupalorg-cli` not installed | Report how to install it; do not fabricate an MR URL. |
| Disclosure threshold ambiguous | Fetch the live policy via `drupal-ai-contrib:ai-policy-checker`; when still unclear, disclose. |
| Project uses GitLab `state::*` labels | Set the GitLab scoped label, not a classic-queue status. |
