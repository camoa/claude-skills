# Permissions in the SDK

The Agent SDK uses the same [permission modes](../08-configuration/permission-modes.md) as the CLI, plus two SDK-specific mechanisms: the `allowed_tools` / `disallowed_tools` options and the `canUseTool` callback.

This page covers how the two layers compose. For mode semantics themselves, see [`../08-configuration/permission-modes.md`](../08-configuration/permission-modes.md).

## Evaluation order

When Claude requests a tool inside an SDK session:

1. **Hooks** run first (same hook events as CLI). They can allow, deny, or fall through.
2. **Deny rules** (`disallowed_tools` + `settings.json` deny) — always win, even in `bypassPermissions`.
3. **Permission mode** decides: `bypassPermissions` approves everything else; `acceptEdits` approves file ops; other modes fall through.
4. **Allow rules** (`allowed_tools` + `settings.json` allow) — approve if matched.
5. **`canUseTool` callback** — your code decides. Skipped entirely in `dontAsk` (tool is denied).

## Allow and deny lists

```python
options = ClaudeAgentOptions(
    allowed_tools=["Read", "Grep"],        # pre-approved
    disallowed_tools=["Bash"],             # always denied
)
```

**Key nuance:** `allowed_tools` adds entries to the **allow rule list**. It does **not** restrict which tools exist. Unlisted tools fall through to the permission mode.

| Config | Outcome |
|--------|---------|
| `allowed_tools=["Read"]`, mode=`default` | `Read` auto-approved; `Bash` falls to `canUseTool` |
| `allowed_tools=["Read"]`, mode=`bypassPermissions` | `Read` approved; **every other tool also approved** — `bypassPermissions` skips the allow-rule layer |
| `disallowed_tools=["Bash"]`, mode=`bypassPermissions` | `Bash` denied; everything else approved |
| `allowed_tools=["Read"]`, mode=`dontAsk` | `Read` approved; everything else denied silently |

**Rule of thumb:** `allowed_tools` pre-approves; `disallowed_tools` hard-blocks. Use both together for a locked-down surface.

## The `canUseTool` callback

`canUseTool` is the SDK's runtime-decision hook. It fires for every tool call that isn't resolved by hooks, deny rules, the mode, or allow rules. Your callback returns an approval decision with optional input modification.

```typescript
const options = {
  canUseTool: async (toolName, input) => {
    if (toolName === "Write" && input.file_path?.includes("/.env")) {
      return { behavior: "deny", message: "Writes to .env blocked" };
    }
    return { behavior: "allow", updatedInput: input };
  },
};
```

```python
async def can_use_tool(tool_name, input, context):
    if tool_name == "Write" and "/.env" in input.get("file_path", ""):
        return {"behavior": "deny", "message": "Writes to .env blocked"}
    return {"behavior": "allow", "updatedInput": input}

options = ClaudeAgentOptions(can_use_tool=can_use_tool)
```

Uses:
- Run a user-facing prompt to approve/deny
- Enforce app-specific policies the declarative rules don't cover
- Modify tool input (redact secrets, normalize paths) before execution
- Log every tool call for audit

In `dontAsk` mode the callback is **skipped** — unmatched tools are denied outright.

## Plugin-author patterns

### Pattern 1: Validator with a locked tool surface

A plugin validator running via the SDK should pin its permissions:

```python
options = ClaudeAgentOptions(
    allowed_tools=["Read", "Grep", "Glob"],
    disallowed_tools=["Write", "Edit", "Bash"],
    permission_mode="dontAsk",  # denials are silent, no callback needed
)
```

This is the minimum surface for a read-only inspection agent.

### Pattern 2: `canUseTool` with a quarantine allowlist

For plugin test harnesses that need Bash but only for a small set of commands:

```python
SAFE_BASH = {"npm test", "npm run lint", "git status"}

async def can_use_tool(name, input, ctx):
    if name == "Bash":
        cmd = input.get("command", "").strip()
        if cmd in SAFE_BASH:
            return {"behavior": "allow", "updatedInput": input}
        return {"behavior": "deny", "message": f"Bash command not in allowlist: {cmd}"}
    return {"behavior": "allow", "updatedInput": input}
```

### Pattern 3: Dynamic mode escalation

Start strict, loosen as the session proves safe:

```python
q = query(prompt="...", options=ClaudeAgentOptions(permission_mode="default"))
# ... review first few tool calls ...
await q.set_permission_mode("acceptEdits")  # loosen mid-session
```

### Pattern 4: Respect plugin-packaged agent restrictions

If your SDK app loads skills and agents from a plugin (via `settingSources=["project"]` + installed plugin), remember:
- Plugin-packaged agent `permissionMode` frontmatter is **silently ignored**
- Plugin-packaged agent `hooks` frontmatter is **silently ignored**
- Plugin-packaged agent `mcpServers` frontmatter is **silently ignored**

These are security restrictions. If your plugin needs per-agent permission overrides, ship as a user/project agent, not inside the plugin.

## Subagent inheritance

When the parent uses `bypassPermissions`, `acceptEdits`, or `auto`, **subagents inherit that mode** and cannot override it. A subagent with a less-constrained prompt can take risky actions under inherited permissions. Audit subagent `prompt` strings with this in mind — and prefer `default` + explicit allow rules for sensitive agents.

See [`subagents-sdk.md`](subagents-sdk.md) for subagent inheritance details.

## See Also

- [`../08-configuration/permission-modes.md`](../08-configuration/permission-modes.md) — mode behavior table
- [`../06-hooks/writing-hooks.md`](../06-hooks/writing-hooks.md) — hooks run before allow/deny rules
- [`subagents-sdk.md`](subagents-sdk.md) — permission inheritance into subagents
- Upstream: [Configure permissions](https://docs.claude.com/en/agent-sdk/permissions), [canUseTool callback](https://docs.claude.com/en/agent-sdk/user-input)
