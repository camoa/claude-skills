#!/usr/bin/env bash
# Behavioral spec for scripts/task-inputs-read.sh, and for the wiring that makes it load-bearing.
#
# A task captured from a discussion arrives with the material that made the ask worth making. That
# material predates the contract AND the research, so it belongs to neither phase's output folder.
# Put it in `research/` — where Phase 1 WRITES — and a later `/research` either collides with it or
# reads it as work already done and skips the work it was supposed to do.
#
# `inputs/` was proposed on 2026-08-30 with exactly one instance and a README saying so. Nothing in
# the plugin named it: no command, no reference, no script. A convention no code knows about is a
# folder one person made once.
#
# The load-bearing properties:
#   - absent is not empty. No `inputs/` means nothing was captured; an `inputs/` holding nothing
#     means somebody made the folder and the material is gone. A reader that reports the second as
#     the first says a loss never happened.
#   - README.md is not material. The folder's own description must not make an empty folder read as
#     a full one, or every `inputs/` is `present` by construction and the state cannot fail.
#   - the phases do not write here. `inputs/` is input; a phase that writes into it has turned the
#     record of what we knew at capture into a record of what we concluded later.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
R="$ROOT/scripts/task-inputs-read.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }
[ -x "$R" ] || { echo "FAIL: $R missing or not executable"; echo "1 failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
f(){ printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

# --- the three states, each distinguishable from the other two ---------------------------------
mkdir -p "$TMP/t1"
OUT="$(bash "$R" "$TMP/t1")"; RC=$?
[ "$RC" -eq 0 ] && ok || no "a task folder with no inputs/ still exits 0"
[ "$(printf '%s' "$OUT" | jq -s 'length')" = "1" ] && ok || no "emits exactly one JSON document"
[ "$(f "$OUT" .status)" = "absent" ] && ok || no "no inputs/ folder reads status=absent"
[ "$(f "$OUT" .count)" = "0" ] && ok || no "absent carries no files"

mkdir -p "$TMP/t1/inputs"
OUT="$(bash "$R" "$TMP/t1")"
[ "$(f "$OUT" .status)" = "empty" ] && ok || no "an inputs/ folder holding nothing reads empty, NOT absent — the material was lost, and that is a different fact"

printf 'describes the folder\n' > "$TMP/t1/inputs/README.md"
OUT="$(bash "$R" "$TMP/t1")"
[ "$(f "$OUT" .status)" = "empty" ] && ok || no "a folder holding only its own README is still empty — counting it makes every inputs/ present by construction"
[ "$(f "$OUT" .count)" = "0" ] && ok || no "README.md is not counted as material"

printf 'the analysis\n' > "$TMP/t1/inputs/round-analysis.md"
OUT="$(bash "$R" "$TMP/t1")"
[ "$(f "$OUT" .status)" = "present" ] && ok || no "real material reads present"
[ "$(f "$OUT" .count)" = "1" ] && ok || no "present counts the material and not the README"
[ "$(f "$OUT" '.files[0]')" = "round-analysis.md" ] && ok || no "present names the file"

# --- deterministic order, so two runs on one folder agree ---------------------------------------
printf 'a\n' > "$TMP/t1/inputs/aaa.md"; printf 'z\n' > "$TMP/t1/inputs/zzz.md"
A="$(bash "$R" "$TMP/t1" | jq -c .files)"; B="$(bash "$R" "$TMP/t1" | jq -c .files)"
[ "$A" = "$B" ] && ok || no "two runs on the same folder return the same order"
[ "$A" = '["aaa.md","round-analysis.md","zzz.md"]' ] && ok || no "files are sorted, not filesystem order (got $A)"

# --- a subdirectory is not material, so a nested phase folder cannot inflate the count ----------
mkdir -p "$TMP/t1/inputs/sub"; printf 'x\n' > "$TMP/t1/inputs/sub/deep.md"
[ "$(f "$(bash "$R" "$TMP/t1")" .count)" = "3" ] && ok || no "a file inside a subdirectory of inputs/ is not counted as top-level material"

# --- unreadable inputs are their own answer, never a clean one ----------------------------------
OUT="$(bash "$R" "$TMP/never-made")"; RC=$?
[ "$RC" -eq 0 ] && ok || no "a missing task folder still exits 0"
[ "$(f "$OUT" .status)" = "unreadable" ] && ok || no "a missing task folder is unreadable, NOT absent — absent is a claim about a folder that was read"
[ "$(f "$OUT" '.warnings[0]')" = "task_folder_missing" ] && ok || no "the missing folder says which way it was unreadable"

OUT="$(bash "$R")"; RC=$?
[ "$RC" -eq 0 ] && ok || no "no argument still exits 0"
[ "$(f "$OUT" .status)" = "unreadable" ] && ok || no "no argument reads unreadable"
[ "$(f "$OUT" '.warnings[0]')" = "missing_arg" ] && ok || no "no argument says so in warnings"

# --- WIRING. A reader nothing calls is a folder one person made once. ---------------------------
RESEARCH="$ROOT/commands/research.md"
if [ -f "$RESEARCH" ]; then
  grep -Fq 'task-inputs-read.sh' "$RESEARCH" && ok || no "commands/research.md never runs task-inputs-read.sh — the convention is documented and unread, which is the state this task exists to end"
else
  no "commands/research.md not found"
fi

WALK="$ROOT/references/research-walkthrough.md"
if [ -f "$WALK" ]; then
  grep -Fq 'inputs/' "$WALK" && ok || no "references/research-walkthrough.md does not describe inputs/"
  grep -Fqi 'never writes' "$WALK" && ok || no "the walkthrough does not say research never writes into inputs/ — the one rule that keeps input from becoming output"
else
  no "references/research-walkthrough.md not found"
fi

# --- NO PHASE WRITES INTO inputs/. Checked against the command bodies, not asserted in prose. ----
# A phase that writes here has turned the record of what we knew at capture into a record of what
# we concluded later, and the next reader cannot tell which they are holding.
BAD=""
for cmd in research design implement review complete; do
  C="$ROOT/commands/$cmd.md"
  [ -f "$C" ] || continue
  # A write instruction naming inputs/ as its destination. The read call is not one.
  if grep -nE '(Write|write|append|>>?)[^`]{0,60}inputs/' "$C" | grep -v 'task-inputs-read' | grep -qv 'never writ'; then
    BAD="$BAD $cmd"
  fi
done
[ -z "$BAD" ] && ok || no "these phase commands appear to write into inputs/:$BAD"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
