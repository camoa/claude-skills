#!/usr/bin/env bash
# The distill sidecar could not say what happened after it was written.
#
# _distill.json carried self_contained and gaps[], with the invariant
# self_contained == (gaps|length == 0). Nothing recorded that a gap was addressed, so an
# orchestrator that acted on one had two wrong options:
#
#   leave the file — it still reads self_contained:false with an open gap, and the next phase
#     goes looking for something already fixed;
#   re-run the agent — it reads self_contained:true, gaps:[], which says nothing was ever wrong
#     and erases the one piece of evidence that the check earned its keep.
#
# Observed live: a Phase 2 distill found a genuine gap (the hub named why the aggregate query
# works but never why the obvious plain condition is wrong), the orchestrator closed it, and then
# had to explain in prose what the record could not.
#
# gaps_closed[] holds {gap, closed_by}. Closing moves an entry across and recomputes
# self_contained, so the invariant is untouched and closing the last gap flips self_contained to
# true while the history survives.
#
# Exit: 0 = schema, agent contract and all three orchestrators agree.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
REF="$ROOT/references/orchestration-context-hygiene.md"
AG="$ROOT/agents/distill-agent.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

grep -q '"gaps_closed"' "$REF" && ok "schema declares gaps_closed" || bad "schema declares gaps_closed"
grep -q 'closed_by' "$REF" && ok "a closed gap records what closed it and where" || bad "a closed gap records what closed it and where"
grep -q 'Closing a gap' "$REF" && ok "the reference states the closing rule" || bad "the reference states the closing rule"
grep -q 'recomputes .self_contained' "$REF" && ok "closing recomputes self_contained rather than hand-setting it" || bad "closing recomputes self_contained"
grep -q 'the \*\*only\*\* edit an orchestrator may make' "$REF" && ok "the orchestrator's write is bounded to this one move" || bad "the orchestrator's write is bounded to this one move"
grep -q 'is not closed' "$REF" && ok "a gap deliberately left open is not recorded as closed" || bad "a gap deliberately left open is not recorded as closed"

# The invariant must survive — the whole point is that it still holds.
grep -q 'self_contained == (gaps | length == 0)' "$REF" \
  && ok "the original invariant is unchanged" || bad "the original invariant is unchanged"

# The agent writes the field empty and never populates it.
grep -q '"gaps_closed": \[\]' "$AG" && ok "the agent emits gaps_closed as []" || bad "the agent emits gaps_closed as []"
grep -q 'never yours' "$AG" && ok "the agent is told populating it is not its job" || bad "the agent is told populating it is not its job"

# All three orchestrators carry the move.
for f in research design scope; do
  C="$ROOT/commands/$f.md"
  grep -q 'move it\*\* from `gaps\[\]`' "$C" \
    && ok "/$f knows to move a closed gap rather than leave or erase it" \
    || bad "/$f knows to move a closed gap rather than leave or erase it"
done

echo "----"
echo "distill-gap-closure-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
