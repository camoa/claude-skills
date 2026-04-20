---
description: Run Claude Code's cloud-hosted multi-agent deep code review (/ultrareview) with pre-flight platform checks and cost transparency. Use when user says "deep review", "pre-merge review", "ultrareview", "cloud review", "rigorous review", "thorough review", "find bugs before merge", "multi-agent review", "verified review".
allowed-tools: Bash, Read
argument-hint: [PR-number]
---

# Ultrareview (Deep Cloud Review)

Wrap Claude Code's built-in `/ultrareview` with pre-flight platform compatibility checks and cost transparency. `/ultrareview` launches a fleet of reviewer agents in a remote Anthropic-managed sandbox, independently verifies each finding, and reports back via `/tasks` — best for pre-merge review on substantial changes.

## Usage

```
/code-quality:ultrareview           # review current branch diff vs default (includes uncommitted)
/code-quality:ultrareview 1234      # review GitHub PR #1234 (clones from GitHub)
```

PR mode requires a `github.com` remote on the repository. If the repo is too large to bundle, push the branch and use PR mode.

## What This Does

1. Pre-flight compatibility check (fails cleanly on unsupported platforms)
2. Cost transparency notice on first use of this session
3. Invokes the built-in `/ultrareview` command with `$ARGUMENTS`
4. Points user to `/tasks` to monitor progress

## Instructions

### Step 1 — Pre-flight Platform Check

Ultrareview is NOT available on:

- Amazon Bedrock (`ANTHROPIC_BEDROCK_BASE_URL` set or `/model` shows Bedrock)
- Google Cloud Vertex AI (`ANTHROPIC_VERTEX_BASE_URL` set)
- Microsoft Foundry
- Organizations with Zero Data Retention (ZDR) enabled
- API-key-only authentication (requires Claude.ai login)

Check environment:

```bash
if [ -n "$ANTHROPIC_BEDROCK_BASE_URL" ] || [ -n "$CLAUDE_CODE_USE_BEDROCK" ]; then
  PLATFORM="Bedrock"
fi
if [ -n "$ANTHROPIC_VERTEX_BASE_URL" ] || [ -n "$CLAUDE_CODE_USE_VERTEX" ]; then
  PLATFORM="Vertex"
fi
```

If any unsupported platform is detected, STOP and respond:

> `/ultrareview` is not available on {platform}. It runs on Claude Code on the web infrastructure, which is not reachable from Bedrock/Vertex/Foundry and is unavailable to organizations with Zero Data Retention enabled.
>
> Alternatives:
> - `/code-quality:review <path>` — local single-pass rubric review
> - `@claude review once` — one-off GitHub-side review (requires managed Code Review enabled on the repo)
> - `/code-quality:audit` — full local audit (PHPStan/ESLint + security scans)

### Step 2 — Cost Transparency

`/ultrareview` bills as extra usage — not included usage. On first invocation per session, show:

> **Ultrareview runs on Anthropic cloud infrastructure and bills as extra usage** (separate from your plan's included tokens).
>
> | Plan | Included free runs | After free runs |
> |---|---|---|
> | Pro / Max | 3 free runs (one-time, never refresh) | $5–$20 per run |
> | Team / Enterprise | none | $5–$20 per run |
>
> Extra usage must be enabled on the account. Run `/extra-usage` to check or change the setting. If disabled, `/ultrareview` will block and link to billing settings.
>
> A review takes 5–10 minutes and runs in the background — track it with `/tasks`.

### Step 3 — GitHub Remote Check (PR Mode Only)

If `$ARGUMENTS` looks like a PR number (integer), verify a `github.com` remote exists:

```bash
git remote -v | grep -q 'github.com' || echo "NO_GITHUB"
```

If missing, STOP:

> PR mode requires a `github.com` remote. Either push your branch to GitHub and retry, or run `/code-quality:ultrareview` (no arguments) to review your local branch diff instead.

### Step 4 — Hand Off to the Built-in /ultrareview

After the pre-flight passes, tell the user to run the built-in command themselves (a command body cannot invoke another slash command directly):

> Pre-flight passed. Run `/ultrareview $ARGUMENTS` to start the review.
>
> The built-in will show a confirmation dialog with the file/line count, remaining free runs, and estimated cost before the session launches. Monitor progress with `/tasks` — the review runs in the background, so you can keep coding or close the terminal.

## When to Use This vs `/code-quality:review`

| `/code-quality:review <path>` | `/code-quality:ultrareview` |
|---|---|
| Local, single-pass | Cloud, multi-agent fleet |
| Seconds to a few minutes | 5–10 minutes |
| Counts toward included usage | Free runs, then $5–$20 per run as extra usage |
| Rubric-scored (/50), persists report | Inline findings verified against code behavior |
| Use while iterating | Use pre-merge on substantial changes |

## See also

- `/code-quality:review` — local rubric-scored single-pass review
- `/code-quality:audit` — full local audit (all tools, no rubric)
- `/code-quality:generate-review-md` — tune managed Code Review (separate from ultrareview)
- `skills/code-quality-audit/references/scheduled-sweeps.md` — scheduling reviews across local and cloud surfaces
