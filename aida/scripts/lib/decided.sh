#!/usr/bin/env bash
# decided.sh: the one reading of alignment.json's decidedWithoutAPerson (gap row 232).
#
# A string entry is a decision an unattended run took that no person has approved yet. Scope's
# `approve` turns it into an object with text, approvedAt and approvedBy, and that object is
# history (scripts/alignment-schema.json). Every script that counts, renders or checks the list
# prepends DECIDED_JQ to its own jq program, so the rule has one copy.
#
#   decidedOpen      the open entries of the contract, as a list
#   decidedApproved  passes one entry through when it is a whole approved object, else nothing
#
# This file is a library. Source it; do not run it.
# shellcheck disable=SC2034 # read by the sourcing script
DECIDED_JQ='
  def decidedOpen: [(.decidedWithoutAPerson // [])[] | select(type == "string")];
  def decidedApproved: objects
    | select((.text | type) == "string" and (.approvedAt | type) == "string"
      and (.approvedBy | type) == "string");'
