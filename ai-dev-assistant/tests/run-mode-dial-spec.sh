#!/usr/bin/env bash
# run-mode-dial-spec.sh — verify the run_mode spine (spine_memory, orchestrator_context_hygiene).
#
# Covers:
#   1. project-state-read.sh emits .runMode
#        - absent  → "interactive" (self-contained safe default)
#        - present → "autonomous" when set (case-insensitive header)
#        - bad     → "interactive" + run_mode_bad_value warning (fail-closed, never autonomous)
#   2. fm_read surfaces run_mode from task.md frontmatter in EVERY defensive envelope
#        (folder_missing, task_md_missing, empty-frontmatter, parser_unavailable,
#         main ok, malformed_yaml) — task-level default is null (inherit).
#   3. run-mode-reminder.sh emits an advisory additionalContext envelope and
#        NEVER a decision/permission/block field; second run is cache-skipped ({}).
#
# Run pre-PR.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PSR="${PLUGIN_ROOT}/scripts/project-state-read.sh"
FMREAD="${PLUGIN_ROOT}/scripts/fm-read.sh"
REMINDER="${PLUGIN_ROOT}/hooks/run-mode-reminder.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# =====================================================================
# Part 1 — project-state-read.sh .runMode dial
# =====================================================================
[ -f "$PSR" ] || { fail_check "project-state-read.sh not found"; exit 1; }

PS="$TMPDIR/ps"; mkdir -p "$PS"

# absent → interactive
printf '# Test\n' > "$PS/project_state.md"
actual=$(bash "$PSR" "$PS" 2>/dev/null | jq -r '.runMode')
[ "$actual" = "interactive" ] && pass_check "runMode absent → interactive" \
  || fail_check "runMode absent returned '$actual' (expected interactive)"

# present autonomous → autonomous
printf '# Test\n**Run Mode:** autonomous\n' > "$PS/project_state.md"
actual=$(bash "$PSR" "$PS" 2>/dev/null | jq -r '.runMode')
[ "$actual" = "autonomous" ] && pass_check "runMode autonomous → autonomous" \
  || fail_check "runMode autonomous returned '$actual'"

# present interactive → interactive
printf '# Test\n**Run Mode:** interactive\n' > "$PS/project_state.md"
actual=$(bash "$PSR" "$PS" 2>/dev/null | jq -r '.runMode')
[ "$actual" = "interactive" ] && pass_check "runMode interactive → interactive" \
  || fail_check "runMode interactive returned '$actual'"

# case-insensitive header + mixed-case value
printf '# Test\n**run mode:** Autonomous\n' > "$PS/project_state.md"
actual=$(bash "$PSR" "$PS" 2>/dev/null | jq -r '.runMode')
[ "$actual" = "autonomous" ] && pass_check "runMode lowercase header + Mixed value → autonomous" \
  || fail_check "runMode case-insensitive returned '$actual'"

# bad value → interactive + warning (fail-closed, NEVER autonomous)
printf '# Test\n**Run Mode:** yolo\n' > "$PS/project_state.md"
out=$(bash "$PSR" "$PS" 2>/dev/null)
if [ "$(echo "$out" | jq -r '.runMode')" = "interactive" ] \
   && echo "$out" | jq -e '.warnings[] | select(.code == "run_mode_bad_value")' >/dev/null; then
  pass_check "runMode bad → interactive + run_mode_bad_value warning"
else
  fail_check "runMode bad handling — got: $(echo "$out" | jq -c '.runMode, .warnings')"
fi

# defensive: missing folder still emits runMode
actual=$(bash "$PSR" "$TMPDIR/does-not-exist" 2>/dev/null | jq -r '.runMode')
[ "$actual" = "interactive" ] && pass_check "runMode present in folder_missing envelope" \
  || fail_check "runMode missing from folder_missing envelope (got '$actual')"

# defensive: missing $1 still emits runMode
actual=$(bash "$PSR" 2>/dev/null | jq -r '.runMode')
[ "$actual" = "interactive" ] && pass_check "runMode present in missing_arg envelope" \
  || fail_check "runMode missing from missing_arg envelope (got '$actual')"

# =====================================================================
# Part 2 — fm_read run_mode in every defensive envelope
# =====================================================================
[ -f "$FMREAD" ] || { fail_check "fm-read.sh not found"; exit 1; }

# helper: assert the emitted JSON HAS a run_mode key with expected value
fm_envelope_check() {
  local label="$1" out="$2" expected_run_mode="$3" expected_warn_code="$4"
  if ! echo "$out" | jq -e 'has("run_mode")' >/dev/null 2>&1; then
    fail_check "$label — run_mode key ABSENT (whitelist drop). got: $out"
    return
  fi
  local rm; rm=$(echo "$out" | jq -c '.run_mode')
  if [ "$rm" != "$expected_run_mode" ]; then
    fail_check "$label — run_mode=$rm (expected $expected_run_mode)"
    return
  fi
  if [ -n "$expected_warn_code" ]; then
    if ! echo "$out" | jq -e --arg c "$expected_warn_code" '.warnings[]|select(.code==$c)' >/dev/null; then
      fail_check "$label — expected warning $expected_warn_code missing"
      return
    fi
  fi
  pass_check "$label — run_mode=$expected_run_mode present"
}

# Envelope 1: folder_missing
out=$(bash "$FMREAD" "$TMPDIR/nope-folder" 2>/dev/null)
fm_envelope_check "fm folder_missing" "$out" "null" "folder_missing"

# Envelope 2: task_md_missing
E2="$TMPDIR/e2"; mkdir -p "$E2"
out=$(bash "$FMREAD" "$E2" 2>/dev/null)
fm_envelope_check "fm task_md_missing" "$out" "null" "task_md_missing"

# Envelope 3: empty-frontmatter (task.md with no --- block)
E3="$TMPDIR/e3"; mkdir -p "$E3"
printf '# Just a body\nno frontmatter here\n' > "$E3/task.md"
out=$(bash "$FMREAD" "$E3" 2>/dev/null)
fm_envelope_check "fm empty-frontmatter" "$out" "null" ""

# Envelope 4: parser_unavailable (fake python3 that fails)
E4="$TMPDIR/e4"; mkdir -p "$E4"
printf -- '---\nid: local:x\n---\n# body\n' > "$E4/task.md"
FAKEBIN="$TMPDIR/fakebin"; mkdir -p "$FAKEBIN"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKEBIN/python3"; chmod +x "$FAKEBIN/python3"
out=$(PATH="$FAKEBIN:$PATH" bash "$FMREAD" "$E4" 2>/dev/null)
fm_envelope_check "fm parser_unavailable" "$out" "null" "parser_unavailable"

# Envelope 5a: main ok, run_mode present in frontmatter → surfaced verbatim
E5="$TMPDIR/e5"; mkdir -p "$E5"
printf -- '---\nid: local:x\nrun_mode: autonomous\n---\n# body\n' > "$E5/task.md"
out=$(bash "$FMREAD" "$E5" 2>/dev/null)
fm_envelope_check "fm main ok (override)" "$out" '"autonomous"' ""

# Envelope 5b: main ok, run_mode absent in frontmatter → null (inherit)
E5b="$TMPDIR/e5b"; mkdir -p "$E5b"
printf -- '---\nid: local:x\nstatus: draft\n---\n# body\n' > "$E5b/task.md"
out=$(bash "$FMREAD" "$E5b" 2>/dev/null)
fm_envelope_check "fm main ok (inherit)" "$out" "null" ""

# Envelope 6: malformed_yaml
E6="$TMPDIR/e6"; mkdir -p "$E6"
printf -- '---\nid: [unclosed list\nkind: : : bad\n---\n# body\n' > "$E6/task.md"
out=$(bash "$FMREAD" "$E6" 2>/dev/null)
fm_envelope_check "fm malformed_yaml" "$out" "null" "malformed_yaml"

# =====================================================================
# Part 3 — run-mode-reminder.sh advisory hook
# =====================================================================
[ -f "$REMINDER" ] || { fail_check "run-mode-reminder.sh not found"; exit 1; }

WS="$TMPDIR/ws"; mkdir -p "$WS"
FAKEHOME="$TMPDIR/home"; mkdir -p "$FAKEHOME"
PROJ="$TMPDIR/rproj"; mkdir -p "$PROJ"
printf '# P\n**Run Mode:** autonomous\n' > "$PROJ/project_state.md"

export CLAUDE_CODE_SESSION_ID="rmtest-sid"
# Resolve the session file path in the SAME env the hook will use.
SESS=$(cd "$WS" && HOME="$FAKEHOME" CLAUDE_CODE_SESSION_ID="rmtest-sid" \
  bash -c ". '$PLUGIN_ROOT/scripts/session-paths.sh'; ddf_session_file")
mkdir -p "$(dirname "$SESS")"
jq -n --arg p "$PROJ" '{task:null, taskPath:null, project:"p", projectPath:$p}' > "$SESS"

run_hook() {
  ( cd "$WS" && HOME="$FAKEHOME" CLAUDE_CODE_SESSION_ID="rmtest-sid" bash "$REMINDER" 2>/dev/null )
}

OUT1=$(run_hook)
if echo "$OUT1" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
   && echo "$OUT1" | jq -e '.hookSpecificOutput.additionalContext | test("autonomous")' >/dev/null 2>&1; then
  pass_check "reminder emits additionalContext mentioning the mode"
else
  fail_check "reminder additionalContext — got: $OUT1"
fi
if echo "$OUT1" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1; then
  pass_check "reminder envelope hookEventName = UserPromptSubmit"
else
  fail_check "reminder hookEventName wrong — got: $OUT1"
fi

# CRITICAL: advisory hook must carry NO gating surface anywhere in the envelope.
if echo "$OUT1" | jq -e '
  (has("decision")) or (has("permissionDecision")) or (has("permission")) or
  (has("block")) or (has("continue")) or
  ((.hookSpecificOutput // {}) | (has("decision") or has("permissionDecision") or has("permission")))
' >/dev/null 2>&1; then
  fail_check "reminder leaked a decision/permission/block field — NOT advisory"
else
  pass_check "reminder has NO decision/permission/block field (structurally advisory)"
fi

# Second identical run → cache-skip → empty envelope {} (keeps prefix cache warm).
OUT2=$(run_hook)
if [ "$(echo "$OUT2" | jq -c '.')" = "{}" ]; then
  pass_check "reminder second run cache-skips → {}"
else
  fail_check "reminder second run did not cache-skip — got: $OUT2"
fi

# No session file → exit 0 silently (fast gate).
RC=0
OUT3=$( cd "$WS" && HOME="$FAKEHOME" CLAUDE_CODE_SESSION_ID="no-such-sid" bash "$REMINDER" 2>/dev/null ) || RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT3" ]; then
  pass_check "reminder no-session fast-gate → exit 0, silent"
else
  fail_check "reminder no-session fast-gate — rc=$RC out='$OUT3'"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nrun_mode spine invariants violated.\n' >&2
  exit 1
fi
printf '\nAll run_mode spine invariants pass.\n'
exit 0
