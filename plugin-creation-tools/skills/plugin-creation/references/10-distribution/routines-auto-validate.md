# Auto-Validate via Routines

A **Routine** is a Claude Code configuration (prompt + repositories + connectors + triggers) that runs automatically on Anthropic-managed cloud infrastructure. For plugin-repo maintainers, a Routine with a `pull_request.opened` GitHub trigger is the right way to run `/plugin-creation-tools:validate` on every PR — no CI config, no GitHub Action to maintain.

This closes the loop on the repeated `feedback_always_validate_plugins` corrections: validation happens automatically so you can't forget.

## When to use Routines vs GitHub Actions

| Need | Use |
|------|-----|
| Run validator on every PR, post inline comments | Routine |
| Deterministic pass/fail for branch protection | GitHub Action (cheaper, no quota) |
| LLM-assisted review of plugin changes | Routine |
| Matrix testing across multiple plugin versions | GitHub Action |
| One-click "run validator now" on a PR | Routine |

The two aren't mutually exclusive. A common setup pairs a GitHub Action for fast deterministic lint with a Routine for LLM-assisted semantic checks.

## Prerequisites

- Pro, Max, Team, or Enterprise plan with **Claude Code on the web** enabled
- **Claude GitHub App** installed on the repo (the trigger-setup flow prompts you if not)
- GitHub connected to your account (`/web-setup` in the CLI, or the web form)

GitHub triggers are configured **from the web UI only** — not from the CLI.

## Create the routine

At [claude.ai/code/routines](https://claude.ai/code/routines), click **New routine**.

### Step 1: Prompt

```
You are a plugin-validation routine running on every PR opened against this repo.

Your task:
1. Check out the PR branch in the repository workspace.
2. Invoke the /plugin-creation-tools:validate skill on the changed plugin(s).
   Identify which plugin(s) changed by inspecting the diff — each top-level
   directory under the repo root that contains a `.claude-plugin/plugin.json`
   is a plugin.
3. Collect all violations from the validator output.
4. Post review comments using the Claude GitHub App:
   - For each Important violation: a blocking inline comment at the
     file:line where it occurred
   - For Nit-level issues: summarize in a single top-level comment,
     capped at 5 inline mentions
   - If no issues: post a brief "Validator passed — no issues found."
5. If the validator detected version drift between `plugin.json` and the
   root `marketplace.json` for the same plugin, flag it as Important.

Success criteria:
- Every PR that opens or synchronizes receives exactly one set of
  validator comments within ~5 minutes.
- Comments reference the specific file:line when available.
- Severity assignment follows the rules in REVIEW.md at the repo root.

Do not:
- Push changes to any branch (read-only run).
- Comment on files unrelated to the PR's diff.
```

### Step 2: Repository

Select the plugin-marketplace repo. **Do not** enable "Allow unrestricted branch pushes" — this routine is read-only.

### Step 3: Environment

The **Default** environment is sufficient unless your plugin has a custom setup script (e.g. `npm install` for a JS-side validator). If you need dependencies:

- Create a custom environment with a setup script that installs them
- Setup-script output is cached — dependencies don't reinstall every run

### Step 4: Trigger

- **Trigger type**: GitHub event
- **Repository**: the one from Step 2
- **Event**: `Pull request` → `pull_request.opened` (and optionally `pull_request.synchronize` to re-run on new commits)
- **Filters** (optional):
  - `Is draft` = `false` — skip drafts so you don't run the validator on half-finished PRs
  - Base branch `main` — only run on PRs targeting the default branch
  - Author `is not one of` — skip bots that auto-open PRs (e.g. Dependabot)

### Step 5: Connectors

Remove connectors the routine doesn't need. For a validator routine, you typically only need the GitHub connector. Removing unused connectors reduces the tool surface and keeps the session focused.

### Step 6: Save and test

Click **Create**. Open a test PR and verify the routine fires within a few minutes. The routine's detail page shows every past run — click any run to open the full session and debug if comments didn't post.

## Branch-push permissions

Routines can only push to `claude/`-prefixed branches by default, which prevents accidental writes to protected branches. A validator routine doesn't push at all — the default restriction is exactly what you want. Never enable **Allow unrestricted branch pushes** for a validator routine.

## Footguns

- **Quota**: Research-preview limits apply per-routine and per-account per hour. Events beyond the cap are **dropped** until the window resets. For high-PR-volume repos, consider filtering more aggressively (e.g. skip Dependabot, skip drafts) to stay within the cap.
- **Token shown once**: API-trigger tokens are shown once at creation. GitHub-trigger routines don't need one, but if you add API triggers later, save the token immediately.
- **GitHub App is separate from `/web-setup`**: `/web-setup` grants clone access but not webhook delivery. The trigger setup flow installs the Claude GitHub App — don't skip that step.
- **Your identity**: everything the routine does on GitHub appears as **you**. Comments, check runs, and any (prohibited-here) pushes carry your GitHub user. Teammates don't share routines.
- **Session reuse disabled for GitHub triggers**: two PR updates produce two independent sessions. The routine can't remember what it said on the first pass. Handle idempotency in the prompt (e.g. "if you already posted comments on this PR, update them instead of duplicating").

## Per-trigger environment scoping

For the `/plugin-creation-tools:validate` routine specifically, the environment should:

- **Network**: default (egress limited) — the validator only needs to read repo files and call the Claude API
- **Env vars**: none required unless your plugin ships with env-dependent tests
- **Setup script**: only if the validator has non-trivial install steps

Minimizing what the environment can reach limits blast radius if the prompt is ever hijacked.

## Pairing with REVIEW.md

A Routine that runs `/plugin-creation-tools:validate` handles mechanical checks. A `REVIEW.md` (see [`review-md-v2.md`](review-md-v2.md)) handles semantic review. They complement each other:

- **Routine**: "Does this PR follow the plugin schema? Did the author bump both version fields? Is every new skill's frontmatter valid?"
- **REVIEW.md**: "Does this change make sense? Is the description pushy enough? Did the author drop a `PROACTIVELY` directive that should be kept?"

Running both on every PR is the recommended setup for a plugin marketplace repo.

## See Also

- [`review-md-v2.md`](review-md-v2.md) — the semantic-review counterpart
- [`packaging.md`](packaging.md) — how plugins are packaged for distribution
- Upstream: [Routines](https://docs.claude.com/en/routines), [Code Review](https://docs.claude.com/en/code-review)
