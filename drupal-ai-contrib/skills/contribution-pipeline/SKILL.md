---
name: contribution-pipeline
description: "Fetches the real GitLab merge-request pipeline for a Drupal contribution and gates on it — the authoritative final check. Use when the user runs /drupal-ai-contrib:pipeline or asks to check the real pipeline, the CI status, or whether a Drupal contribution is done. A contribution is not complete until the real drupalci pipeline is green."
version: 0.1.0
model: sonnet
user-invocable: false
---

# Contribution Pipeline (worker skill)

The authoritative final gate. Local verification (`contribution-verify`) is the fast
inner loop; **the real GitLab MR pipeline is the truth**. A contribution is **not done**
until the real drupalci pipeline is green.

Backs `/drupal-ai-contrib:pipeline`. Load the knowledge layer via `dev-guides-navigator`:
`drupal/contributing/drupalci-pipeline-gitlab-templates`,
`drupal/contributing/reproducing-drupalci-failures-locally`.

## Procedure

### 1. Resolve the MR and project

Identify the GitLab project and merge-request for the current issue fork (from `submit`
state, or ask). Validate the project path and MR number against expected patterns
before any API call.

### 2. Fetch the pipeline — via the GitLab API

Fetch the MR's latest pipeline and its jobs from the GitLab API. This is the produced
artifact — the actual pipeline result, not a prediction. Credentials are the
contributor's own; never store or transmit them.

### 3. Read the pipeline honestly

A pipeline reported "passed" can still hide problems. Inspect **every job**:
- **`allow_failure` jobs** — a red `allow_failure` job does not fail the pipeline but
  is still a real failure. Surface it.
- **Manual / opt-in jobs** — `gitlab_templates` v1.15.0+ moved opt-in variant jobs
  (`OPT_IN_TEST_PREVIOUS_MAJOR`, `_PREVIOUS_MINOR`, `_NEXT_MINOR`, `_MAX_PHP`) to
  manual trigger. An un-run manual job is **not coverage**. Report it explicitly as
  not run — never imply a green pipeline means those variants passed.

### 4. Gate

The contribution is **done** only when: every blocking job is green, every
`allow_failure` job's real status is surfaced, and every relevant manual variant is
either triggered-and-green or explicitly recorded as a deliberate non-goal.

If a job failed, diagnose it against the reproduction dev-guide and route the
contributor back to development → `verify`. Do not mark the work complete on local
green alone.

### 5. Report

Summarize per job: name, status, blocking vs. `allow_failure` vs. manual, and the link
to the job log. State plainly: is the contribution done, or what remains. The verdict
is the pipeline's — never assert "should pass".

## Examples

### Example 1: a green pipeline hiding a red allow_failure job
**Trigger:** `/drupal-ai-contrib:pipeline`
**Actions:**
1. Fetch the MR pipeline — overall status "passed".
2. Inspect every job — `phpstan` is red but `allow_failure: true`.
**Result:** Reported: pipeline green, but `phpstan` failed (non-blocking) — surfaced, not hidden.

### Example 2: un-run manual variant
**Trigger:** `/drupal-ai-contrib:pipeline`
**Actions:**
1. All blocking jobs green; the `PREVIOUS_MAJOR` variant is a manual job, never triggered.
**Result:** Reported as UNRUN — not implied coverage; the contributor decides whether to trigger it.

## Troubleshooting

| Situation | Handling |
|-----------|----------|
| No MR found for the branch | Report it; point at `/drupal-ai-contrib:submit` to create the MR first. |
| GitLab API unreachable / unauthenticated | Report the failure; never substitute a local-green result for the real pipeline. |
| Pipeline still running | Report in-progress; the gate is not satisfied until jobs finish. |
| A blocking job failed | Diagnose against the reproduction dev-guide; route back to development → `verify`. |
