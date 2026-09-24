#!/usr/bin/env bash
# proof.sh: what one work order's proof kind means for a check about to answer.
#
# A work order carries one proof kind: `tests`, `gate`, `record` or `observe`. No check wants the
# kind itself. Every site that reads `.proof` turns it into one of three questions about the
# order (gap row 170). The first asks which of the eight deciding checks takes its first slot.
# The second asks which repository holds its range. The third asks whether it owns a file in the
# code path. Each site turned the kind into its question on its own, in its own words. So a fifth
# kind meant finding twenty-three of them.
#
# The classification is written twice here, once in shell and once in jq. A shell function cannot
# be called from inside a jq program. Nine sites in check-design.sh and three in review-actions.sh
# live inside single jq programs that build cross-order lists. Both copies sit in this one file,
# so a fifth kind is one edit. schema-check.sh:86 already holds a jq program as
# a string constant in a library, so the shape is not new.
#
# Why this file and not scripts/lib/recipes.sh, where br_proof_facts was written: check-design.sh
# sources scripts/lib/schema-check.sh alone. recipes.sh is 1,679 lines, requires its caller to
# define `die`, and requires records-hash.sh sourced first. check-design.sh defines die3 and die2,
# not die. Why not schema-check.sh: its own header says a cross-field rule that is not shape stays
# with the script that owns it. A proof-kind classification is that rule.
#
# This library takes nothing from its caller and refuses nothing. An unknown kind reads as the
# default, `tests`; scripts/design-schema.json is what refuses a value outside the enum.
#
# Public:
#
#   br_order_facts <work order document>   sets BR_ORDER_SLOT, BR_ORDER_RANGE, BR_ORDER_OWNS_CODE
#   BR_ORDER_FACTS_JQ                      the same classification as a jq definition, `orderFacts`
#   br_order_needs <work order document>   sets BR_ORDER_ROLES, BR_ORDER_LOOKUPS
#   br_proof_facts <snapshot>              commits in the code repository, owns a file there
#
# Portability: bash 3.2+ and zsh. Every `case` pattern below is a literal word, never a variable.

# $1 one work order document as JSON text. It sets three variables, in the multi-value return
# pattern recipes.sh's br_subtract_baseline and implement-actions.sh's rv_load_range_repo already
# use. They are named globals that share one prefix. They are declared here, so a caller under
# `set -u` never reads one unset, and reset at the top of the function.
#
# BR_ORDER_SLOT is the check that takes the first of the eight deciding checks: `order-tests`,
# `configuration-gate`, `done-when` or `observed`. An order freezes and runs a test exactly when
# its slot is `order-tests`, so that question needs no field of its own.
# BR_ORDER_RANGE is `code` or `project`, the repository the order's range lives in.
# BR_ORDER_OWNS_CODE is `yes` or `no`, whether the order owns a file in the code path.
BR_ORDER_SLOT=""; BR_ORDER_RANGE=""; BR_ORDER_OWNS_CODE=""
# shellcheck disable=SC2034 # read by the sourcing script
br_order_facts() {
  local proof
  BR_ORDER_SLOT=""; BR_ORDER_RANGE=""; BR_ORDER_OWNS_CODE=""
  proof="$(printf '%s' "$1" | jq -r '.proof // "tests"')"
  case "$proof" in
    gate)    BR_ORDER_SLOT="configuration-gate"; BR_ORDER_RANGE="code";    BR_ORDER_OWNS_CODE="yes" ;;
    record)  BR_ORDER_SLOT="done-when";          BR_ORDER_RANGE="project"; BR_ORDER_OWNS_CODE="no"  ;;
    observe) BR_ORDER_SLOT="observed";           BR_ORDER_RANGE="code";    BR_ORDER_OWNS_CODE="yes" ;;
    *)       BR_ORDER_SLOT="order-tests";        BR_ORDER_RANGE="code";    BR_ORDER_OWNS_CODE="yes" ;;
  esac
}

# The same classification as a jq definition, for the sites that cannot call a function. A caller
# prefixes this string to its own program and reads `orderFacts` with a work order as the input.
BR_ORDER_FACTS_JQ='
  def orderFacts:
    (.proof // "tests") as $p
    | if   $p == "gate"    then {slot: "configuration-gate", range: "code",    ownsCode: true}
      elif $p == "record"  then {slot: "done-when",          range: "project", ownsCode: false}
      elif $p == "observe" then {slot: "observed",           range: "code",    ownsCode: true}
      else                      {slot: "order-tests",        range: "code",    ownsCode: true}
      end;'

# The roles one order's proof kind dispatches, and the catalog points its tests step asks. $1 one
# work order document. Sets two space-separated lists. It reads the slot br_order_facts sets, so a
# fifth kind is still one edit above. `read` prints both on the order's line, the tests step reads
# them there, and dispatch-open refuses a role in BR_KIND_ROLES that the order's list lacks.
#
# A fixer is not listed: an open finding decides it, not a kind. `point: implement` is on every
# kind, because the tests step takes the oracle globs from it and a gate order runs its
# `## Configuration gate`. The test author and the row-checker read `point: test-authoring`.
# The row-checker takes the recipe path on every dispatch (agents/row-checker.md), a record
# order's done-when row included, so a `record` order asks for it too.
#
# Three rules keep roles on these lists. Do not cut them to save a dispatch.
# - The per-order reviewer is on every kind. A passing check says the order met its own check;
#   only the reviewer reads the diff against the contract.
# - The row-checker stays on a `record` order. Its done-when row is that order's only check, so
#   without the checker nothing judges the deliverable before the build.
# - No top-tier critic leaves because an order is small. A small diff can still break a criterion,
#   and a missed defect costs the same whatever the size.
BR_KIND_ROLES="test-author row-checker implementer reviewer"
BR_ORDER_ROLES=""; BR_ORDER_LOOKUPS=""
# shellcheck disable=SC2034 # read by the sourcing script
br_order_needs() {
  br_order_facts "$1"
  case "$BR_ORDER_SLOT" in
    order-tests) BR_ORDER_ROLES="test-author row-checker implementer reviewer"; BR_ORDER_LOOKUPS="test-authoring implement" ;;
    done-when)   BR_ORDER_ROLES="row-checker implementer reviewer";             BR_ORDER_LOOKUPS="test-authoring implement" ;;
    *)           BR_ORDER_ROLES="implementer reviewer";                         BR_ORDER_LOOKUPS="implement" ;;
  esac
}

# What the frozen snapshot's proof kinds mean for a check that is about to answer. $1 the snapshot
# document. Prints two words separated by a tab: whether any order commits in the code repository,
# and whether any order owns a file there, each `yes` or `no`.
#
# The two questions have one answer today, because an order proved by its record is the one kind
# that lands its deliverable in the project folder. They are asked apart because a check reads one
# or the other. A fifth proof kind separates them in the classification above, not at the call
# sites. Its four consumers in review-actions.sh ask a whole-task question about a whole-task
# range. Over a range that changed no file, it asks whether this task ever had code to look at.
br_proof_facts() {
  printf '%s' "$1" | jq -r "$BR_ORDER_FACTS_JQ"'
    def yesno(f): if any((.workOrders // [])[]; orderFacts | f) then "yes" else "no" end;
    yesno(.range == "code") + "\t" + yesno(.ownsCode)'
}
