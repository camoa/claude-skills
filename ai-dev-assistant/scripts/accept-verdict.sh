#!/usr/bin/env bash
# accept-verdict.sh — the 8 pure decisions behind the repair accept verdict block in
# build-critique-assert.sh (the section commented "the repair accept verdict (v5.42.0+)").
#
# SOURCE this file (do not execute it). Each function takes the record's PAYLOAD as $1 and
# nothing else, and answers ONE of the 8 questions build-critique-assert.sh's accept block
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
# Components with no accept key that HAVE a non-null rounds field whose type is not number.
# Replaces UNREADABLE_REPAIR.
accept_unreadable_repair_components() {
  local out
  out=$(jq -c \
    '[(.components // [])[]
      | select((has("accept") | not) and has("rounds") and (.rounds != null)
               and ((.rounds | type) != "number"))
      | (.component // "unnamed")]' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
  printf '%s' "$out"
}

# accept_unreadable_round_components <payload>
# Components with no accept, component-row rounds<=1 (default 1), no matching rounds[] entry
# with a numeric round>1, but WITH a matching rounds[] entry whose round is present and
# non-numeric — ambiguous whether that entry is round 1 or a repair. Replaces UNREADABLE_ROUND.
accept_unreadable_round_components() {
  local out
  out=$(jq -c \
    '(.rounds // []) as $r
     | [(.components // [])[]
        | . as $c
        | select(has("accept") | not)
        | (($c.component // "unnamed") | tostring) as $name
        | select(((($c.rounds // 1) | if type == "number" then . else 1 end)) <= 1)
        | select(any($r[]?; ((.component // .wo // "") | tostring) == $name
                            and ((.round | type) == "number") and (.round > 1)) | not)
        | select(any($r[]?; ((.component // .wo // "") | tostring) == $name
                            and ((.round | type) != "number")))
        | $name]' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
  printf '%s' "$out"
}

# accept_missing_verdict_components <payload>
# Components with no accept, where component-row rounds>1 OR a rounds[] entry names them with
# numeric round>1 — disk evidence says repaired but no verdict recorded. Replaces NO_ACCEPT.
accept_missing_verdict_components() {
  local out
  out=$(jq -c \
    '(.rounds // []) as $r
     | [(.components // [])[]
        | . as $c
        | select(has("accept") | not)
        | (($c.component // "unnamed") | tostring) as $name
        | select((((($c.rounds // 1) | if type == "number" then . else 1 end)) > 1)
                 or any($r[]?; ((.component // .wo // "") | tostring) == $name
                               and ((.round | type) == "number") and (.round > 1)))
        | $name]' <<<"$1" 2>/dev/null) || { printf '%s' "$JQ_ERR"; return 0; }
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
