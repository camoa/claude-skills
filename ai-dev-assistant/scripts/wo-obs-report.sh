#!/usr/bin/env bash
# wo-obs-report.sh (⑤ telemetry, READER) — the off-line failure-pattern miner.
#
# Owner: observability lane (sibling of wo-obs-append.sh, the WRITER). The writer appends one
# compact NDJSON record per WO to <work-orders-dir>/loop-obs.ndjson as the loop processes each WO;
# THIS kernel READS that log and aggregates it into a single report so recurring failure patterns
# (terminal HALTs, repeated rework) can be mined for triage/learning. It is a passive, READ-ONLY
# consumer: it NEVER writes/renames a *.HALT marker, never touches run.json / a WO status, never
# calls git/gh/merge/PR, and is NEVER part of the gate or merge decision.
#
# A WO can have MULTIPLE records across a run (re-dispatches); the LATEST record (by line order,
# which also tracks recorded_at) is its current state. Latest-per-WO drives the disposition /
# verdict histograms + per_wo; the halt_reasons histogram spans ALL records.
#
# Usage:
#   wo-obs-report.sh <work-orders-dir> [--format json|text] [--rework-threshold N]
#       reads <work-orders-dir>/loop-obs.ndjson. Default --format json, default --rework-threshold 2.
#
# Report (schema_version "1.0"), built EXCLUSIVELY via jq (slurped NDJSON), injection-inert:
#   { schema_version, records, skipped_lines, work_orders, dispositions{...}, halt_reasons{...},
#     review_verdicts{...}, critique_overall{...}, per_wo[], flagged[] }
#   flagged[] = the recurring failure patterns: latest disposition terminal_halt/terminal_escalated
#   (reason "terminal") OR rework_count >= threshold (reason "repeated_rework").
#
# Exit: 0 in all normal cases (incl. a MISSING log — an empty-but-valid report, safe to call always).
# Exit 2 ONLY on a hard usage error (missing/nonexistent <work-orders-dir>) — even then a best-effort
# JSON {schema_version, error} is emitted to stdout + a stderr line. Malformed/blank NDJSON lines are
# skipped defensively (counted in skipped_lines), never crash. One compact stderr summary line always.

set -uo pipefail

DIR=""; FORMAT="json"; THRESH="2"
# --- parse args (positional dir first, then flags) -------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --format)           FORMAT="${2:-json}"; shift 2 || shift ;;
    --rework-threshold) THRESH="${2:-2}"; shift 2 || shift ;;
    --) shift ;;
    -*) shift ;;                       # ignore unknown flags (non-fatal)
    *)  [ -z "$DIR" ] && DIR="$1"; shift ;;
  esac
done
case "$FORMAT" in json|text) ;; *) FORMAT="json" ;; esac          # garbage => json
case "$THRESH" in ''|*[!0-9]*) THRESH=2 ;; esac                   # non-int => default 2

# --- usage error (the ONLY exit-2 path) ------------------------------------
USAGE_ERR=""
if   [ -z "$DIR" ];   then USAGE_ERR="missing_work_orders_dir"
elif [ ! -d "$DIR" ]; then USAGE_ERR="work_orders_dir_missing"
fi
if [ -n "$USAGE_ERR" ]; then
  jq -nc --arg e "$USAGE_ERR" '{schema_version:"1.0", error:$e}'
  printf 'wo-obs-report error=%s\n' "$USAGE_ERR" >&2
  exit 2
fi

LOG="$DIR/loop-obs.ndjson"

# --- pre-filter the NDJSON: keep only valid JSON objects, count the rest ----
# jq -s would abort the whole file on a single malformed line, so we validate line-by-line and
# slurp ONLY the clean lines. A missing log simply yields an empty set ⇒ an empty-but-valid report.
VALID="$(mktemp)"; trap 'rm -f "$VALID"' EXIT
SKIPPED=0
if [ -f "$LOG" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    # blank / whitespace-only line ⇒ skip + count
    if [ -z "${line//[[:space:]]/}" ]; then SKIPPED=$((SKIPPED+1)); continue; fi
    if printf '%s' "$line" | jq -e 'type=="object"' >/dev/null 2>&1; then
      printf '%s\n' "$line" >> "$VALID"
    else
      SKIPPED=$((SKIPPED+1))               # malformed / non-object ⇒ skip + count
    fi
  done < "$LOG"
fi

# --- aggregate (ALL JSON built by jq; latest-per-WO = last in input order) --
REPORT="$(jq -n \
  --slurpfile recs "$VALID" \
  --argjson skipped "$SKIPPED" \
  --argjson thresh "$THRESH" \
  '
  ($recs) as $all
  | ($all | group_by(.wo_id // "")) as $groups
  | ($groups | map(.[-1])) as $latest
  | ($latest
     | reduce .[] as $r ({done:0,needs_rework:0,terminal_halt:0,terminal_escalated:0,unknown:0};
         (($r.disposition // "unknown") | tostring) as $d
         | (if (["done","needs_rework","terminal_halt","terminal_escalated","unknown"] | index($d))
            then $d else "unknown" end) as $dd
         | .[$dd] += 1)) as $disp
  | {
      schema_version: "1.0",
      records: ($all | length),
      skipped_lines: $skipped,
      work_orders: ($latest | length),
      dispositions: $disp,
      halt_reasons: (
        reduce $all[] as $r ({};
          ($r.halt_reason) as $h
          | if $h == null then . else (($h | tostring) as $k | .[$k] = ((.[$k] // 0) + 1)) end)),
      review_verdicts: (
        reduce $latest[] as $r ({};
          (($r.review_verdict // "missing") | tostring) as $k | .[$k] = ((.[$k] // 0) + 1))),
      critique_overall: (
        reduce $latest[] as $r ({};
          (($r.critique_overall // "missing") | tostring) as $k | .[$k] = ((.[$k] // 0) + 1))),
      per_wo: (
        $groups | map(
          . as $g | ($g[-1]) as $last
          | {
              wo_id: ($last.wo_id // null),
              last_disposition: (($last.disposition // "unknown") | tostring),
              attempts: ([ $g[] | (.attempts // 0) ] | max),
              records: ($g | length),
              ever_halted: ([ $g[] | ((.halt_marker_present == true) or (.halted == true)) ] | any),
              rework_count: ([ $g[] | select(.disposition == "needs_rework") ] | length)
            }) | sort_by(.wo_id)),
      flagged: (
        $groups | map(
          . as $g | ($g[-1]) as $last
          | (($last.disposition // "unknown") | tostring) as $dispo
          | ([ $g[] | select(.disposition == "needs_rework") ] | length) as $rc
          | ([ $g[] | (.attempts // 0) ] | max) as $att
          | (if ($dispo == "terminal_halt" or $dispo == "terminal_escalated") then "terminal"
             elif ($rc >= $thresh) then "repeated_rework"
             else null end) as $reason
          | select($reason != null)
          | {
              wo_id: ($last.wo_id // null),
              reason: $reason,
              attempts: $att,
              rework_count: $rc,
              last_disposition: $dispo,
              halt_reason: ($last.halt_reason // null)
            }) | sort_by(.wo_id))
    }')"

# defensive: if jq somehow produced nothing, emit a minimal empty-but-valid report (non-fatal)
[ -n "$REPORT" ] || REPORT="$(jq -nc --argjson s "$SKIPPED" \
  '{schema_version:"1.0", records:0, skipped_lines:$s, work_orders:0,
    dispositions:{done:0,needs_rework:0,terminal_halt:0,terminal_escalated:0,unknown:0},
    halt_reasons:{}, review_verdicts:{}, critique_overall:{}, per_wo:[], flagged:[]}')"

# --- output ----------------------------------------------------------------
if [ "$FORMAT" = "text" ]; then
  printf '%s\n' "$REPORT" | jq -r '
    "wo-obs-report: \(.records) records, \(.work_orders) work-orders (skipped \(.skipped_lines))",
    "dispositions: done=\(.dispositions.done) needs_rework=\(.dispositions.needs_rework) terminal_halt=\(.dispositions.terminal_halt) terminal_escalated=\(.dispositions.terminal_escalated) unknown=\(.dispositions.unknown)",
    (if (.flagged | length) == 0 then "Flagged WOs: none"
     else ("Flagged WOs (\(.flagged | length)):"),
          (.flagged[] | "  \(.wo_id)  \(.reason)  rework=\(.rework_count) attempts=\(.attempts) last=\(.last_disposition)"
             + (if .halt_reason then " halt_reason=\(.halt_reason)" else "" end))
     end),
    (if (.halt_reasons | length) == 0 then "halt reasons: none"
     else "top halt reasons: " + ([.halt_reasons | to_entries[] | "\(.key)=\(.value)"] | join(" "))
     end)'
else
  printf '%s\n' "$REPORT"
fi

# --- one compact stderr summary line ---------------------------------------
printf 'wo-obs-report wos=%s done=%s rework=%s terminal=%s flagged=%s\n' \
  "$(jq -r '.work_orders' <<<"$REPORT" 2>/dev/null)" \
  "$(jq -r '.dispositions.done' <<<"$REPORT" 2>/dev/null)" \
  "$(jq -r '.dispositions.needs_rework' <<<"$REPORT" 2>/dev/null)" \
  "$(jq -r '(.dispositions.terminal_halt + .dispositions.terminal_escalated)' <<<"$REPORT" 2>/dev/null)" \
  "$(jq -r '.flagged | length' <<<"$REPORT" 2>/dev/null)" >&2

exit 0
