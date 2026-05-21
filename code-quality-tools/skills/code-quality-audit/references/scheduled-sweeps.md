# Scheduled Quality Sweeps — Pick the Right Surface

Claude Code ships three distinct scheduling surfaces. Picking the wrong one is the most common failure mode for quality automation. For this plugin, local surfaces often beat cloud because local has access to DDEV containers, composer autoload cache, drush, and uncommitted work.

## Comparison

|                            | [Desktop Scheduled Tasks](#desktop--primary) | [Cloud Routines](#cloud-routines--fallback) | [`/loop`](#loop--in-session-only) |
|---|---|---|---|
| Runs on                    | Your machine             | Anthropic cloud         | Your machine (in-session) |
| Requires machine on        | Yes                      | No                      | Yes                       |
| Requires open session      | No                       | No                      | Yes                       |
| Access to local files      | Yes (incl. uncommitted)  | No (fresh clone)        | Yes                       |
| Minimum interval           | 1 minute                 | 1 hour                  | 1 minute                  |
| Permission prompts         | Configurable per task    | None (autonomous)       | Inherits session          |
| Missed runs                | One catch-up on wake     | Server-side reliable    | Dies when session exits   |
| Persistent across restarts | Yes                      | Yes                     | Restored via `--resume`   |

## Decision Tree

```
Start here:

- Need DDEV, composer autoload, drush, or uncommitted work?       → Desktop
- Need GitHub event trigger (PR opened, release published)?        → Cloud Routine
- Need CI pipeline to trigger the run (curl from GitHub Actions)?  → Cloud Routine (API trigger)
- Need machine-off reliability, laptop frequently closed?          → Cloud Routine
- Polling status during an active session ("did CI finish")?       → /loop
- All of the above?                                                → Desktop primary, Cloud fallback
```

### Desktop — PRIMARY for this plugin

Local files, 1-minute minimum interval, runs on your machine with direct access to running DDEV containers, composer vendor cache, `.env.local`, uncommitted changes, and local MCP servers. Missed runs during sleep catch up once on wake.

Best for:

- **Daily local audit.** `/code-quality:audit` at 7am against your working copy, report to `.reports/quality-YYYY-MM-DD.md` before you start coding.
- **Hourly security watch.** `/code-quality:security` while iterating — catches regressions in near-real-time.
- **Pre-commit sweep.** Run before your end-of-day commit so morning-you inherits a clean state.

Template: `desktop-sweep-template.md`

### Cloud Routines — fallback

Runs on Anthropic cloud, 1-hour minimum interval, no permission prompts (must scope tightly). Repository is fresh-cloned from the default branch on every run, so the routine cannot see uncommitted work. Can react to GitHub events and has an HTTP `/fire` endpoint for CI triggering.

Best for:

- **Machine-off weekly sweeps.** Team wants server-side reliability regardless of individual laptops.
- **PR auto-review on GitHub events.** Runs on `pull_request.opened` — Desktop can't.
- **API-triggered pre-merge gate from CI.** `curl` from GitHub Actions / GitLab CI hits `/fire`, routine runs the audit, results posted back.

Template: `cloud-routine-sweep.md`. API-triggered CI gate: `premerge-gate-routine.md`.

### `/loop` — in-session only

Session-scoped polling. Dies when the session exits. 3-day auto-expiry. Inherits session permissions and MCP config.

Best for:

- `/loop 30m /code-quality:lint` while actively coding
- `/loop 5m "check if CI has finished on the current branch"`

Not for: production quality automation — restart the session and the loop is gone.

**`/loop` vs `/goal`:** `/loop` re-runs a prompt on a fixed **time interval** and stops only when you stop it. `/goal` re-runs after every turn and stops when a fresh evaluator model confirms a **completion condition** from the transcript — use it for "audit until clean" / "fix until tests pass" loops (see `commands/audit.md` and `commands/tdd.md`). Neither is a CI primitive: both keep the current session running.

## See Also

- `desktop-sweep-template.md` — full Desktop Scheduled Task template (primary)
- `cloud-routine-sweep.md` — Cloud Routine template (fallback)
- `premerge-gate-routine.md` — API-triggered pre-merge CI gate
- Upstream: [`/en/desktop-scheduled-tasks`](https://docs.claude.com/en/desktop-scheduled-tasks), [`/en/routines`](https://docs.claude.com/en/routines), [`/en/scheduled-tasks`](https://docs.claude.com/en/scheduled-tasks)
