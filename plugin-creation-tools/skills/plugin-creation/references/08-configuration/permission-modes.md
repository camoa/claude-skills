# Permission Modes

Permission modes control how often Claude pauses to ask before editing files, running commands, or making network requests. Plugin authors need to understand them because hooks, skills, and subagents behave differently in each mode — and some of those differences are load-bearing for security.

## The six modes

| Mode | What runs without asking | Best for |
|------|--------------------------|----------|
| `default` | Reads only | Sensitive work, getting started |
| `acceptEdits` | Reads, file edits, and common filesystem commands (`mkdir`, `touch`, `mv`, `cp`, `rm`, `rmdir`, `sed`) | Iterating on code you're reviewing |
| `plan` | Reads only — Claude writes a plan but does not edit source | Exploring a codebase before changing it |
| `auto` | Everything, with a classifier running background safety checks | Long tasks, reducing prompt fatigue |
| `dontAsk` | Only pre-approved tools (`permissions.allow` rules + [read-only Bash commands](https://docs.claude.com/en/permissions#read-only-commands)) | Locked-down CI and scripts |
| `bypassPermissions` | Everything except protected paths — no checks, no prompts | Isolated containers and VMs only |

Modes set the **baseline**. [Permission rules](https://docs.claude.com/en/permissions#manage-permissions) (allow/ask/deny) layer on top of every mode except `bypassPermissions`, which skips the permission layer entirely.

## How modes change hook behavior

This is the table plugin authors most need. A hook that's safe in `default` can be silently dangerous in `auto` or `bypassPermissions`.

| Hook event / return | `default` | `acceptEdits` | `plan` | `auto` | `dontAsk` | `bypassPermissions` |
|---------------------|-----------|---------------|--------|--------|-----------|---------------------|
| `PreToolUse` fires | yes | yes | yes (reads only) | yes | yes | yes |
| `PreToolUse` `deny` honored | yes | yes | yes | yes | yes | yes |
| `PreToolUse` `ask` honored | yes | yes | yes | yes | no — falls back to default | no — bypassed |
| `PermissionRequest` fires | when dialog shown | when dialog shown | when dialog shown | **only when a prompt actually happens** (rare in auto) | never (no dialogs) | never |
| `PermissionDenied` fires | no | no | no | **yes** — classifier denials | no | no |
| `PostToolUse` / `PostToolUseFailure` fires | yes | yes | yes | yes | yes | yes |

**Takeaways:**
- `PreToolUse` is the only guardrail that runs in every mode. Treat it as the lowest-common-denominator safety hook.
- `PermissionRequest` hooks only fire when a dialog would have been shown. In `auto` and `dontAsk`, they may never fire — do not rely on them for security-critical logic.
- `PermissionDenied` is **exclusive to `auto` mode** — it fires when the classifier denies a call. Use it to log denials or tell the model it may retry (`{retry: true}`).

## Auto mode specifics

`auto` is the riskiest mode for plugin authors to design around because it suppresses the prompts that normally surface unsafe actions.

**How it decides** (in order):
1. Matching `allow` / `deny` rules resolve immediately
2. Read-only actions and edits to the working directory are auto-approved (except [protected paths](#protected-paths))
3. Everything else goes to the classifier
4. The classifier denies anything that escalates beyond the request, targets unrecognized infrastructure, or looks driven by hostile content

**What auto drops on entry:**
- Blanket `Bash(*)`
- Wildcarded interpreters like `Bash(python*)`
- Package-manager run commands
- `Agent` allow rules

Narrow rules like `Bash(npm test)` carry over. Dropped rules are restored when leaving auto mode.

**Fallback thresholds:**
- 3 consecutive classifier denials, or 20 total denials → auto pauses, Claude resumes prompting
- Approving the prompted action resumes auto
- In `-p` headless mode, repeated blocks abort the session

**Requirements** (auto is gated):
- Plan: Max, Team, Enterprise, or API (not Pro)
- Admin enablement on Team/Enterprise
- Model: Sonnet 4.6, Opus 4.6, or Opus 4.7 (Team/Enterprise/API); Opus 4.7 only on Max
- Provider: Anthropic API only (not Bedrock, Vertex, or Foundry)

## Subagent inheritance

Subagents inherit the parent's permission mode. `permissionMode` in a subagent's frontmatter is **ignored** in auto mode — the classifier re-evaluates every subagent action against the parent's rules.

The classifier also:
1. Checks the subagent's task description **before spawn**
2. Checks each action during execution
3. Reviews the full action history when the subagent finishes — if something flags, a security warning is prepended to the subagent's results

For plugin agents specifically: `hooks`, `mcpServers`, and `permissionMode` are **silently ignored** in plugin-packaged agents as a security measure, regardless of mode.

## Protected paths (all modes)

Writes to these paths are **never** auto-approved, in any mode. In `default`/`acceptEdits`/`plan`/`bypassPermissions` they prompt; in `auto` they route to the classifier; in `dontAsk` they are denied.

**Directories:**
- `.git`, `.vscode`, `.idea`, `.husky`
- `.claude` — except `commands/`, `agents/`, `skills/`, and `worktrees/` subdirectories

**Files:**
- `.gitconfig`, `.gitmodules`
- `.bashrc`, `.bash_profile`, `.zshrc`, `.zprofile`, `.profile`
- `.ripgreprc`
- `.mcp.json`, `.claude.json`

## Guidance for plugin authors

1. **Write hooks that work in every mode.** Don't assume the user will review a prompt. In `auto` and `bypassPermissions`, hooks are the only barrier.
2. **Use `PreToolUse` for hard safety, not `PermissionRequest`.** `PermissionRequest` can be skipped entirely in `auto`/`dontAsk`.
3. **Pair broad matchers with the `if` field.** Narrow the pre-spawn filter so your hook doesn't become a no-op in `auto` where every action reaches you.
4. **Log `PermissionDenied` in `auto` mode.** Classifier denials are useful signal for tuning allow-rules and spotting false positives.
5. **Don't rely on `ask` in `dontAsk`.** It silently falls back to the default — your hook logic will never see the approval.
6. **For `bypassPermissions`, assume zero user oversight.** Document this explicitly in your plugin's README if it ships hooks that matter.

## How users switch modes

- **CLI**: `Shift+Tab` to cycle `default` → `acceptEdits` → `plan`. Optional modes (`auto`, `bypassPermissions`) slot in after `plan` when enabled. `dontAsk` never appears in the cycle — set it with `--permission-mode dontAsk`.
- **At startup**: `claude --permission-mode plan` (works with `-p` for headless).
- **As default**: `permissions.defaultMode` in [settings.json](settings.md).
- **VS Code / Desktop / Web**: mode selector in the UI.

Administrators can lock modes off via [managed settings](https://docs.claude.com/en/permissions#managed-settings):
- `permissions.disableAutoMode: "disable"` blocks `auto`
- `permissions.disableBypassPermissionsMode: "disable"` blocks `bypassPermissions`

## See Also

- [`../06-hooks/writing-hooks.md`](../06-hooks/writing-hooks.md) — Permission Mode Interaction section
- [`../06-hooks/hook-events.md#permissiondenied`](../06-hooks/hook-events.md) — PermissionDenied details
- [`plugin-json.md`](plugin-json.md) — plugin manifest (plugin-packaged agents strip `permissionMode`)
- Upstream: [Permission Modes](https://docs.claude.com/en/permission-modes), [Permissions](https://docs.claude.com/en/permissions)
