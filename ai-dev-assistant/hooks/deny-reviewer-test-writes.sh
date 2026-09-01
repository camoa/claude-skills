#!/usr/bin/env bash
# deny-reviewer-test-writes.sh — PreToolUse hook: a reviewer cannot write to a test path through the
# Write/Edit tools, or through the plain Bash forms a critic actually types.
#
# Two critics left probe test files inside a reviewed tree. The reviewers (wo-critic,
# architecture-validator, spec-axis-reviewer, prior-art-verdict-confirmer) are read-only on code and
# write only their verdict sidecar; wo-critic also holds Bash, so a Write-only rule is bypassed by a
# redirect. This hook reads the payload's `agent_type` (present inside a sub-agent; measured live on
# Claude Code 2.1.257 as the bare agent name, beside `agent_id`) and denies a write to a test path for
# those agents only. Everyone else passes: a builder's first act under TDD is writing a test.
#
# FAIL-OPEN, and visible where it can be. The main session carries neither field: allow, silent.
# `agent_id` without `agent_type` is a sub-agent this hook cannot name: allow, and say so through
# `systemMessage`, the one hook-output channel the model sees on exit 0 (stderr on exit 0 is not
# shown). It never denies every sub-agent's test write. Unreadable stdin, no jq, no path: allow, silent.
#
# KNOWN LIMITATIONS of the Bash door. It is token-shaped, like block-dangerous-commands.sh: friction
# against the plain forms, not a boundary. A path assembled from a variable, an escaped or
# capitalised path, an encoded or eval'd command, an interpreter (`python -c`, `perl -pi`), `dd of=`,
# `patch`, `git apply`/`checkout`/`stash`, `rsync`, an editor, or a symlink into the test dir all pass.
# The Write/Edit door sees the real path and has none of these.
#
# Deny is the documented JSON form (permissionDecision: deny, permissionDecisionReason shown to the
# model), on exit 0, so the reason reaches the critic and its verdict file is still written.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }
INPUT="$(cat 2>/dev/null)" || { echo '{}'; exit 0; }
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)"; [ -n "$TOOL" ] || { echo '{}'; exit 0; }
AGENT="$(jq -r '.agent_type // empty' <<<"$INPUT" 2>/dev/null)"
AGENT_ID="$(jq -r '.agent_id // empty' <<<"$INPUT" 2>/dev/null)"

case "$AGENT" in
  wo-critic|architecture-validator|spec-axis-reviewer|prior-art-verdict-confirmer|*:wo-critic|*:architecture-validator|*:spec-axis-reviewer|*:prior-art-verdict-confirmer) ;;
  "") if [ -n "$AGENT_ID" ]; then
        jq -nc '{systemMessage:"deny-reviewer-test-writes: not_enforced: sub-agent payload carries agent_id but no agent_type, cannot tell a reviewer from the builder"}'
      else echo '{}'; fi; exit 0 ;;
  *) echo '{}'; exit 0 ;;
esac

# A test path, by the conventions the recipes and this repo use: a test directory anywhere in the
# path, the directory itself, or a test-named file. A verdict sidecar is never a test path, wherever
# the task folder lives.
is_test_path() {
  case "$1" in
    *.critic-*.json|*/build-critique/*|_*.json|*/_*.json) return 1 ;;
    */tests/*|tests/*|*/test/*|test/*|*/__tests__/*|*/spec/*|spec/*) return 0 ;;
    tests|test|__tests__|spec|*/tests|*/test|*/__tests__|*/spec) return 0 ;;
    *-spec.sh|*_spec.sh|*Test.php|*_test.go|*_test.py|test_*.py|*/test_*.py|*.test.js|*.test.ts|*.spec.js|*.spec.ts|*.test.tsx|*.spec.tsx) return 0 ;;
  esac
  return 1
}
deny() { jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
REASON_TAIL="Reviewers are read-only on code: record the finding in your verdict file; run probes in a scratch copy outside the tree."

case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    P="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$INPUT" 2>/dev/null)"
    [ -n "$P" ] || { echo '{}'; exit 0; }
    is_test_path "$P" && deny "reviewer agent '$AGENT' may not write to a test path ($P). $REASON_TAIL"
    ;;
  Bash)
    CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)"
    [ -n "$CMD" ] || { echo '{}'; exit 0; }
    # A test path in the WRITE POSITION only: the target of a stdout redirect, the operand of a
    # deleting or touching verb, the last operand of a copying verb, or a `cd` into a test dir on a
    # line that also redirects. Reading a test file, running a spec (with any stderr redirect), or
    # copying one OUT to scratch is allowed; the deny message tells the critic to do exactly that.
    HIT=""
    while IFS= read -r seg; do
      [ -n "$HIT" ] && break
      set -f; read -r -a w <<<"$(printf '%s' "$seg" | tr '`$"()' '     ' | tr -d "'")"; set +f
      [ "${#w[@]}" -gt 0 ] || continue
      i=0
      while [ "$i" -lt "${#w[@]}" ]; do
        t="${w[$i]}"; n=$((i+1))
        case "$t" in
          '>'|'>>'|'1>'|'1>>'|'&>'|'&>>'|'>|') [ "$n" -lt "${#w[@]}" ] && is_test_path "${w[$n]}" && { HIT="${w[$n]}"; break; } ;;
          '2>'*) ;;
          '>'*|'1>'*|'&>'*) x="${t#&}"; x="${x#1}"; x="${x#>>}"; x="${x#>}"; x="${x#|}"; [ -n "$x" ] && is_test_path "$x" && { HIT="$x"; break; } ;;
        esac
        i=$n
      done
      [ -n "$HIT" ] && break
      case "${w[0]}" in
        rm|touch|truncate|chmod|mkdir|rmdir|tee|unlink)
          for t in "${w[@]:1}"; do case "$t" in -*) continue ;; esac; is_test_path "$t" && { HIT="$t"; break; }; done ;;
        git) case "${w[1]:-}" in rm|mv|checkout|restore|stash|apply|clean|reset)
               for t in "${w[@]:2}"; do case "$t" in -*) continue ;; esac; is_test_path "$t" && { HIT="$t"; break; }; done ;; esac ;;
        sed) case "${w[1]:-}" in -i*) for t in "${w[@]:2}"; do is_test_path "$t" && { HIT="$t"; break; }; done ;; esac ;;
        cp|mv|ln|install|rsync) last="${w[$((${#w[@]}-1))]}"; is_test_path "$last" && HIT="$last" ;;
        cd) is_test_path "${w[1]:-}" && printf '%s' "$CMD" | grep -q '>' && HIT="${w[1]}" ;;
      esac
    done < <(printf '%s\n' "$CMD" | sed -e 's/&&/\n/g; s/||/\n/g; s/[;|]/\n/g')
    [ -n "$HIT" ] && deny "reviewer agent '$AGENT' may not write to a test path through Bash ($HIT). $REASON_TAIL"
    ;;
esac
echo '{}'; exit 0
