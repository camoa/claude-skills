#!/usr/bin/env bash
# recipe-method-fit-spec.sh — a recipe that did not suit the task had nowhere to say so.
#
# Recipe routing keys on phase and framework and on nothing else. What kind of work the task
# does never enters, so a task that edits three configuration values and runs a build was
# handed a contrib-module prior-art method during research and a service-and-plugin
# architecture method during design.
#
# Both phases noticed. Both wrote a paragraph into a `notes` key that the gate's schema has
# never defined and that no consumer reads, and both observations were gone by the next
# phase, because the audit file is overwrite-on-fire. The review that eventually judges the
# work had no way to learn the method was wrong for it.
#
# So: a verdict field the writer checks for, and a durable copy on the project_state recipe
# line. Absent is warned, never taken for a good fit — nobody assessed it and it suited the
# task are different facts.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRITER="$PLUGIN_ROOT/scripts/gate-audit-write.sh"
READER="$PLUGIN_ROOT/scripts/project-state-read.sh"
SCHEMA="$PLUGIN_ROOT/references/gate-audit-schema.md"
PROTOCOL="$PLUGIN_ROOT/references/recipe-resolution.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/tf" "$TMP/ps"

warns_on() { # warns_on <payload> <grep pattern>
  "$WRITER" "$TMP/tf" recipe-load "$1" 2>&1 >/dev/null | grep -q "$2"
}

# ------------------------------------------------------- the writer notices a missing verdict

if warns_on '{"phase":"design","resolved_count":1,"frameworks":[{"framework":"drupal","available":true}],"bypass":null}' 'no method_fit'; then
  pass_check "a resolved recipe with no fit verdict is warned about"
else
  fail_check "a resolved recipe with no fit verdict was written silently"
fi

if warns_on '{"phase":"design","resolved_count":1,"frameworks":[{"framework":"drupal","available":true,"method_fit":{"verdict":"ok","reason":"x"}}],"bypass":null}' 'is not fits|partial'; then
  pass_check "a verdict outside the enum is warned about"
else
  fail_check "a verdict outside the enum passed as valid"
fi

if warns_on '{"phase":"design","resolved_count":1,"frameworks":[{"framework":"drupal","available":true,"method_fit":{"verdict":"mismatch","reason":""}}],"bypass":null}' 'with no reason'; then
  pass_check "a mismatch with no reason is warned about"
else
  fail_check "a mismatch was recorded with nothing the next phase can act on"
fi

GOOD='{"phase":"design","resolved_count":1,"frameworks":[{"framework":"drupal","available":true,"method_fit":{"verdict":"mismatch","reason":"method builds services; this task edits three config values"}}],"bypass":null}'
if "$WRITER" "$TMP/tf" recipe-load "$GOOD" 2>&1 >/dev/null | grep -q 'method_fit'; then
  fail_check "a complete fit record was warned about anyway"
else
  pass_check "a complete fit record writes clean"
fi

# A framework that resolved nothing is not asked to judge a method it never read.
if "$WRITER" "$TMP/tf" recipe-load '{"phase":"design","resolved_count":0,"frameworks":[{"framework":"drupal","available":false}],"bypass":{"reason":"recipe_not_published"}}' 2>&1 >/dev/null | grep -q 'method_fit'; then
  fail_check "an unresolved framework was asked for a fit verdict"
else
  pass_check "an unresolved framework is not asked to judge a method it never read"
fi

# The check must not answer when it cannot run. A jq failure that reads as "no problems"
# is the whole defect class this file belongs to.
if grep -q 'could not check recipe-load method_fit' "$WRITER"; then
  pass_check "a failed fit check reports itself instead of reading as clean"
else
  fail_check "a failed fit check would be indistinguishable from finding no problems"
fi

# `resolved_count` is documented and was absent from the record the live run wrote.
if warns_on '{"phase":"design","frameworks":[{"framework":"drupal","available":true,"method_fit":{"verdict":"fits","reason":""}}],"bypass":null}' 'resolved_count'; then
  pass_check "a record missing resolved_count is warned about"
else
  fail_check "resolved_count is documented but not checked for"
fi

# ------------------------------------------------------------ the verdict survives the phase

write_state() { printf '%s\n' "# Project: fit-test" "**Frameworks:** drupal" "**Process Recipes:**" "$@" > "$TMP/ps/project_state.md"; }
fit_of() { "$READER" "$TMP/ps" 2>/dev/null | jq -r --arg k "$1" '.processRecipes[] | select(.key == $k) | .fit'; }
warn_codes() { "$READER" "$TMP/ps" 2>/dev/null | jq -r '.warnings[].code' | sort -u | tr '\n' ' '; }

write_state "- design/drupal/architecture → source=dev-guides fit=mismatch" \
            "- review/drupal/checks → source=dev-guides"
if [ "$(fit_of design/drupal/architecture)" = "mismatch" ]; then
  pass_check "a fit verdict on the recipe line survives to the next phase"
else
  fail_check "a fit verdict on the recipe line is not read back (got '$(fit_of design/drupal/architecture)')"
fi

if [ "$(fit_of review/drupal/checks)" = "null" ]; then
  pass_check "a recipe line with no verdict reads as null, not as a good fit"
else
  fail_check "an unassessed recipe read as '$(fit_of review/drupal/checks)' instead of null"
fi

# Every recipe line predating this field must still parse. There are projects full of them.
case " $(warn_codes) " in
  *process_recipe_bad_*) fail_check "a recipe line with no fit token now warns: $(warn_codes)" ;;
  *) pass_check "recipe lines written before this field still parse clean" ;;
esac

write_state "- design/drupal/architecture → source=dev-guides fit=probably"
case " $(warn_codes) " in
  *process_recipe_bad_fit*) pass_check "a verdict outside the enum on the recipe line is warned about" ;;
  *) fail_check "an invented verdict on the recipe line passed silently" ;;
esac

# --------------------------------------------------------- the field is documented, not folklore

grep -q 'method_fit' "$SCHEMA" \
  && pass_check "the fit field is in the gate schema" \
  || fail_check "the fit field is not documented, so the next caller will invent a key again"

grep -q 'Assess whether the method fits the task' "$PROTOCOL" \
  && pass_check "the resolution protocol tells a phase to assess fit" \
  || fail_check "nothing instructs a phase to assess fit, so nothing will"

grep -q 'fit=<verdict>' "$PROTOCOL" \
  && pass_check "the protocol says where the verdict goes to survive the phase" \
  || fail_check "the protocol records the verdict only where the next phase cannot read it"

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'recipe-method-fit-spec: all checks passed\n'; exit 0; }
printf 'recipe-method-fit-spec: FAILURES\n' >&2; exit 1
