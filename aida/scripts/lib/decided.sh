#!/usr/bin/env bash
# decided.sh: the one reading of alignment.json's decidedWithoutAPerson (gap rows 232 and 244).
#
# An entry is a decision an unattended run took. It is open, or it is history:
#   open        a string, or an object with text and field. field names what the answer set:
#               automatedTests, goal, expectedResult, or a criterion or non-goal id.
#   approved    scope's `approve` added approvedAt and approvedBy.
#   superseded  a later scope action changed the entry's field. It added supersededAt and
#               supersededBy, the action's name. `approve` never marks it approved.
#   retired     a person retired it with scope's `retire`, which added retiredAt, retiredBy and
#               retiredReason.
# Superseded and retired win over approved: an approval of an answer that no longer holds is not
# an approval. A reader takes every history entry as a record of the past, never as a gap to
# repair (scripts/alignment-schema.json). Every script that counts, renders, checks or changes the
# list prepends DECIDED_JQ to its own jq program, so the rule has one copy.
#
#   decidedWhole       true for one entry that is a string, or an object whose state keys are whole
#   decidedState       open, approved, superseded or retired, for one whole entry
#   decidedIsOpen      true for one entry that is open
#   decidedOpen        the open entries of the contract, as a list
#   decidedApproved    passes one entry through when it is whole and approved, else nothing
#   decidedSupersede($old; $by; $at)
#                      run on the contract after a write: marks each open or approved entry whose
#                      field differs from $old, the contract before the write
#
# This file is a library. Source it; do not run it.
# shellcheck disable=SC2034 # read by the sourcing script
DECIDED_JQ='
  def decidedWhole: type == "string" or (type == "object"
    and (.text | type) == "string" and (.text | length) > 0
    and ([.field, .approvedAt, .approvedBy, .supersededAt, .supersededBy, .retiredAt, .retiredBy,
      .retiredReason] | map(. == null or type == "string") | all)
    and ([has("approvedAt"), has("approvedBy")] | unique | length) == 1
    and ([has("supersededAt"), has("supersededBy")] | unique | length) == 1
    and ([has("retiredAt"), has("retiredBy"), has("retiredReason")] | unique | length) == 1);
  def decidedState: if type == "string" then "open"
    elif has("retiredAt") then "retired" elif has("supersededAt") then "superseded"
    elif has("approvedAt") then "approved" else "open" end;
  def decidedIsOpen: type == "string" or (type == "object" and decidedWhole and decidedState == "open");
  def decidedOpen: [(.decidedWithoutAPerson // [])[] | select(decidedIsOpen)];
  def decidedApproved: objects | select(decidedWhole and decidedState == "approved");
  def decidedFieldValue($f): if ($f | test("^[cn][1-9][0-9]*$"))
    then [(.criteria // [])[], (.nonGoals // [])[] | objects | select(.id == $f) | del(.author, .verdict)]
    else .[$f] end;
  def decidedSupersede($old; $by; $at): . as $new
    | if (.decidedWithoutAPerson | type) != "array" then . else .decidedWithoutAPerson |= map(
        if type == "object" and decidedWhole and (.field | type) == "string"
          and (decidedState == "open" or decidedState == "approved")
          and (.field as $f | ($new | decidedFieldValue($f)) != ($old | decidedFieldValue($f)))
        then . + {supersededAt: $at, supersededBy: $by} else . end) end;'
