#!/usr/bin/env bash
# block-dangerous-commands.sh — PreToolUse guardrail (OPT-IN): blocks a small set of
# destructive git/shell command patterns before Bash executes them.
#
# NOT WIRED into hooks.json — this plugin never installs it by default (that would
# hijack every installer's git). The ONLY wiring path is /install-guardrails writing
# a PreToolUse "Bash" matcher into the USER'S chosen settings.json when they opt in.
#
# OPT-IN CONVENIENCE GATE, NOT A SECURITY BOUNDARY. It is friction against an
# accidental destructive command in an agentic session — not a sandbox, not a
# permission system. It is exactly as strong as the pattern list below (a
# differently-phrased or obfuscated command bypasses it) and it is FAIL-OPEN on
# any parse failure — see below. This is the mirror-image posture of
# scripts/wo-mode-gate.sh's fail-CLOSED irreversible boundary: that gate guards a
# real irreversible choke point (PR open) and must never silently allow; this one
# guards convenience and must never silently brick the session.
#
# KNOWN REMAINING LIMITATIONS (documented, not fixed — this is a convenience
# gate, not a security boundary; closing these would mean parsing the shell
# grammar, which is out of scope for a substring-match script):
#   - `git -C <path> push`-style commands: the flag/path inserted between
#     `git` and the subcommand is not normalized away, so a pattern like
#     "git push" may fail to match and the command slips through.
#   - Quoted/escaped forms, e.g. `git "push"` or `git 'reset' --hard`: shell
#     quoting is not stripped before matching, so these may evade the
#     substring check entirely.
#   - Dangerous strings mentioned inside a SAFE command's arguments, e.g.
#     `git commit -m "rm -rf /"`: the match is purely textual against the
#     whole command line, so a safe command can be over-caught (false BLOCK)
#     if a blocked phrase appears inside a quoted argument like a commit
#     message.
#
# FAIL-OPEN BY DESIGN: if jq is missing, stdin is empty/unreadable, or the payload
# has no .tool_input.command (including every non-Bash tool call — those payloads
# carry no .command), this exits 0 (allow). A guardrail that fails CLOSED on parse
# error would block every tool call in the session on a transient hiccup — worse
# than the destructive command it is trying to prevent.
#
# Override: set AIDA_ALLOW_DANGEROUS=1 to skip all checks for this call (e.g. the
# user genuinely wants to run `git push --force` and knows it).
#
# Usage (wired as a PreToolUse "Bash" matcher hook): reads the hook JSON payload
# from stdin, e.g. {"tool_input": {"command": "git push origin main"}}.
#
# Exit codes: 0 = allow (no match / non-Bash / override / parse failure).
#             2 = BLOCK (stderr carries the reason; Claude Code surfaces it and
#                 does not run the command).

set -u

# Explicit opt-out override — checked first, before touching stdin/jq at all.
if [ "${AIDA_ALLOW_DANGEROUS:-}" = "1" ]; then
  exit 0
fi

# Never crash: no jq → fail open.
command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD="$(cat 2>/dev/null || true)"
[ -n "$PAYLOAD" ] || exit 0

# Not Bash / no command field → empty string → allow. Malformed JSON → jq fails → allow.
CMD="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$CMD" ] || exit 0

# Whitespace-normalize before matching: collapse runs of spaces/tabs to a single
# space so "git  push" (double space) and "git<TAB>push" (literal tab) still hit
# the substring patterns below. This kills the double-space/tab false-negatives
# for every pattern in one place instead of needing a variant per pattern.
CMD_NORM="$(printf '%s' "$CMD" | tr -s ' \t' ' ')"

# git checkout . / git restore . are special-cased (not in the generic loop
# below) because they must match "." as a WHOLE ARGUMENT, not as a filename
# prefix — the generic substring loop would also match "git checkout .gitignore"
# or "git restore .env", which are safe, common commands. Anchored end-of-string
# and followed-by-space cases together cover "git checkout ." and
# "git checkout . && foo" while leaving "git checkout .gitignore" alone.
case "$CMD_NORM" in
  *"git checkout ."|*"git checkout . "*)
    printf "BLOCKED: %s matches dangerous pattern 'git checkout .' — the guardrail is preventing this. Remove the guardrail or run it yourself if intended.\n" "$CMD" >&2
    exit 2
    ;;
esac
case "$CMD_NORM" in
  *"git restore ."|*"git restore . "*)
    printf "BLOCKED: %s matches dangerous pattern 'git restore .' — the guardrail is preventing this. Remove the guardrail or run it yourself if intended.\n" "$CMD" >&2
    exit 2
    ;;
esac

DANGEROUS_PATTERNS=(
  "git push"
  "git reset --hard"
  "git clean -f"
  "git clean -fd"
  "git branch -D"
  "push --force"
  "--force-with-lease"
  "reset --hard"
  "rm -rf /"
  "rm -rf ~"
  "rm -rf ."
  "rm -rf *"
  "rm -fr /"
  "rm -fr ~"
  "rm -fr ."
  "rm -fr *"
  "git clean -x"
)

for p in "${DANGEROUS_PATTERNS[@]}"; do
  case "$CMD_NORM" in
    *"$p"*)
      printf "BLOCKED: %s matches dangerous pattern '%s' — the guardrail is preventing this. Remove the guardrail or run it yourself if intended.\n" "$CMD" "$p" >&2
      exit 2
      ;;
  esac
done

exit 0
