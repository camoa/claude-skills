---
name: contribution-pipeline
description: "Fetches the real GitLab merge-request pipeline for a Drupal contribution and gates on it — the authoritative final check. Use when the user runs /drupal-ai-contrib:pipeline or asks to check the real pipeline, the CI status, or whether a Drupal contribution is done. A contribution is not complete until the real drupalci pipeline is green."
version: 0.1.0
model: inherit
user-invocable: false
disallowed-tools: Edit, Write
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
state, or ask). Before any API call, validate against an explicit pattern — the MR
number must match `^[0-9]+$`, the project path `^[A-Za-z0-9_./-]+$` — and reject
anything that does not match rather than calling the API with it.

### 2. Fetch the pipeline — `glab` via the `drupal-gitlab` skill

Fetch the MR's latest pipeline and its jobs with **`glab`**, delegated to the
`drupal-gitlab` skill (it owns the `git.drupalcode.org` auth + host rules; see its
`references/ci-cd.md`). This is the produced artifact — the actual pipeline result, not a
prediction:

```bash
glab ci status                                    # pipeline status for the MR's branch
glab ci view                                      # per-job overview
glab ci trace <job-name>                          # stream a job's full log (debug failures)
```

Always pass `--repo "git.drupalcode.org/project/<repo>"` (or run inside the configured
git dir) — never rely on the default host. Credentials are the contributor's own (a
read-only token suffices for status); never store or transmit them.

**Two hard limits on `git.drupalcode.org`:**
- **Pipelines fire on push events only** — API/CLI triggers (`glab ci run`,
  `POST /pipeline`) are blocked. To re-run CI, push a commit (an `--allow-empty` commit
  works); never claim a re-trigger you cannot perform.
- **Never WebFetch a GitLab job/MR URL** — the pages are JavaScript-rendered and return
  no log. Read job logs with `glab ci trace <job>` (or `glab api … /jobs/<id>/trace`).

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
| `glab` unauthenticated / API unreachable | Report the failure (`glab auth login --hostname git.drupalcode.org`); never substitute a local-green result for the real pipeline. |
| Pipeline still running | Report in-progress; the gate is not satisfied until jobs finish. |
| Pipeline needs re-running | Triggers are blocked on `git.drupalcode.org` — push a commit (`--allow-empty` if no code change); pipelines fire on push only. |
| A blocking job failed | Diagnose against the reproduction dev-guide; route back to development → `verify`. |
