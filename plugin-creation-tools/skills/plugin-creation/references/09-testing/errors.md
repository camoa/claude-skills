# Errors Reference

Plugin authors encounter two categories of errors: **runtime** errors (returned by the Claude Code session when a plugin's component runs) and **plugin-loading** errors (surfaced when a plugin is installed, updated, or loaded at session start).

Your `/plugin-creation-tools:validate` output should use the official error names in this page so users can cross-reference with Claude Code's own diagnostics (`claude plugin list`, `/doctor`).

## Plugin-loading errors

Surfaced in `claude plugin list`, the `/plugin` interface, and `/doctor`. Read programmatically via `claude plugin list --json` — check the `errors` field on each plugin.

### Dependency errors

| Error | Meaning | Resolution |
|-------|---------|------------|
| `range-conflict` | Combined version ranges have no common satisfying version, or a range uses invalid semver syntax. | Uninstall or update one of the conflicting plugins; fix invalid `version` strings; simplify long `\|\|` chains. |
| `dependency-version-unsatisfied` | The installed dependency's version is outside this plugin's declared range. | `claude plugin install <dependency>@<marketplace>` to re-resolve. |
| `no-matching-tag` | The dependency's repository has no `{name}--v*` tag satisfying the range. | Check upstream tagging convention; relax the range if appropriate. |

See [`../08-configuration/plugin-json.md#dependencies-version-constrained`](../08-configuration/plugin-json.md) for the full resolution model.

### Manifest errors

These fire when `plugin.json` or `marketplace.json` fails validation. Exact error strings vary by Claude Code version; the validator should surface all of them:

| Symptom | What's wrong |
|---------|--------------|
| Missing `source` key on a marketplace plugin entry | v3.0.0 renamed `type` → `source`; old entries fail. |
| `http` hook in `hooks.json` silently ignored | HTTP hooks must be configured in `settings.json`, not plugin `hooks.json`. |
| Plugin name collides with reserved marketplace names | Rename; reserved list: `claude-code-marketplace`, `claude-code-plugins`, `claude-plugins-official`, `anthropic-marketplace`, `anthropic-plugins`, `agent-skills`, `life-sciences`, `knowledge-work-plugins`. |
| Plugin name not kebab-case or contains invalid chars | Use kebab-case, no spaces, no slashes. |
| Path traversal outside plugin root | Symlinks or `../` references fail after install-time cache copy — restructure so all files are under the plugin root. |
| Duplicate component names (two skills/commands/agents with the same name) | Rename or namespace. |
| Missing/invalid YAML frontmatter on a skill or agent | Fix the frontmatter block. |
| `hooks.json` parse failure | Hard-blocks the plugin from loading. JSON-validate before shipping. |

## Runtime errors (session)

Runtime errors surface during session execution — usually while a plugin's hook, skill, or MCP server is active. Most map to an underlying Claude API error; see the [upstream error reference](https://docs.claude.com/en/errors) for HTTP status definitions.

### Auto mode

| Symptom | Category |
|---------|----------|
| `<model> is temporarily unavailable, so auto mode cannot determine the safety of <tool>...` | Transient classifier outage. Retry in a few minutes. Not a plugin bug. |
| Repeated classifier denials (3 consecutive, 20 total) | Auto mode pauses; session resumes prompting. Not a plugin failure — log the `reason` from `PermissionDenied` hooks to tune allow-rules. |

### Authentication

| Error | Meaning |
|-------|---------|
| `Not logged in` | User has no active OAuth or API key. Plugins that require Anthropic-hosted features fail here. |
| `Invalid API key` | Key is present but invalid. Check `env \| grep ANTHROPIC` — direnv/dotenv tools can inject stale keys. |
| `This organization has been disabled` | Workspace/org issue, not a plugin issue. |
| `OAuth token revoked or expired` | Re-auth with `claude login`. |

### Usage limits

| Error | Meaning |
|-------|---------|
| `You've hit your session limit` | User plan limit. Your plugin cannot recover this. |
| `Request rejected (429)` | Rate-limited. Back off; retry. |
| `Credit balance is too low` | User billing issue. |

### Request errors

| Error | Meaning |
|-------|---------|
| `Prompt is too long` | Session exceeds the model's context window. See [`../02-philosophy/core-philosophy.md`](../02-philosophy/core-philosophy.md) for plugin-author budget guidance. |
| `Error during compaction: Conversation too long` | Context compaction failed. Advise the user to `/clear` and restart. |
| `Request too large` | Usually an oversized file read or tool input; avoid shipping hooks that dump entire files on stdin. |
| `Extra inputs are not permitted` | Unknown fields in tool/request JSON. Usually a plugin schema mismatch — check your `hooks.json` and `plugin.json` against the latest schema. |

### Model availability

| Error | Meaning |
|-------|---------|
| `There's an issue with the selected model` | Model misconfigured for the account/plan. |
| `Claude Opus is not available with the Claude Pro plan` | Plan-tier restriction. |
| `thinking.type.enabled is not supported for this model` | Hook using `type: prompt` or `type: agent` set `thinking` on a non-thinking model. |
| `Thinking budget exceeds output limit` | Adjust `thinking.budget_tokens`. |

## Validator alignment checklist

When writing validator messages in `/plugin-creation-tools:validate`:

- [ ] Use the **exact error name** from the upstream docs (e.g. `range-conflict`, not "dependency version conflict")
- [ ] Link the user back to the section in this file that explains resolution
- [ ] For manifest errors, name the failing field and line number where possible
- [ ] Emit **warnings** (not errors) for best-practice violations like broad matchers without `if` fields

## See Also

- Upstream: [Error reference](https://docs.claude.com/en/errors)
- [`../08-configuration/plugin-json.md`](../08-configuration/plugin-json.md) — manifest schema
- [`../08-configuration/marketplace-json.md`](../08-configuration/marketplace-json.md) — marketplace schema
- [`../06-hooks/hook-events.md`](../06-hooks/hook-events.md) — `PermissionDenied` event for classifier-denial handling
- [`testing.md`](testing.md) — testing plugins
- [`debugging.md`](debugging.md) — debugging strategies
