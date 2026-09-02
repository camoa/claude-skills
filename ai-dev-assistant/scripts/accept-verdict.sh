#!/usr/bin/env bash
# accept-verdict.sh — the 7 pure decisions behind the repair accept verdict block in
# build-critique-assert.sh (the section commented "the repair accept verdict (v5.42.0+)").
#
# SOURCE this file (do not execute it). Each function takes the record's PAYLOAD as $1 and
# nothing else, and answers ONE of the 7 questions build-critique-assert.sh's accept block
# asks: is a field readable, and if so, which components trip it. Nothing here formats a
# message, sets an evidence key, or exits — that stays in the caller, exactly as
# architecture.md for the `tdd_knowledge_ownership` task requires. A function that both
# decided and called emit would not be a unit, it would be the whole check with a name.
#
# THE RETURN CONVENTION, stated once and applied eight times: echo the JSON value, or echo
# the literal $JQ_ERR sentinel, and return 0 either way. Never signal the jq failure with a
# non-zero exit status — the caller compares the returned STRING against $JQ_ERR, and nothing
# here reads a bash exit code.
#
# WAS EIGHT UNTIL v5.47.0. `accept_unreadable_round_components` disambiguated a `rounds[]`
# entry whose round number was absent or non-numeric. A component now gets at most one critic
# round, so no `rounds[]` entry is written and that question has no subject. Deleted with the
# reading rather than left as a check that cannot fire.
#
# Every jq query below is moved verbatim from build-critique-assert.sh. Not retyped, not
# tidied, not reformatted — a reformatted query is an unreviewable diff, and the whole claim
# of this file is that behaviour did not move. See
# research/subject-accept-block-anatomy.md and architecture.md in the
# `tdd_knowledge_ownership` task for the anatomy this was extracted from.

ACCEPT_ACTIONS='["accepted","not_accepted","cannot_judge"]'
ACCEPT_SUITES='["green","red","not_run"]'
ACCEPT_DECIDERS='["suite_and_motion","motion","none"]'

# A JQ ERROR IS NOT AN EMPTY RESULT SET. See build-critique-assert.sh's own comment above the
# block this was lifted from: a fallback of '[]' on a jq failure reads as "I looked and found
# nothing wrong", which is a silent pass on a block whose entire purpose is to refuse silent
# passes. JQ_ERR is hoisted here, unconditional, because build-critique-assert.sh reuses this
# same sentinel outside the accept block (its deferred-findings section) — one sentinel, one
# home, rather than two definitions of the same marker string.
JQ_ERR="__jq_error__"

# accept_bad_action_components <payload>
# Components carrying an accept object whose .accept.action is outside the three-value enum,
# or whose .accept is present but not an object at all. Replaces BAD_ACTION.
accept_bad_action_components() {
  local out
  out=$(jq -c --argjson ok "$ACCEPT_ACTIONS" \
    '[(.components // [])[]
      | select(has("accept"))
      | select(if (.accept | type) != "object" then true
               else (((.accept.action // "") | tostring) as $a
                     | ($ok | index($a)) == null) end)
      | (.component // "unnamed")]' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
  printf '%s' "$out"
}

# accept_bad_suite_components <payload>
# Components with an accept object whose .accept.suite is outside the three-value enum.
# Replaces BAD_SUITE.
accept_bad_suite_components() {
  local out
  out=$(jq -c --argjson ok "$ACCEPT_SUITES" \
    '[(.components // [])[]
      | select(has("accept") and ((.accept | type) == "object"))
      | select((((.accept.suite // "") | tostring) as $s | ($ok | index($s)) == null))
      | (.component // "unnamed")]' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
  printf '%s' "$out"
}

# accept_bad_basis_components <payload>
# Components with an accept object where .accept.decided_by is outside the three-value enum,
# OR .accept.reason trims to empty. Replaces BAD_BASIS. Known ceiling, not fixed here: this
# ORs two distinct facts into one list, so the result cannot say which of the two tripped for
# a given component (research/decisions-and-findings.md, F1).
accept_bad_basis_components() {
  local out
  out=$(jq -c --argjson ok "$ACCEPT_DECIDERS" \
    '[(.components // [])[]
      | select(has("accept") and ((.accept | type) == "object"))
      | select(((((.accept.decided_by // "") | tostring) as $d | ($ok | index($d)) == null))
               or ((((.accept.reason // "") | tostring) | gsub("^\\s+|\\s+$";"")) == ""))
      | (.component // "unnamed")]' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
  printf '%s' "$out"
}

# accept_unreadable_repair_components <payload>
# Components whose `checkpoint_repaired` is present but is neither a sha string nor null —
# a repair state was written down and cannot be read. Replaces UNREADABLE_REPAIR.
#
# RETARGETED WITH THE SIGNAL (v5.47.0+). This read the component row's `rounds` count and
# tripped on a non-numeric one. A component now gets at most one critic round, so that count
# is 1 on every row and the check could no longer fire for its own subject.
accept_unreadable_repair_components() {
  local out
  out=$(jq -c \
    '[(.components // [])[]
      | select(has("accept") | not)
      | select(has("checkpoint_repaired") and (.checkpoint_repaired != null)
               and ((.checkpoint_repaired | type) != "string"))
      | (.component // "unnamed")]' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
  printf '%s' "$out"
}

# accept_missing_verdict_components <payload>
# Components with no accept whose `checkpoint_repaired` is a non-null sha — disk evidence says
# the repair path ran but no verdict was recorded. Replaces NO_ACCEPT.
#
# THE SIGNAL IS THE CHECKPOINT, NOT THE ROUND COUNT (v5.47.0+). Until this version the
# question was "is rounds>1, or does a rounds[] entry name a numeric round>1". A component
# now gets at most one critic round, so `rounds` is 1 on every row and answers nobody. It was
# already the weaker reading before that: on the one record built after the accept verdict
# shipped, `rounds>1` named 2 of 14 components while 13 of 14 carried a repaired checkpoint,
# so eleven repairs owed a verdict under the contract and none under the check. That is the
# inherited N2 ceiling — a build that repairs, writes `rounds: 1` and no `rounds[]` entry
# passed clean — and moving the signal closes it rather than documenting it again.
#
# `<component>.repaired` is captured inside the `[a]ddress` block in commands/implement.md and
# nowhere else, so a non-null value IS the fact that the repair path ran for that component.
# Absent and null both mean it did not, which is why this reads the value rather than has().
accept_missing_verdict_components() {
  local out
  out=$(jq -c \
    '[(.components // [])[]
      | select(has("accept") | not)
      | select(.checkpoint_repaired != null)
      | (.component // "unnamed")]' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
  printf '%s' "$out"
}

# accept_unaccepted_components <payload>
# Components with an accept object whose .accept.action != "accepted". Replaces UNACCEPTED.
accept_unaccepted_components() {
  local out
  out=$(jq -c \
    '[(.components // [])[]
      | select(has("accept") and ((.accept | type) == "object"))
      | select(((.accept.action // "") | tostring) != "accepted")
      | (.component // "unnamed")]' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
  printf '%s' "$out"
}

# accept_escalation_reason <payload>
# Record-wide, not per-component: the trimmed top-level .escalation.reason, else the last
# non-blank .rounds[].resolution. Replaces ESC. KNOWN CEILING, inherited unchanged: one
# recorded decision clears every unaccepted component in the record.
# THE `.rounds[]` FALLBACK BELOW IS NOT DEAD CODE, THOUGH NO NEW BUILD FEEDS IT (v5.47.0+).
# A component gets at most one critic round, so a build written from here on records no
# `rounds[]` array and this branch never fires for one. It stays because `/review` reads records
# it did not write: a task built under v5.42.0 to v5.46.0 carries `rounds[].resolution` and is
# reviewed by this code. Retrofitting those records is a stated non-goal, so the reader is how
# they stay readable. Delete this branch only when no such record can still reach a review.
accept_escalation_reason() {
  local out
  out=$(jq -r 'def trim: gsub("^\\s+|\\s+$";"");
                 ((.escalation.reason // "") | tostring | trim) as $top
                 | if $top != "" then $top
                   else ([(.rounds // [])[] | (.resolution // empty) | tostring | trim]
                         | map(select(. != "")) | last // "")
                   end' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
  printf '%s' "$out"
}
