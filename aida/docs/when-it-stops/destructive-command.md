# A command is put to you or refused

A hook reads each command before it runs. A command that throws work away or publishes it, such
as `git push`, is put to you or refused. The full list is on
[after the merge](../stages/completion/after-merge.md).

## What you see

| Where the command runs | What happens |
|---|---|
| The main session, in default, acceptEdits, plan or auto mode | Claude Code shows its permission prompt. The command runs only on your yes. In auto mode the classifier cannot approve it. |
| The main session, in bypassPermissions or dontAsk mode | The hook refuses the command, because no prompt can show there. The message names the mode. |
| A call whose permission mode is not given | The hook refuses the command. |
| A role AIDA dispatched, in every mode | The hook refuses the command, and the role stops. It reports the command to you. |

A write to AIDA's own hooks, or a `disableAllHooks` written into a `.claude` settings file, is
refused in every mode. It is never asked. Those files hold the stops on frozen tests, owned files
and your answer.

## What to do

- **At a prompt.** Read the command in the prompt. Approve it only if you mean it.
- **After a refusal.** Run the command yourself, in your own terminal, if you mean it. For a
  push, push the branch the pull request body names.
- **On an unattended run that must run one of these commands.** Set `AIDA_ALLOW_DANGEROUS=1` in
  the shell that launches the session. It turns the hook off for that whole session.
- **After a role stopped.** Read the command it reports. Decide whether it was needed, then run
  the step again or run the command yourself.

## Why it works this way

- Publishing and throwing work away are a person's acts. A prompt puts each one to you.
- A role has no reason to run these commands. A role told only to stop once deleted the refused
  folder one file at a time, so the refusal now ends the role's turn.
- The hook reads text, not the shell grammar, so it is best effort. A command built in a variable
  or a script file gets past it.

Source: hooks/deny-destructive-commands.sh
