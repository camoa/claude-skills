---
name: contribution-issue
description: "Works the Drupal issue lifecycle — reviews prior work on an issue first, then creates / comments on / claims it, and checks out the issue fork + branch with three-way fork handling. Use when the user runs /drupal-ai-contrib:issue or asks to find, create, claim, or check out a Drupal issue or issue fork. Wraps drupalorg-cli."
version: 0.1.0
model: sonnet
user-invocable: false
---

# Contribution Issue (worker skill)

Works the Drupal issue lifecycle so the contribution is **meaningful, not duplicate**.

Backs `/drupal-ai-contrib:issue`. Load the knowledge layer via `dev-guides-navigator`:
`drupal/contributing/drupal-issue-lifecycle`,
`drupal/contributing/issue-forks-merge-requests`,
`drupal/contributing/contribution-etiquette-rtbc-credit`,
`drupal/contributing-with-ai/issue-creation`.

## Procedure

### 1. Review prior work FIRST — before anything else

For an existing issue, review what has already happened:
- Read existing comments, the issue status, and any open merge requests.
- Determine whether the contribution would **duplicate** work in progress.
- If someone is actively on it, surface that — coordinate, do not compete.

A contribution that re-does existing work wastes maintainer review time. This review
is mandatory; it is not optional context-gathering.

### 2. Detect the issue system

drupal.org classic queue vs. GitLab — detect by following the project's Issues link.
The status taxonomy differs (classic statuses vs. GitLab `state::*` scoped labels);
handle dual-mode per the issue-lifecycle dev-guide.

### 3. Act — create, comment, or claim

- **Create** an issue — a clear summary, steps to reproduce, the proposed resolution.
- **Comment** on an issue — shape: thank → what works → feedback → next step.
- **Claim** an issue — set the appropriate status; then proceed to fork checkout (§4).

### 4. Fork checkout — three-way handling

When claiming an issue, handle the issue-fork state in **three ways** — never clobber
existing work:

| State | Action |
|-------|--------|
| **Your existing fork** | `issue:checkout` — check out your fork's issue branch |
| **Someone else's fork/branch** | **Surface it. Do not clobber.** Coordinate via an issue comment before proceeding — their work may be ahead of yours |
| **No fork yet** | `issue:branch` — create the issue fork + branch |

Branch naming **must include the issue number** (per the issue-forks dev-guide). Target
the most recent development branch (`main` for core; per-project for contrib).

### 5. Wrap drupalorg-cli — safely

All issue/fork operations wrap `mglaman/drupalorg-cli`. Use **fixed, validated
subcommands**. Validate issue IDs and project names against their expected patterns
before passing them to the CLI; never interpolate unsanitized input into a shell
command. drupal.org / GitLab credentials are the contributor's own — never store or
transmit them.

### 6. Report

Summarize: the issue, its system + status, the prior-work finding, the fork/branch
state and what was done. Point the contributor at the development phase, then `verify`.

## Examples

### Example 1: claiming an issue someone else already forked
**Trigger:** `/drupal-ai-contrib:issue 3456789`
**Actions:**
1. Review comments, status, MRs — find an existing issue fork by another contributor.
2. Surface it; do **not** create a competing branch. Suggest a coordinating comment.
**Result:** No clobbered work; the contributor decides whether to build on or wait.

### Example 2: a fresh issue, no prior work
**Trigger:** `/drupal-ai-contrib:issue 3456789`
**Actions:**
1. Review confirms no prior MR or fork.
2. Claim the issue, `issue:branch` to create the fork + issue-number branch.
**Result:** A clean issue branch checked out, ready for development.

## Troubleshooting

| Situation | Handling |
|-----------|----------|
| Issue ID is non-numeric / malformed | Reject before calling `drupalorg-cli`; ask for a valid ID. |
| `drupalorg-cli` not installed | Report how to install `mglaman/drupalorg-cli`; do not fabricate fork state. |
| Project uses GitLab, not the classic queue | Use the `state::*` scoped-label taxonomy per the issue-lifecycle dev-guide. |
| Prior work fully resolves the issue | Surface it — the contribution may be unnecessary; let the contributor decide. |
