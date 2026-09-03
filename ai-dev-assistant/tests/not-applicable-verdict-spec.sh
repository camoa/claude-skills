#!/usr/bin/env bash
# not-applicable-verdict-spec.sh — "considered, does not apply" is its own answer.
#
# THE STATE THIS FILE EXISTS FOR. A gate can end in three different places and the
# framework had words for only two of them:
#
#   it looked and found nothing wrong      pass
#   it could not look at all               skipped + unresolved: true
#   it looked at its own scope, found
#   nothing of its kind in the change,
#   and said why                           ← had no word
#
# The third landed on one of the other two, and both readings are wrong in a way that
# matters. `security-check.sh`'s correctly-scoped no-op resolved to the same `skipped`
# word an unreadable report gets, so a reader of the verdict alone could not tell a
# docs-only diff from a scanner that returned nothing usable. Worse, `dry-check.sh`'s
# no-PHP-in-the-changed-set branch writes `"status": "pass"` with a `skip_reason`, and
# the resolver reported `dry: duplication measured and within target` — a full green
# claiming a measurement that never happened, on the majority of documentation pull
# requests. That is the false all-clear, and it was live.
#
# `not_applicable` is the third word. It is a COMPLETED check: it counts as applied, it
# passes, and it is never folded into `skipped`.
#
# THE REASON IS NOT OPTIONAL. A `not_applicable` that cannot say why nothing applied is
# indistinguishable from a gate nobody ran, so the reason is what the branch keys on: a
# report that declines without naming a reason resolves `unresolved`, exactly as before.
# Cells X1-X3 are that exclusion, and they are the half that keeps this from becoming a
# new way to go green.
#
# Env seams, for the mutation run only: NA_SPEC_RESOLVER / NA_SPEC_EMITTER override the
# two scripts under test.
#
# Exit 0 on all-pass; 1 on any failure.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="${NA_SPEC_RESOLVER:-$ROOT/scripts/gate-verdict-resolve.sh}"
EMITTER="${NA_SPEC_EMITTER:-$ROOT/scripts/validation-envelope-write.sh}"
REVIEW="$ROOT/commands/review.md"
CONTRACT="$ROOT/references/validation-gate-result.md"
SCHEMA="$ROOT/references/gate-audit-schema.md"

FAIL=0
ok()  { printf 'OK   %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; [ $# -lt 2 ] || printf '      got: %s\n' "$2" >&2; FAIL=1; }
eq()  { # eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2')" "$3"; fi
}

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
for f in "$RESOLVER" "$EMITTER" "$REVIEW" "$CONTRACT" "$SCHEMA"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TASK="$WORK/task"; mkdir -p "$TASK"

# The catalog is irrelevant to every case below (no gaps anywhere), so the resolver runs
# without one; that only makes gaps block, and there are none.

# ── fixtures ────────────────────────────────────────────────────────────────
# Each is the shape its producer really writes; the producer path is named beside it.

# code-quality-tools/skills/code-quality-audit/scripts/drupal/security-check.sh, the
# `RELEVANT_FILES == 0 && HAS_COMPOSER == false` branch.
cat > "$WORK/sec-na.json" <<'J'
{"meta":{"timestamp":"2026-09-03T00:00:00Z","scan_type":"security_audit_changed","mode":"changed",
 "tools_run":[],"tools_absent":[],"tools_failed":[],"tools_unmeasured":[],
 "tools_skipped":["semgrep","gitleaks"],"skip_reason":"no_eligible_changes"},
 "summary":{"overall_status":"skipped","total_issues":0},"issues":[]}
J

# The same word with no reason attached — the shape drupal/solid-check.sh's own
# no-PHP branch writes. Nothing here says a layer was considered and excused.
cat > "$WORK/sec-mute.json" <<'J'
{"meta":{"timestamp":"2026-09-03T00:00:00Z","mode":"changed",
 "tools_absent":[],"tools_failed":[],"tools_unmeasured":[],"tools_skipped":[]},
 "summary":{"overall_status":"skipped","total_issues":0},"issues":[]}
J

# code-quality-tools/skills/code-quality-audit/scripts/drupal/dry-check.sh, the
# `_DRY_HAS_PHP == false` branch. Note `"status": "pass"` — this is the live false green.
cat > "$WORK/dry-na.json" <<'J'
{"changed_mode":true,"duplication_percentage":0,"total_lines":0,"duplicated_lines":0,
 "clone_count":0,"clones":[],"rating":"excellent","status":"pass",
 "skip_reason":"no PHP files in changed set","generated_at":"2026-09-03T00:00:00Z"}
J

# A dry report that declines and names no reason.
cat > "$WORK/dry-mute.json" <<'J'
{"mode":"changed","rating":"skipped","status":"skipped","tools_absent":[],
 "generated_at":"2026-09-03T00:00:00Z"}
J

# An ordinary measured dry run, so the new branch cannot be shown to swallow one.
cat > "$WORK/dry-real.json" <<'J'
{"mode":"whole-project","measured":true,"duplication_percentage":1.2,"rating":"excellent",
 "status":"pass","tools_absent":[],"generated_at":"2026-09-03T00:00:00Z"}
J

# The dry analyzer is gone. Nobody looked; this must never become not_applicable.
cat > "$WORK/dry-absent.json" <<'J'
{"mode":"skipped","rating":"skipped","status":"skipped","skip_reason":"tool_absent",
 "tools_absent":["phpcpd"],"generated_at":"2026-09-03T00:00:00Z"}
J

r() { bash "$RESOLVER" "$@" 2>/dev/null || true; }

# ── N: the resolver has the third word ──────────────────────────────────────

OUT="$(r security "$WORK/sec-na.json")"
eq "N1 security scope no-op resolves not_applicable" "not_applicable" "$(jq -r '.verdict' <<<"$OUT")"
eq "N2 it is not unresolved — the gate did look at its own scope" "false" "$(jq -r '.unresolved' <<<"$OUT")"
eq "N3 it carries the reason the producer gave" "no_eligible_changes" "$(jq -r '.reason' <<<"$OUT")"
eq "N4 it sets no partial-coverage marker" "false" "$(jq -r '.coverage_partial' <<<"$OUT")"
if jq -e '[.messages[] | select(test("unresolved: true"))] | length == 0' <<<"$OUT" >/dev/null; then
  ok "N5 no unresolved marker reaches review's fail-closed rule"
else bad "N5 no unresolved marker reaches review's fail-closed rule" "$OUT"; fi

OUT="$(r dry "$WORK/dry-na.json")"
eq "N6 dry no-eligible-files resolves not_applicable, not pass" "not_applicable" "$(jq -r '.verdict' <<<"$OUT")"
eq "N7 dry not_applicable carries the producer's reason" "no PHP files in changed set" "$(jq -r '.reason' <<<"$OUT")"
eq "N8 dry not_applicable is not unresolved" "false" "$(jq -r '.unresolved' <<<"$OUT")"
if jq -e '[.messages[] | select(test("measured and within target"))] | length == 0' <<<"$OUT" >/dev/null; then
  ok "N9 dry no longer claims duplication was measured when nothing was eligible"
else bad "N9 dry no longer claims duplication was measured when nothing was eligible" "$OUT"; fi

eq "N10 the resolver still exits 0 on a not_applicable answer" "0" \
  "$(bash "$RESOLVER" dry "$WORK/dry-na.json" >/dev/null 2>&1; echo $?)"

# ── X: the exclusion. No reason, no not_applicable. ─────────────────────────

OUT="$(r security "$WORK/sec-mute.json")"
eq "X1 a security decline with no reason is not not_applicable" "skipped" "$(jq -r '.verdict' <<<"$OUT")"
eq "X2 and it stays unresolved" "true" "$(jq -r '.unresolved' <<<"$OUT")"

OUT="$(r dry "$WORK/dry-mute.json")"
eq "X3 a dry decline with no reason is not not_applicable" "skipped" "$(jq -r '.verdict' <<<"$OUT")"
eq "X4 and it stays unresolved" "true" "$(jq -r '.unresolved' <<<"$OUT")"

OUT="$(r dry "$WORK/dry-absent.json")"
eq "X5 an absent analyzer is nobody-looked, never not_applicable" "skipped" "$(jq -r '.verdict' <<<"$OUT")"
eq "X6 and it stays unresolved" "true" "$(jq -r '.unresolved' <<<"$OUT")"

OUT="$(r dry "$WORK/dry-real.json")"
eq "X7 a real measured dry run is still pass" "pass" "$(jq -r '.verdict' <<<"$OUT")"
eq "X8 a real measured run records no not-applicable reason" "null" "$(jq -r '.reason' <<<"$OUT")"

OUT="$(r tdd "" --exit-code 0)"
eq "X9 a gate that ran its tests is still pass" "pass" "$(jq -r '.verdict' <<<"$OUT")"

# ── E: the envelope carries it, and no count hides it ───────────────────────

e() { bash "$EMITTER" "$@" 2>/dev/null || true; }

OUT="$(e gate --gate dry --task na_spec --task-folder "$TASK" --stdout-only \
        --verdict not_applicable --message "no PHP files in changed set")"
eq "E1 the envelope writer accepts not_applicable" "not_applicable" "$(jq -r '.verdict' <<<"$OUT")"
eq "E2 status and verdict stay paired" "true" "$(jq -r '.status == .verdict' <<<"$OUT")"
eq "E3 a not-applicable finding is INFO, not an alarm" "INFO" "$(jq -r '.findings[0].severity' <<<"$OUT")"

OUT="$(e aggregate --task na_spec --task-folder "$TASK" --stdout-only \
        --gates-json '[{"gate":"dry","verdict":"not_applicable"},{"gate":"security","verdict":"not_applicable"}]')"
eq "E4 an all-not-applicable run does not read as nobody-looked" "not_applicable" "$(jq -r '.status' <<<"$OUT")"
eq "E5 and it is counted, not dropped" "2" "$(jq -r '.summary.not_applicable' <<<"$OUT")"
eq "E6 it is not folded into the pass count" "0" "$(jq -r '.summary.pass' <<<"$OUT")"
eq "E7 it is not folded into the skipped count" "0" "$(jq -r '.summary.skipped' <<<"$OUT")"

OUT="$(e aggregate --task na_spec --task-folder "$TASK" --stdout-only \
        --gates-json '[{"gate":"tdd","verdict":"pass"},{"gate":"dry","verdict":"not_applicable"}]')"
eq "E8 a real pass beside it still reads pass" "pass" "$(jq -r '.status' <<<"$OUT")"

OUT="$(e aggregate --task na_spec --task-folder "$TASK" --stdout-only \
        --gates-json '[{"gate":"tdd","verdict":"fail"},{"gate":"dry","verdict":"not_applicable"}]')"
eq "E9 it never softens a fail" "fail" "$(jq -r '.status' <<<"$OUT")"

OUT="$(e aggregate --task na_spec --task-folder "$TASK" --stdout-only \
        --gates-json '[{"gate":"tdd","verdict":"skipped"},{"gate":"dry","verdict":"not_applicable"}]')"
eq "E10 considered-and-excused outranks nobody-looked" "not_applicable" "$(jq -r '.status' <<<"$OUT")"

# ── C: the consumers know the word ──────────────────────────────────────────
# A verdict no aggregator has a rule for is the defect review's rule 4 exists to close,
# so the rules have to name it rather than leave it to fall off the end of the list.

if grep -q 'not_applicable' "$REVIEW"; then
  ok "C1 review's aggregation names not_applicable"
else bad "C1 review's aggregation names not_applicable"; fi

if grep -n 'not_applicable' "$REVIEW" | grep -qE 'benign|rule 5|pass. if every'; then
  ok "C2 review treats it as a benign state that does not block"
else bad "C2 review treats it as a benign state that does not block"; fi

if grep -q 'pass | warning | fail | not_applicable | skipped' "$SCHEMA" \
   || grep -qE 'gates_run.*not_applicable|not_applicable.*bypassed' "$SCHEMA"; then
  ok "C3 the audit schema's gate verdict enum carries it"
else bad "C3 the audit schema's gate verdict enum carries it"; fi

if grep -q 'not_applicable' "$CONTRACT"; then
  ok "C4 the gate-result contract documents it"
else bad "C4 the gate-result contract documents it"; fi

for w in tdd solid dry security; do
  if grep -q 'not_applicable' "$ROOT/commands/validate-$w.md"; then
    ok "C5-$w the $w wrapper's verdict row carries it"
  else bad "C5-$w the $w wrapper's verdict row carries it"; fi
done

# The batch runner prints a totals line to a person. A verdict with no column there is a
# gate that ran and left no trace in the only number anyone reads.
ALL="$ROOT/commands/validate-all.md"
if grep -q 'not_applicable' "$ALL"; then
  ok "C6 the batch runner's aggregation names it"
else bad "C6 the batch runner's aggregation names it"; fi
if grep -qE 'Totals:.*not.applicable' "$ALL"; then
  ok "C7 the printed totals line gives it a column of its own"
else bad "C7 the printed totals line gives it a column of its own"; fi

if [ "$FAIL" = "0" ]; then
  printf '\nnot-applicable-verdict-spec: all checks passed\n'
else
  printf '\nnot-applicable-verdict-spec: FAILURES\n' >&2
fi
exit "$FAIL"
