#!/usr/bin/env bash
# migrate-to-epic-delete-safety-spec.sh — behavioural spec for the six `rm -rf`
# sites in scripts/migrate-to-epic.sh.
#
# Each of those six deletes a path built as "<base>/<leaf>". If either half is
# empty the path collapses onto something far larger than the intended target:
# an empty leaf turns `rm -rf "$TEMP_ROOT/$TASK_NAME"` into `rm -rf` of the whole
# .migration-tmp/ (which holds the 24h rollback copy of the user's task, and any
# other migration's temp), and turns `rm -rf "$CHILD_IN_PROGRESS_ROOT/$child"`
# into `rm -rf` of the project's entire in_progress/ folder. The script moves and
# deletes real task folders, so that is data loss, not a wrong message.
#
# Every site now guards both halves with ${var:?...}, which makes bash refuse the
# expansion and exit rather than run the rm. This spec proves the refusal is real:
# for each site it blanks the variable on the way into that site in a throwaway
# copy of the script, runs the copy against a throwaway fixture, and asserts BOTH
# that the run exited non-zero AND that the folder the unguarded form would have
# erased is still there. Those are two different claims and only the second one
# matters.
#
# The blanking is done with count-asserted literal injections: each anchor must
# occur exactly once in the script or the case fails outright, so an anchor that
# drifts out of the script is reported instead of silently testing nothing. No
# anchor quotes the guard text itself, so removing a guard does not disarm the
# injection that is supposed to catch it. Deleting any one of the six guards was
# confirmed to fail this spec on a survival assertion, not just a missing anchor.
#
# Case 0 is the control: an uninjected run must still succeed and must still
# delete the peer folders it is supposed to delete, so the guards cannot pass by
# turning the script into a no-op.

set -uo pipefail
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPTS_SRC="$SPEC_DIR/../scripts"

OK=0; FAIL=0
ok(){ printf 'OK   %s\n' "$1"; OK=$((OK + 1)); }
bad(){ printf 'FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); }
chk(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

WORK="$(mktemp -d)"
# Guarded the same way as the script under test: an empty WORK here would take
# out the whole of /.
trap 'rm -rf "${WORK:?spec cleanup refused, WORK is empty}"' EXIT
FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME"

# --- literal-text tooling ----------------------------------------------------
# Occurrences (not matching lines) of a literal needle in a file.
count_occ() { # <needle> <file>
  awk -v ndl="$1" '
    BEGIN { c = 0 }
    { s = $0; while ((i = index(s, ndl)) > 0) { c++; s = substr(s, i + length(ndl)) } }
    END { print c + 0 }' "$2"
}

# Replace the single occurrence of a literal needle. Fails the case when the
# needle does not occur exactly once, so a drifted anchor is loud.
replace_once() { # <file> <needle> <repl> <label>
  local f="$1" ndl="$2" rpl="$3" label="$4" n
  n=$(count_occ "$ndl" "$f")
  if [ "$n" -ne 1 ]; then
    bad "$label: anchor occurs $n time(s) in the script, want exactly 1"
    return 1
  fi
  ok "$label: anchor occurs exactly 1 time"
  awk -v ndl="$ndl" -v rpl="$rpl" '
    !done { i = index($0, ndl); if (i > 0) { $0 = substr($0, 1, i - 1) rpl substr($0, i + length(ndl)); done = 1 } }
    { print }' "$f" > "$f.mut" && mv "$f.mut" "$f"
}

# Insert a line immediately before the single line holding a literal anchor.
insert_before() { # <file> <anchor> <line> <label>
  local f="$1" anchor="$2" line="$3" label="$4" n
  n=$(count_occ "$anchor" "$f")
  if [ "$n" -ne 1 ]; then
    bad "$label: anchor occurs $n time(s) in the script, want exactly 1"
    return 1
  fi
  ok "$label: anchor occurs exactly 1 time"
  awk -v a="$anchor" -v ins="$line" '
    !done && index($0, a) { print ins; done = 1 }
    { print }' "$f" > "$f.mut" && mv "$f.mut" "$f"
}

# --- fixtures ----------------------------------------------------------------
mk_flat_task() { # <dir> <name> [status]
  mkdir -p "$1"
  cat > "$1/task.md" <<EOF
---
id: local:$2
kind: flat
parent: null
children: null
blocks: []
blocked_by: []
external_ids: {}
status: ${3:-draft}
---

# Task: $2
EOF
  printf 'marker for %s\n' "$2" > "$1/marker.txt"
}

# A project with a flat task to promote, one in-progress peer (move_existing),
# one completed peer (already_completed), a bystander in each of those two
# folders, and an unrelated rollback dir already sitting in .migration-tmp/.
# The bystanders and the unrelated rollback dir are the survival witnesses: the
# script never touches them, so if one disappears the rm collapsed onto its root.
mk_project() { # <dir>
  local p="$1" ip cp_
  ip="$p/implementation_process/in_progress"
  cp_="$p/implementation_process/completed"
  mk_flat_task "$ip/demo" demo in_progress
  mk_flat_task "$ip/peer" peer in_progress
  mk_flat_task "$ip/bystander" bystander in_progress
  mk_flat_task "$cp_/donechild" donechild completed
  mk_flat_task "$cp_/bystander_done" bystander_done completed
  mkdir -p "$ip/.migration-tmp/.old-unrelated"
  printf 'another migration rollback copy\n' > "$ip/.migration-tmp/.old-unrelated/keepme.txt"
}

# A project whose task is ALREADY an epic, so the run takes the expansion path
# (the only path that reaches the copy-failure cleanup).
mk_epic_project() { # <dir>
  local p="$1" ip
  ip="$p/implementation_process/in_progress"
  mkdir -p "$ip/theepic/in_progress/existing_a" "$ip/theepic/shared" "$ip/theepic/completed"
  cat > "$ip/theepic/task.md" <<'EOF'
---
id: local:theepic
kind: epic
parent: null
children:
- local:existing_a
blocks: []
blocked_by: []
external_ids: {}
status: in_progress
---

# Epic: theepic
EOF
  cat > "$ip/theepic/in_progress/existing_a/task.md" <<'EOF'
---
id: local:existing_a
kind: subtask
parent: local:theepic
children: null
blocks: []
blocked_by: []
external_ids: {}
status: in_progress
---

# Task: existing_a
EOF
  printf 'epic-wide notes\n' > "$ip/theepic/shared/notes.md"
  mkdir -p "$ip/.migration-tmp/.old-unrelated"
  printf 'another migration rollback copy\n' > "$ip/.migration-tmp/.old-unrelated/keepme.txt"
}

# Fresh throwaway copy of the scripts the migration sources, so injections never
# touch the repository copy.
mk_scripts() { # <dir>
  mkdir -p "$1"
  cp "$SCRIPTS_SRC/migrate-to-epic.sh" "$SCRIPTS_SRC/fm-helpers.sh" \
     "$SCRIPTS_SRC/session-paths.sh" "$1/"
}

RC=0
run_migrate() { # <scripts_dir> <out_file> <project> <task> [children...]
  local sd="$1" out="$2"; shift 2
  # Separate process, not a subshell: `set -e` semantics do not leak either way,
  # and $? here is the script's own status with no pipeline in between.
  HOME="$FAKE_HOME" bash "$sd/migrate-to-epic.sh" "$@" > "$out" 2>&1
  RC=$?
}

# Exit-status assertions get their own helpers rather than going through chk's
# eval, so RC is a plain reference the linter can see.
chk_rc_zero()    { if [ "$RC" -eq 0 ]; then ok "$1"; else bad "$1 (rc=$RC)"; fi; }
chk_rc_nonzero() { if [ "$RC" -ne 0 ]; then ok "$1"; else bad "$1 (rc=$RC)"; fi; }

# The exact guarded lines, used both as injection anchors and as the static
# check that every site still carries both halves of the guard.
RM_COPY='rm -rf "${TEMP_ROOT:?empty, refusing rm -rf}/${TASK_NAME:?empty, refusing rm -rf of the whole temp root after a failed epic copy}"'
RM_KIND='rm -rf "${TEMP_ROOT:?empty, refusing rm -rf}/${TASK_NAME:?empty, refusing rm -rf of the whole temp root after an unknown child kind}"'
RM_VALID='rm -rf "${TEMP_ROOT:?empty, refusing rm -rf}/${TASK_NAME:?empty, refusing rm -rf of the whole temp root after failed validation}"'
RM_SWAP='rm -rf "${TEMP_ROOT:?empty, refusing rm -rf}/${TASK_NAME:?empty, refusing rm -rf of the whole temp root after a failed swap}"'
RM_INPROG='rm -rf "${CHILD_IN_PROGRESS_ROOT:?empty, refusing rm -rf}/${child:?empty, refusing rm -rf of the whole in_progress root}"'
RM_DONE='rm -rf "${CHILD_COMPLETED_ROOT:?empty, refusing rm -rf}/${child:?empty, refusing rm -rf of the whole completed root}"'

# --- static: all six sites present, exactly once each ------------------------
echo "--- guards present in the shipped script"
SRC="$SCRIPTS_SRC/migrate-to-epic.sh"
for pair in "epic copy:$RM_COPY" "unknown child kind:$RM_KIND" "failed validation:$RM_VALID" \
            "failed swap:$RM_SWAP" "in_progress child:$RM_INPROG" "completed child:$RM_DONE"; do
  label="${pair%%:*}"; needle="${pair#*:}"
  n=$(count_occ "$needle" "$SRC")
  chk "guarded rm site present exactly once: $label" '[ "$n" -eq 1 ]'
done
# The invariant behind the six, so a seventh rm -rf added later is caught too:
# every `rm -rf "` line must carry at least two `:?` guards, one per half of the
# path it builds. Reports the offending line rather than just a count.
UNGUARDED=$(awk '
  /rm -rf "/ { c = 0; s = $0; while ((i = index(s, ":?")) > 0) { c++; s = substr(s, i + 2) }
               if (c < 2) print FNR ": " $0 }' "$SRC")
if [ -z "$UNGUARDED" ]; then
  ok "every rm -rf line guards both halves of its path"
else
  bad "every rm -rf line guards both halves of its path"
  printf '     %s\n' "$UNGUARDED"
fi

# --- case 0: control, the valid path is unchanged ----------------------------
echo "--- case 0: control (no injection)"
C0="$WORK/case0"; mk_project "$C0"; mk_scripts "$C0/scripts"
run_migrate "$C0/scripts" "$C0/out.txt" "$C0" demo peer donechild
chk_rc_zero "control run exits 0"
chk "control: epic built at in_progress/demo" '[ -f "$C0/implementation_process/in_progress/demo/task.md" ]'
chk "control: peer moved inside the epic"     '[ -f "$C0/implementation_process/in_progress/demo/in_progress/peer/task.md" ]'
chk "control: donechild moved inside the epic" '[ -f "$C0/implementation_process/in_progress/demo/completed/donechild/task.md" ]'
chk "control: original peer folder IS deleted"      '[ ! -d "$C0/implementation_process/in_progress/peer" ]'
chk "control: original donechild folder IS deleted" '[ ! -d "$C0/implementation_process/completed/donechild" ]'
chk "control: bystanders untouched" '[ -f "$C0/implementation_process/in_progress/bystander/task.md" ] && [ -f "$C0/implementation_process/completed/bystander_done/task.md" ]'

# --- case A: empty child at the in_progress delete ---------------------------
echo "--- case A: empty child name at the in_progress peer delete"
CA="$WORK/caseA"; mk_project "$CA"; mk_scripts "$CA/scripts"
insert_before "$CA/scripts/migrate-to-epic.sh" \
  '# project'"'"'s whole in_progress/ root and erases every task under it.' \
  '        child=""' "case A injection"
run_migrate "$CA/scripts" "$CA/out.txt" "$CA" demo peer donechild
chk_rc_nonzero "A: run refused, exit non-zero"
chk "A: refusal names the in_progress root" 'grep -q "refusing rm -rf of the whole in_progress root" "$CA/out.txt"'
chk "A: in_progress/ root still exists"     '[ -d "$CA/implementation_process/in_progress" ]'
chk "A: bystander task survives (WOULD HAVE BEEN ERASED)" '[ -f "$CA/implementation_process/in_progress/bystander/task.md" ]'
chk "A: peer task survives"                 '[ -f "$CA/implementation_process/in_progress/peer/task.md" ]'
chk "A: the migrated epic survives"         '[ -f "$CA/implementation_process/in_progress/demo/task.md" ]'

# --- case B: empty child at the completed delete -----------------------------
echo "--- case B: empty child name at the completed peer delete"
CB="$WORK/caseB"; mk_project "$CB"; mk_scripts "$CB/scripts"
insert_before "$CB/scripts/migrate-to-epic.sh" \
  '# Same hazard against the completed/ root.' \
  '        child=""' "case B injection"
run_migrate "$CB/scripts" "$CB/out.txt" "$CB" demo peer donechild
chk_rc_nonzero "B: run refused, exit non-zero"
chk "B: refusal names the completed root" 'grep -q "refusing rm -rf of the whole completed root" "$CB/out.txt"'
chk "B: completed/ root still exists"     '[ -d "$CB/implementation_process/completed" ]'
chk "B: bystander_done survives (WOULD HAVE BEEN ERASED)" '[ -f "$CB/implementation_process/completed/bystander_done/task.md" ]'
chk "B: donechild source survives"        '[ -f "$CB/implementation_process/completed/donechild/task.md" ]'

# --- case C: empty task name at the failed-validation cleanup ----------------
echo "--- case C: empty task name at the failed-validation temp cleanup"
CC="$WORK/caseC"; mk_project "$CC"; mk_scripts "$CC/scripts"
replace_once "$CC/scripts/migrate-to-epic.sh" \
  'if [ "$VALIDATION_FAILED" = "true" ]; then' \
  'VALIDATION_FAILED=true; if [ "$VALIDATION_FAILED" = "true" ]; then TASK_NAME="";' \
  "case C injection"
run_migrate "$CC/scripts" "$CC/out.txt" "$CC" demo peer donechild
chk_rc_nonzero "C: run refused, exit non-zero"
chk "C: refusal names the failed-validation cleanup" 'grep -q "temp root after failed validation" "$CC/out.txt"'
chk "C: unrelated rollback dir survives (WOULD HAVE BEEN ERASED)" '[ -f "$CC/implementation_process/in_progress/.migration-tmp/.old-unrelated/keepme.txt" ]'
chk "C: the built temp dir is still there"  '[ -d "$CC/implementation_process/in_progress/.migration-tmp/demo" ]'
chk "C: original task untouched"            '[ -f "$CC/implementation_process/in_progress/demo/marker.txt" ]'
chk "C: peer untouched"                     '[ -f "$CC/implementation_process/in_progress/peer/task.md" ]'

# --- case D: empty task name at the failed-swap cleanup ----------------------
echo "--- case D: empty task name at the failed-swap temp cleanup"
CD="$WORK/caseD"; mk_project "$CD"; mk_scripts "$CD/scripts"
# Forcing the swap to fail AND blanking the name in one injection, so the anchor
# does not mention the guard. The blanking also defeats the restore mv on the
# line above, which leaves .old-demo as the ONLY copy of the user's task: the
# unguarded form erases the whole temp root, and that copy with it.
replace_once "$CD/scripts/migrate-to-epic.sh" \
  'mv "$TEMP_ROOT/$TASK_NAME" "$TASK_DIR" || {' \
  'false || { TASK_NAME="";' \
  "case D injection"
run_migrate "$CD/scripts" "$CD/out.txt" "$CD" demo peer donechild
chk_rc_nonzero "D: run refused, exit non-zero"
chk "D: refusal names the failed-swap cleanup" 'grep -q "temp root after a failed swap" "$CD/out.txt"'
chk "D: unrelated rollback dir survives (WOULD HAVE BEEN ERASED)" '[ -f "$CD/implementation_process/in_progress/.migration-tmp/.old-unrelated/keepme.txt" ]'
chk "D: the only copy of the task survives in .old-demo (WOULD HAVE BEEN ERASED)" '[ -f "$CD/implementation_process/in_progress/.migration-tmp/.old-demo/marker.txt" ]'
chk "D: peer untouched"                        '[ -f "$CD/implementation_process/in_progress/peer/task.md" ]'

# --- case E: empty task name at the unknown-child-kind cleanup ---------------
echo "--- case E: empty task name at the unknown-child-kind temp cleanup"
CE="$WORK/caseE"; mk_project "$CE"; mk_scripts "$CE/scripts"
replace_once "$CE/scripts/migrate-to-epic.sh" \
  'local k="${CHILD_KINDS[$i]:-}"' \
  'local k="bogus"' \
  "case E branch injection"
# Blanked at the top of the add-children block rather than at the rm line, so the
# anchor is independent of the guard. Nothing between there and the catch-all
# branch reads TASK_NAME.
insert_before "$CE/scripts/migrate-to-epic.sh" \
  '# Add the NEW children (both promotion and expansion). Existing epic children' \
  'TASK_NAME=""' "case E blanking injection"
run_migrate "$CE/scripts" "$CE/out.txt" "$CE" demo peer donechild
chk_rc_nonzero "E: run refused, exit non-zero"
chk "E: refusal names the unknown-child-kind cleanup" 'grep -q "temp root after an unknown child kind" "$CE/out.txt"'
chk "E: unrelated rollback dir survives (WOULD HAVE BEEN ERASED)" '[ -f "$CE/implementation_process/in_progress/.migration-tmp/.old-unrelated/keepme.txt" ]'
chk "E: original task untouched" '[ -f "$CE/implementation_process/in_progress/demo/marker.txt" ]'
chk "E: peer untouched"          '[ -f "$CE/implementation_process/in_progress/peer/task.md" ]'

# --- case F: empty task name at the failed-epic-copy cleanup -----------------
echo "--- case F: empty task name at the failed-epic-copy temp cleanup"
CF="$WORK/caseF"; mk_epic_project "$CF"; mk_scripts "$CF/scripts"
replace_once "$CF/scripts/migrate-to-epic.sh" \
  'cp -r "$TASK_DIR"/. "$TEMP_ROOT/$TASK_NAME/" || {' \
  'TASK_NAME=""; false || {' \
  "case F injection"
run_migrate "$CF/scripts" "$CF/out.txt" "$CF" theepic newchild
chk_rc_nonzero "F: run refused, exit non-zero"
chk "F: refusal names the failed-epic-copy cleanup" 'grep -q "temp root after a failed epic copy" "$CF/out.txt"'
chk "F: unrelated rollback dir survives (WOULD HAVE BEEN ERASED)" '[ -f "$CF/implementation_process/in_progress/.migration-tmp/.old-unrelated/keepme.txt" ]'
chk "F: existing epic untouched"          '[ -f "$CF/implementation_process/in_progress/theepic/task.md" ]'
chk "F: its existing child untouched"     '[ -f "$CF/implementation_process/in_progress/theepic/in_progress/existing_a/task.md" ]'

printf '\n%d OK, %d FAIL\n' "$OK" "$FAIL"
[ "$FAIL" -eq 0 ]
