#!/usr/bin/env bash
# TDD spec for scripts/wo-mode-gate.sh — the fail-closed irreversible run-mode gate.
#
# SECURITY-CRITICAL: every ambiguous branch must REFUSE (non-zero). These cases assert BOTH the
# exit code AND the halt_reason so a regression that flips a refuse→allow cannot pass silently.
# Fully network-free: no gh, no real project layout beyond a synthetic project_state.md + task.md.
# Mirrors the harness idiom of wo-ship-gate-spec.sh / wo-pr-open-spec.sh.
set -uo pipefail

HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
KERNEL="$ROOT/scripts/wo-mode-gate.sh"
PR_OPEN="$ROOT/scripts/wo-pr-open.sh"
CRITIQUE_SKILL="$ROOT/skills/work-order-critique/SKILL.md"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL $1: $2"; }

# chk LABEL want_allowed want_exit want_halt OUT RC
chk() {
  local l="$1" wa="$2" we="$3" wh="$4" out="$5" rc="$6" a h
  a="$(jq -r '.allowed'     <<<"$out" 2>/dev/null || echo err)"
  h="$(jq -r '.halt_reason' <<<"$out" 2>/dev/null || echo err)"
  if [ "$a" = "$wa" ] && [ "$rc" -eq "$we" ] && [ "$h" = "$wh" ]; then ok
  else no "$l" "allowed=$a rc=$rc halt=$h (want $wa/$we/$wh) :: $out"; fi
}

# mkproj NAME RUNMODE  → prints project root; project_state.md carries **Run Mode:** RUNMODE (or none)
mkproj() {
  local p="$TMP/$1"; mkdir -p "$p"
  if [ "$2" = "none" ]; then printf '# %s\n' "$1" > "$p/project_state.md"
  else printf '# %s\n**Run Mode:** %s\n' "$1" "$2" > "$p/project_state.md"; fi
  echo "$p"
}
# mktask PROOT SUB [fm_run_mode|none] [confirm|noconfirm]  → prints task folder nested under PROOT
mktask() {
  local t="$1/impl/$2"; mkdir -p "$t"
  if [ "${3:-none}" = "none" ]; then printf -- '---\nid: local:%s\n---\n# task\n' "$2" > "$t/task.md"
  else printf -- '---\nid: local:%s\nrun_mode: %s\n---\n# task\n' "$2" "$3" > "$t/task.md"; fi
  [ "${4:-noconfirm}" = "confirm" ] && : > "$t/.pr-confirm"
  echo "$t"
}

# ─── S1: HALT-on-autonomous — artifact PRESENT and ABSENT both refuse; artifact never consulted ───
PROOT="$(mkproj p1 autonomous)"
T="$(mktask "$PROOT" s1a autonomous confirm)"     # artifact present
out="$(bash "$KERNEL" "$T" --action pr-open 2>/dev/null)"; rc=$?
chk "S1a autonomous + .pr-confirm present" false 1 autonomous_irreversible "$out" "$rc"
T="$(mktask "$PROOT" s1b autonomous noconfirm)"   # artifact absent
out="$(bash "$KERNEL" "$T" --action pr-open 2>/dev/null)"; rc=$?
chk "S1b autonomous + no artifact" false 1 autonomous_irreversible "$out" "$rc"

# ─── S2: proceed-on-interactive-with-artifact ───
PROOT="$(mkproj p2 interactive)"; T="$(mktask "$PROOT" s2 none confirm)"
out="$(bash "$KERNEL" "$T" 2>/dev/null)"; rc=$?
chk "S2 interactive + .pr-confirm → allow" true 0 null "$out" "$rc"

# ─── S3: refuse-on-interactive-missing-artifact ───
PROOT="$(mkproj p3 interactive)"; T="$(mktask "$PROOT" s3 none noconfirm)"
out="$(bash "$KERNEL" "$T" 2>/dev/null)"; rc=$?
chk "S3 interactive + no artifact → refuse" false 1 interactive_unconfirmed "$out" "$rc"

# ─── S4: refuse-on-unreadable-run_mode (broken reader stub → fail-closed) ───
BADPS="$TMP/badps.sh"; printf '#!/usr/bin/env bash\necho "{ not json"\n' > "$BADPS"; chmod +x "$BADPS"
PROOT="$(mkproj p4 interactive)"; T="$(mktask "$PROOT" s4 none confirm)"
out="$(WO_PROJECT_STATE_CMD="$BADPS" bash "$KERNEL" "$T" 2>/dev/null)"; rc=$?
chk "S4 garbage reader → run_mode_unreadable" false 1 run_mode_unreadable "$out" "$rc"
# S4b: project root not found (no project_state.md ancestor) → run_mode_unreadable
ORPHAN="$TMP/orphan/task"; mkdir -p "$ORPHAN"; printf -- '---\nid: local:o\n---\n' > "$ORPHAN/task.md"
out="$(bash "$KERNEL" "$ORPHAN" 2>/dev/null)"; rc=$?
chk "S4b no project_state.md ancestor → unreadable" false 1 run_mode_unreadable "$out" "$rc"

# ─── S5: bad-args → exit 2 ───
out="$(bash "$KERNEL" 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && ok || no "S5a missing task arg" "rc=$rc (want 2)"
out="$(bash "$KERNEL" "$TMP/nonexistent-xyz" 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && ok || no "S5b non-directory task" "rc=$rc (want 2)"
FILEARG="$TMP/afile"; : > "$FILEARG"
out="$(bash "$KERNEL" "$FILEARG" 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && ok || no "S5c file-not-dir task" "rc=$rc (want 2)"
PROOT="$(mkproj p5 interactive)"; T="$(mktask "$PROOT" s5 none confirm)"
out="$(bash "$KERNEL" "$T" --bogus-flag 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && ok || no "S5d unknown flag" "rc=$rc (want 2)"

# ─── S6: --print-cmd stays UNGATED (wo-pr-open --print-cmd must NOT invoke the mode gate) ───
# mode-gate stub that ALWAYS refuses AND logs its invocation; merge-gate stub that says merge_ok.
MODESTUB="$TMP/modestub.sh"; MODELOG="$TMP/modestub.log"; rm -f "$MODELOG"
cat > "$MODESTUB" <<STUB
#!/usr/bin/env bash
echo "INVOKED" >> "$MODELOG"
echo '{"action":"pr-open","mode":"autonomous","allowed":false,"reason":"autonomous_irreversible","halt_reason":"autonomous_irreversible","confirm_artifact":""}'
exit 1
STUB
chmod +x "$MODESTUB"
MGOK="$TMP/mgok.sh"
cat > "$MGOK" <<'STUB'
#!/usr/bin/env bash
echo '{"merge_ok":true,"auto_merge_allowed":true,"reason":"merge_ok"}'
exit 0
STUB
chmod +x "$MGOK"
PCTASK="$TMP/pctask"; mkdir -p "$PCTASK"
cat > "$PCTASK/PR_BODY.md" <<'BODY'
# feat: print-cmd stays ungated
Body.
BODY
out="$(WO_MERGE_GATE_CMD="$MGOK" WO_MODE_GATE_CMD="$MODESTUB" bash "$PR_OPEN" "$PCTASK" --print-cmd 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$MODELOG" ]; then ok
else no "S6 --print-cmd ungated" "rc=$rc mode_gate_invoked=$([ -f "$MODELOG" ] && echo yes || echo no) (want rc=0, gate NOT invoked)"; fi
# S6b: WITHOUT --print-cmd the gate IS consulted and its refusal aborts before any gh call
GHLOG="$TMP/s6b-gh.log"; rm -f "$GHLOG" "$MODELOG"
GHSTUB="$TMP/gh.sh"; printf '#!/usr/bin/env bash\necho called >> "%s"\necho url\n' "$GHLOG" > "$GHSTUB"; chmod +x "$GHSTUB"
out="$(WO_MERGE_GATE_CMD="$MGOK" WO_MODE_GATE_CMD="$MODESTUB" WO_GH_CMD="$GHSTUB" bash "$PR_OPEN" "$PCTASK" 2>/dev/null)"; rc=$?
reason="$(jq -r '.reason' <<<"$out" 2>/dev/null || echo err)"
mg_type="$(jq -r '.mode_gate|type' <<<"$out" 2>/dev/null || echo err)"
if [ "$rc" -ne 0 ] && [ "$reason" = "mode_gate_failed" ] && [ "$mg_type" = "object" ] && [ ! -f "$GHLOG" ]; then ok
else no "S6b gate refusal aborts before gh" "rc=$rc reason=$reason mg_type=$mg_type gh_called=$([ -f "$GHLOG" ] && echo yes || echo no)"; fi

# ─── S7: task-autonomous TIGHTENS project-interactive → refuse (monotonic-toward-strict) ───
PROOT="$(mkproj p7 interactive)"; T="$(mktask "$PROOT" s7 autonomous confirm)"
out="$(bash "$KERNEL" "$T" 2>/dev/null)"; rc=$?
chk "S7 task=autonomous over proj=interactive" false 1 autonomous_irreversible "$out" "$rc"

# ─── S8: task-interactive CANNOT LOOSEN project-autonomous → still refuse ───
PROOT="$(mkproj p8 autonomous)"; T="$(mktask "$PROOT" s8 interactive confirm)"
out="$(bash "$KERNEL" "$T" 2>/dev/null)"; rc=$?
chk "S8 task=interactive cannot loosen proj=autonomous" false 1 autonomous_irreversible "$out" "$rc"

# ─── S9: task-null INHERITS project (interactive) → allow with artifact ───
PROOT="$(mkproj p9 interactive)"; T="$(mktask "$PROOT" s9 none confirm)"
out="$(bash "$KERNEL" "$T" 2>/dev/null)"; rc=$?
chk "S9 task null inherits proj interactive" true 0 null "$out" "$rc"

# ─── S10: reject-non-operator-artifact (defense-in-depth uid mismatch) ───
PROOT="$(mkproj p10 interactive)"; T="$(mktask "$PROOT" s10 none confirm)"
OTHER_UID=$(( $(id -u) + 1 ))
out="$(bash "$KERNEL" "$T" --operator-uid "$OTHER_UID" 2>/dev/null)"; rc=$?
chk "S10 uid mismatch → refuse" false 1 interactive_unconfirmed "$out" "$rc"
# S10b: uid MATCH → allow (proves the check is real, not always-refuse)
out="$(bash "$KERNEL" "$T" --operator-uid "$(id -u)" 2>/dev/null)"; rc=$?
chk "S10b uid match → allow" true 0 null "$out" "$rc"

# ─── S11: kernel writes NOTHING (no .HALT, does not delete .pr-confirm) ───
PROOT="$(mkproj p11 interactive)"; T="$(mktask "$PROOT" s11 none confirm)"
before="$(cd "$T" && find . -type f | sort | md5sum)"
bash "$KERNEL" "$T" >/dev/null 2>&1                       # allow path
PROOT2="$(mkproj p11b autonomous)"; T2="$(mktask "$PROOT2" s11b autonomous confirm)"
bash "$KERNEL" "$T2" >/dev/null 2>&1                      # refuse path
after="$(cd "$T" && find . -type f | sort | md5sum)"
halts="$(find "$T" "$T2" -name '*.HALT' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$before" = "$after" ] && [ -f "$T/.pr-confirm" ] && [ -f "$T2/.pr-confirm" ] && [ "$halts" -eq 0 ]; then ok
else no "S11 kernel is write-free" "fs_changed=$([ "$before" = "$after" ] && echo no || echo yes) confirm_kept=$([ -f "$T/.pr-confirm" ] && echo yes || echo no)/$([ -f "$T2/.pr-confirm" ] && echo yes || echo no) halts=$halts"; fi

# ─── S12: critique-boundary wiring — SKILL prose sources unattended from runMode==autonomous ───
#          AND still keeps the default-true floor (interactive must NOT downgrade forced-on critique).
if grep -q 'runMode == "autonomous"' "$CRITIQUE_SKILL" \
   && grep -qE 'the input is boolean \? it : true' "$CRITIQUE_SKILL"; then ok
else no "S12 critique unattended wiring" "expected both the runMode==autonomous force AND the default-true floor in $CRITIQUE_SKILL"; fi

echo "----"; echo "wo-mode-gate-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
