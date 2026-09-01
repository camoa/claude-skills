#!/usr/bin/env bash
# oracle-globs.sh — where the test-file globs come from, and a record of which source was used.
#
# Reads a process recipe's `## Oracle files` block: the first ```json fence under that H2, a top-level
# array of {type, globs, changes, oracle_class, severity}. Emits the `globs` of the row whose type is
# --type (default test_delete). The markdown table beside the fence is never read: two hand-maintained
# copies, nothing checks they agree, and the JSON is the one the tamper guard consumes.
#
# Origins, recorded so a narrow list cannot satisfy a gate on the record while classifying nothing:
#   recipe        the block is present and carries the row
#   convention    no block (or no row); --fallback-globs supplied the set
#   undetermined  no block and no fallback: the caller passes --test-globs-source undetermined
#                 downstream, never [], which would be the positive claim that no test path changed.
#
# Usage: oracle-globs.sh --body <recipe.md> [--type test_delete] [--fallback-globs '<json array>']
# Exit 0 with JSON on stdout; 2 with nothing on stdout on a bad or missing argument.
set -uo pipefail
BODY=""; TYPE="test_delete"; FALLBACK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body) [ "$#" -ge 2 ] || { echo "oracle-globs: --body needs a value" >&2; exit 2; }; BODY="$2"; shift 2 ;;
    --type) [ "$#" -ge 2 ] || { echo "oracle-globs: --type needs a value" >&2; exit 2; }; TYPE="$2"; shift 2 ;;
    --fallback-globs) [ "$#" -ge 2 ] || { echo "oracle-globs: --fallback-globs needs a value" >&2; exit 2; }; FALLBACK="$2"; shift 2 ;;
    *) echo "oracle-globs: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$BODY" ] || { echo "oracle-globs: --body is required" >&2; exit 2; }
[ -r "$BODY" ] || { echo "oracle-globs: body not readable: $BODY" >&2; exit 2; }
if [ -n "$FALLBACK" ] && ! jq -e 'type=="array" and length>0 and all(type=="string" and length>0)' <<<"$FALLBACK" >/dev/null 2>&1; then
  echo "oracle-globs: --fallback-globs must be a non-empty JSON array of non-empty strings" >&2; exit 2
fi

# The fence: from the H2 to the next H2, first ```json ... ``` block. Headings inside fences are not headings.
FENCE="$(awk '
  /^```/ { infence = !infence; if (infence && inblock && !taken && $0 ~ /^```json[[:space:]]*$/) { grab=1; next } ; if (!infence && grab) { grab=0; taken=1 }; next }
  !infence && /^## Oracle files[[:space:]]*$/ { inblock=1; next }
  !infence && /^## / && inblock { inblock=0 }
  grab { print }
' < "$BODY")"

emit() { jq -nc --arg o "$1" --argjson g "$2" --arg t "$TYPE" --arg r "$3" \
  '{schema_version:"1.0", origin:$o, type:$t, globs:$g, reason:(if $r=="" then null else $r end)}'; }

if [ -n "$FENCE" ] && jq -e 'type=="array"' <<<"$FENCE" >/dev/null 2>&1; then
  ROW="$(jq -c --arg t "$TYPE" '[.[] | select(type=="object" and .type==$t)] | .[0] // empty' <<<"$FENCE")"
  if [ -n "$ROW" ] && jq -e '.globs | type=="array" and length>0 and all(type=="string")' <<<"$ROW" >/dev/null 2>&1; then
    emit recipe "$(jq -c '.globs' <<<"$ROW")" ""; exit 0
  fi
  REASON="block present, no $TYPE row with a non-empty globs array"
else
  REASON="no ## Oracle files block with a json fence"
fi
if [ -n "$FALLBACK" ]; then emit convention "$FALLBACK" "$REASON"; else emit undetermined '[]' "$REASON"; fi
