# Cloud Routine — Quality Sweep (fallback)

Use a Cloud Routine when the sweep must run without your machine, or must react to GitHub events that Desktop can't see. Routines run on Anthropic-managed cloud infrastructure with a fresh clone of the default branch — they do NOT see your uncommitted work.

Prerequisites: Claude Code on the web enabled on your account; GitHub connected via `/web-setup`. Routines are available on Pro, Max, Team, and Enterprise.

## Create

CLI: `/schedule daily quality audit at 7am` — walks through the same form the web uses. Or web: [claude.ai/code/routines](https://claude.ai/code/routines) → **New routine**.

## Configuration

| Field | Value |
|---|---|
| **Name** | `quality-sweep-cloud` |
| **Model** | Sonnet |
| **Repositories** | Your project repo(s). Default branch is cloned on each run. |
| **Branch pushes** | Default: only `claude/`-prefixed branches. Enable *Allow unrestricted branch pushes* only if the routine should open PRs against other branches. |
| **Environment** | Default, unless you need extra secrets or a custom setup script. Setup scripts are cached, so dependency install runs once per environment change. |
| **Connectors** | Remove all except what the routine actually needs. Slack is useful for posting summaries. |
| **Trigger** | Schedule (weekly recommended — hourly hits daily cap fast) |

## Prompt

```markdown
Run a code-quality sweep on this repository.

1. Detect project type:
   - composer.json with drupal/core → Drupal
   - package.json with next → Next.js
   - Else → post "Unsupported project type" to Slack and exit

2. Run the full audit (tools the cloud image has pre-installed are used;
   anything missing is skipped with a note):
   - Drupal: /code-quality:audit
   - Next.js: /code-quality:audit

3. Generate a summary:
   - Project type detected
   - Tools run and exit status
   - Top 10 findings ranked by severity
   - Week-over-week delta if the previous sweep's summary is reachable

4. Post the summary to Slack channel #eng-quality. Prefix the message with
   "REGRESSION" if any Critical or High severity findings are new.
   REDACT secrets-type findings: Gitleaks findings include the matched secret
   in the body — strip or mask before posting. Format as "secret of type X
   detected in file.ext:line (value redacted)".

5. If any finding is actionable (specific file:line), create a PR on a
   claude/quality-sweep-YYYY-WW branch with a minimal fix. Link the PR
   in the Slack summary. Do NOT modify shared/protected branches.

6. Respond with the Slack message text.
```

## Triggers

- **Schedule** — weekly, Sunday 6 AM (daily hits the per-account cap fast and burns subscription usage)
- **GitHub event** — `pull_request.opened` if you want auto-review on every PR (combine with filters to skip drafts / dependabot)
- **API** — for CI-triggered pre-merge gate, see `premerge-gate-routine.md`

## Footguns

1. **No permission prompts.** Routines run autonomously. There is no "ask me first." Scope aggressively: limit branch pushes to `claude/`, remove unused connectors, restrict network in the environment if the setup script doesn't need open egress.
2. **Fresh clone only.** The routine cannot see uncommitted work, untracked files, local `.env.local`, or the state of your DDEV containers. If the audit needs those, use Desktop instead.
3. **`text` body is literal.** For API triggers, the `text` field is freeform string, NOT parsed JSON. If you send `'{"pr": 1234}'` the routine receives that literal string.
4. **Beta header required.** `anthropic-beta: experimental-cc-routine-2026-04-01` for API triggers. Breaking changes ship behind new dated headers; the two most recent versions keep working.
5. **Token shown once.** API trigger token appears once on generation and cannot be retrieved later. Store it immediately in your alerting tool's secret store. Rotate via **Regenerate**; revoke via **Revoke**.
6. **GitHub App install ≠ `/web-setup`.** `/web-setup` grants cloning; GitHub triggers additionally require installing the Claude GitHub App on the repo. The trigger setup prompts for this.
7. **Daily run cap + subscription usage counter.** Routines count against both. Check consumption at [claude.ai/settings/usage](https://claude.ai/settings/usage). Organizations with extra usage can overage past the cap; without it, runs are rejected.
8. **Individual account, not team.** Routines belong to you. Commits, PRs, and connector actions appear under your GitHub identity and linked services.
9. **Not available on Bedrock, Vertex, Foundry, or ZDR.** The web infrastructure is unreachable from those platforms.
10. **GitHub trigger hourly caps.** During research preview, per-routine and per-account hourly webhook caps drop events beyond the limit until the window resets.

## Trigger via CLI

```bash
/schedule run quality-sweep-cloud
```

## Trigger via API (programmatic)

See `premerge-gate-routine.md` for the `/fire` endpoint pattern, bearer-token handling, and GitHub Actions / GitLab CI snippets.

## See Also

- `scheduled-sweeps.md` — comparison of the three scheduling surfaces
- `desktop-sweep-template.md` — local primary
- `premerge-gate-routine.md` — API-triggered CI gate
