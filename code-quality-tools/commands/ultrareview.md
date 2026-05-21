---
description: Run Claude Code's cloud-hosted multi-agent deep code review (/ultrareview) with pre-flight platform checks and cost transparency. Use when user says "deep review", "pre-merge review", "ultrareview", "cloud review", "rigorous review", "thorough review", "find bugs before merge", "multi-agent review", "verified review".
allowed-tools: Bash, Read
argument-hint: "[PR-number]"
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

- Amazon Bedrock
- Google Cloud Vertex AI
- Microsoft Foundry
- Organizations with Zero Data Retention (ZDR) enabled
- API-key-only authentication (requires Claude.ai login via `/login`)

Only Bedrock and Vertex expose local env vars. **Foundry, ZDR, and API-only cannot be reliably detected from the shell** — for those, the built-in `/ultrareview` itself will refuse with a platform error when the session tries to launch. Warn the user accordingly.

Check the env-var-detectable platforms. Treat only truthy values as "set" (empty, `0`, `false`, `no` mean disabled even if the variable exists):

```bash
PLATFORM=""
is_truthy() { case "${1:-}" in ""|0|false|no|off|FALSE|NO|OFF) return 1 ;; *) return 0 ;; esac; }
if is_truthy "${ANTHROPIC_BEDROCK_BASE_URL:-}" || is_truthy "${CLAUDE_CODE_USE_BEDROCK:-}"; then
  PLATFORM="Bedrock"
fi
if is_truthy "${ANTHROPIC_VERTEX_BASE_URL:-}" || is_truthy "${CLAUDE_CODE_USE_VERTEX:-}"; then
  PLATFORM="Vertex"
fi
```

If an env-detectable platform matches, STOP and respond:

> `/ultrareview` is not available on {platform}. It runs on Claude Code on the web infrastructure, which is not reachable from Bedrock/Vertex/Foundry and is unavailable to organizations with Zero Data Retention enabled.
>
> Alternatives:
> - `/code-quality:review <path>` — local single-pass rubric review
> - `@claude review once` — one-off GitHub-side review (requires managed Code Review enabled on the repo)
> - `/code-quality:audit` — full local audit (PHPStan/ESLint + security scans)

If no env var matched, proceed — but tell the user:

> Pre-flight only detects Bedrock and Vertex locally. If you're on Foundry, a ZDR organization, or authenticated with an API key only, the built-in `/ultrareview` will refuse at session launch. If that happens, run `/login` and sign in with Claude.ai, or fall back to `/code-quality:review`.

### Step 2 — Cost Transparency

`/ultrareview` bills as extra usage — not included usage. On first invocation per session, show:

> **Ultrareview runs on Anthropic cloud infrastructure and bills as extra usage** (separate from your plan's included tokens).
>
> | Plan | Included free runs | After free runs |
> |---|---|---|
> | Pro / Max | 3 free runs (one-time, never refresh) | $5–$20 per run |
> | Team / Enterprise | none | $5–$20 per run |
>
> Usage credits must be enabled on the account. Run `/usage-credits` to check or change the setting. If disabled, `/ultrareview` will block and link to billing settings.
>
> A review takes 5–10 minutes and runs in the background — track it with `/tasks`.

### Step 3 — Argument Validation + GitHub Remote Check (PR Mode Only)

If `$ARGUMENTS` is non-empty, validate it is a pure positive integer PR number — reject `#1234`, `PR-1234`, `https://github.com/owner/repo/pull/1234`, or anything with leading/trailing whitespace:

```bash
ARGS="${ARGUMENTS// /}"
if [ -n "$ARGS" ] && ! printf '%s' "$ARGS" | grep -qE '^[1-9][0-9]{0,6}$'; then
  INVALID=1
fi
```

If `INVALID=1`, STOP:

> PR mode expects a positive integer (e.g. `1234`). Got: `$ARGUMENTS`. Strip any `#`, `PR-`, or URL prefix and retry.

If `$ARGS` is a valid integer, also verify a `github.com` remote exists:

```bash
git remote -v | grep -q 'github.com' || echo "NO_GITHUB"
```

If missing, STOP:

> PR mode requires a `github.com` remote. Either push your branch to GitHub and retry, or run `/code-quality:ultrareview` (no arguments) to review your local branch diff instead.

### Step 4 — Hand Off to the Built-in /ultrareview

A command body cannot invoke another *slash* command, so the interactive `/ultrareview` must be run by the user. (This limitation does **not** apply to CI/headless use — the `claude ultrareview` CLI subcommand *is* Bash-invokable; see "CI / Headless Mode" below.) After the pre-flight passes, tell the user:

> Pre-flight passed. Run `/ultrareview $ARGUMENTS` to start the review.
>
> The built-in will show a confirmation dialog with the file/line count, remaining free runs, and estimated cost before the session launches. Monitor progress with `/tasks` — the review runs in the background, so you can keep coding or close the terminal.

## CI / Headless Mode (`claude ultrareview`)

For pre-merge gating in CI or scripts, use the `claude ultrareview` CLI subcommand instead of the interactive slash command. It launches the same cloud review, blocks until the remote review finishes, prints findings to stdout, and returns an exit code — so a pipeline step can gate on it directly. Unlike the `/ultrareview` slash command, this subcommand runs from a Bash step.

### Invocation

```bash
claude ultrareview                 # diff: current branch vs default branch
claude ultrareview 1234            # GitHub PR #1234
claude ultrareview origin/main     # diff vs an explicit base branch
```

Invoking the subcommand counts as consent for the billing/terms prompt the interactive command shows.

### Flags

| Flag | Effect |
|---|---|
| `--json` | Print the raw `bugs.json` payload instead of the formatted findings |
| `--timeout <minutes>` | Maximum minutes to wait for the review to finish (default 30) |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Review completed — with or without findings |
| `1` | Failed to launch, the remote session errored, or the timeout elapsed |
| `130` | Interrupted with Ctrl-C — the remote review keeps running; follow the session URL printed to stderr |

Progress messages and the live session URL go to **stderr**; findings go to **stdout**, so stdout stays parseable.

### Gating snippet

```bash
claude ultrareview --json "${BASE:-origin/main}" --timeout 20 > ultrareview.json
rc=$?
[ "$rc" -eq 0 ] || { echo "ultrareview failed (rc=$rc)"; exit 1; }
# bugs.json field names are not published — verify against a real run before relying on this filter.
jq -e '[.bugs[]? | select(.severity=="high" or .severity=="critical")] | length == 0' ultrareview.json \
  || { echo "ultrareview found blocking bugs"; jq '.bugs' ultrareview.json; exit 1; }
```

### Cost discipline for CI

A run that fails or is stopped **still consumes** one of the three free Pro/Max runs; paid runs bill $5–$20 as usage credits. Reserve `claude ultrareview` for merge-ready / release branches — do **not** wire it to `on: push`. For every-push gating use the cheaper local `/code-quality:audit --json`; use `claude ultrareview --json` only as a release-gate step. The Step 1 pre-flight platform constraints (Bedrock/Vertex/Foundry/ZDR/API-key-only) apply to the subcommand identically — it has the same authentication and usage-credit requirements as `/ultrareview`.

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
