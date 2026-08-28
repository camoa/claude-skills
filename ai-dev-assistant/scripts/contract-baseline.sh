#!/usr/bin/env bash
# contract-baseline.sh — freeze the contract a build is judged against, before the build runs.
#
# THE DEFECT THIS EXISTS FOR. `spec-axis-reviewer` and `wo-critic`'s `meets-ac` lens both
# answer "does this change implement what was asked?" by reading `alignment.md` and
# `architecture/`. The builder can edit those files. Nothing recorded what they said when the
# phase opened, so a scope question resolves against whatever the document says NOW — which
# may be text the builder wrote ten minutes ago to describe the code it had just written.
#
# Seen live, and only because the builder annotated its own edit: a `meets-ac` critic ruled an
# addition "blessed only by design-doc text that self-declares added at Phase 3". Had the edit
# been silent the same critic would have read the amended design as the baseline and passed
# it. The same build amended the contract twice.
#
# Editing the contract mid-build is legitimate — a design can be discovered to be impossible,
# and on that build one genuinely was. What is not legitimate is editing it invisibly. This
# script makes the change visible; it never blocks one.
#
# Usage: contract-baseline.sh capture <task_folder>
#        contract-baseline.sh diff    <task_folder>
#
# capture — copies alignment.md and architecture/ to <task>/build-critique/_contract-baseline/
#           Refuses to overwrite an existing baseline: the whole value is that it predates the
#           build. Re-capturing mid-phase would launder exactly the edit it exists to expose.
# diff    — lists what changed since capture. Exit 0 always; the answer is in the JSON.
#
# Emits ONE JSON object on stdout. Exit codes: 0 ok, 2 usage, 4 io.
set -uo pipefail

SUB="${1:-}"; TASK="${2:-}"
case "$SUB" in capture|diff) ;; *)
  echo "contract-baseline: usage: contract-baseline.sh capture|diff <task_folder>" >&2; exit 2 ;;
esac
[ -n "$TASK" ] || { echo "contract-baseline: task folder is required" >&2; exit 2; }
[ -d "$TASK" ] || { echo "contract-baseline: not a directory: $TASK" >&2; exit 4; }
command -v jq >/dev/null 2>&1 || {
  # A check that could not run has established nothing.
  printf '{"schema_version":"1.0","action":"%s","status":"unresolved","reason":"jq_missing"}\n' "$SUB"; exit 4; }

BASE="$TASK/build-critique/_contract-baseline"

# The contract is these two things. A task may legitimately have either, or neither before
# /design has run; "absent" is recorded rather than treated as empty.
present_list() {
  local root="$1" out=()
  [ -f "$root/alignment.md" ] && out+=("alignment.md")
  if [ -d "$root/architecture" ]; then
    while IFS= read -r f; do out+=("architecture/$(basename "$f")"); done \
      < <(find "$root/architecture" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
  fi
  [ -f "$root/architecture.md" ] && out+=("architecture.md")
  printf '%s\n' "${out[@]+"${out[@]}"}"
}

if [ "$SUB" = "capture" ]; then
  if [ -e "$BASE" ]; then
    # Not an error. Re-entering a phase is ordinary; silently refreshing the baseline is not.
    printf '{"schema_version":"1.0","action":"capture","status":"already_present","path":"%s","note":"a baseline predating the build already exists and was left alone"}\n' "$BASE"
    exit 0
  fi
  mkdir -p "$BASE/architecture" 2>/dev/null || { echo "contract-baseline: cannot create $BASE" >&2; exit 4; }
  N=0
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    cp "$TASK/$rel" "$BASE/$rel" 2>/dev/null && N=$((N + 1))
  done < <(present_list "$TASK")
  jq -nc --arg p "$BASE" --argjson n "$N" \
    '{schema_version:"1.0",action:"capture",status:"captured",path:$p,files:$n}'
  exit 0
fi

# diff
if [ ! -d "$BASE" ]; then
  # No baseline means no answer, and "no answer" must never read as "nothing changed".
  jq -nc '{schema_version:"1.0",action:"diff",status:"unresolved",
           reason:"no baseline was captured, so whether the contract changed cannot be determined",
           changed:[],added:[],removed:[]}'
  exit 0
fi
CHANGED='[]'; ADDED='[]'; REMOVED='[]'
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  if [ -f "$BASE/$rel" ]; then
    cmp -s "$TASK/$rel" "$BASE/$rel" || CHANGED=$(jq -c --arg f "$rel" '. + [$f]' <<<"$CHANGED")
  else
    ADDED=$(jq -c --arg f "$rel" '. + [$f]' <<<"$ADDED")
  fi
done < <(present_list "$TASK")
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  [ -f "$TASK/$rel" ] || REMOVED=$(jq -c --arg f "$rel" '. + [$f]' <<<"$REMOVED")
done < <(present_list "$BASE")

jq -nc --argjson c "$CHANGED" --argjson a "$ADDED" --argjson r "$REMOVED" \
  '{schema_version:"1.0",action:"diff",
    status:(if ($c+$a+$r|length)==0 then "unchanged" else "changed" end),
    changed:$c,added:$a,removed:$r}'
