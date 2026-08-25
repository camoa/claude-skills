#!/usr/bin/env bash
# prompt-template-spec.sh — a prompt template cited and never written.
#
# `/research` step 3 cited `prompts:dev-guides-preflight` from v4.10.0. The template was
# never written. Nothing said so: the citation is prose, the reader is a model, and a model
# that cannot find a template does not stop — it composes one. Observed live, a run spent
# three greps hunting for it and then invented its own wording.
#
# The cost is not the wasted greps. A gate with a template renders the same block every
# time; a gate without one renders whatever this run thought of, and what it thinks of is
# named after the only handle it has — the step number in the command file. So a person
# gets asked about "Step 5a", which is an address inside a file they have never opened.
#
# Two steps had no template at all for the same reason, and produced the same symptom.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPTS="${PLUGIN_ROOT}/references/gate-hardening-prompts.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -f "$PROMPTS" ] || { printf 'FAIL: %s missing\n' "$PROMPTS" >&2; exit 1; }

# --------------------------------------------------- every citation resolves to a template

CITED=$(grep -rhoE 'prompts:[a-z0-9-]+' "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/references" \
        | sed 's/prompts://' | sort -u)
[ -n "$CITED" ] || fail_check "no prompt citations found at all — the scan is looking in the wrong place"

DANGLING=0
for id in $CITED; do
  if ! grep -q "Template ID: \`$id\`" "$PROMPTS"; then
    fail_check "prompts:$id is cited but no template defines it"
    DANGLING=$((DANGLING + 1))
  fi
done
[ "$DANGLING" -eq 0 ] && pass_check "every cited prompt template is defined ($(printf '%s' "$CITED" | wc -w | tr -d ' ') citations)"

# ------------------------------------- the three gates that used to improvise now cite one

# Each of these blocks on a person and had no words of its own. Losing the citation again
# would not break anything at runtime, which is exactly why it needs asserting here.
check_cites() { # check_cites <file> <template-id> <what it asks>
  if grep -q "prompts:$2" "$PLUGIN_ROOT/commands/$1"; then
    pass_check "$1 asks $3 with a template"
  else
    fail_check "$1 no longer cites prompts:$2 — $3 goes back to improvised wording"
  fi
}
check_cites research.md  dev-guides-preflight  "which guides to load"
check_cites research.md  scope-contract-offer  "whether to write a scope contract"
check_cites research.md  prior-art-ask         "what prior art the user knows of"
check_cites design.md    scope-contract-offer  "whether to write a scope contract"
check_cites implement.md scope-contract-offer  "whether to write a scope contract"

# ------------------------------------------------------ no step numbers in prompt bodies

# The symptom that started this. A template body is what a person reads, so an address
# from inside a command file has no business in one. Checked on the fenced bodies only —
# the surrounding commentary is written for whoever maintains this file, not for a user.
BODIES=$(awk '/^## Template ID:/{t=1} t&&/^```/{f=!f; next} f&&t{print}' "$PROMPTS")
if printf '%s' "$BODIES" | grep -qiE '\b(step [0-9]+[a-z]?|phase [0-9]+ step)\b'; then
  fail_check "a template body names a step number: $(printf '%s' "$BODIES" | grep -ioE '\bstep [0-9]+[a-z]?\b' | sort -u | tr '\n' ' ')"
else
  pass_check "no template body makes the reader look up a step number"
fi

# A template that pre-answers its own question is not asking it. The prior-art ask exists
# because an assumed answer and a given one are different things.
PA=$(awk '/^## Template ID: `prior-art-ask`/{t=1} t&&/^```/{f=!f; next} f&&t{print}' "$PROMPTS")
if [ -n "$PA" ]; then
  printf '%s' "$PA" | grep -q 'say so' \
    && pass_check "the prior-art prompt makes 'none known' an answer the user gives" \
    || fail_check "the prior-art prompt no longer tells the user that 'none' is a real answer"
else
  fail_check "the prior-art template body is empty"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'prompt-template-spec: all checks passed\n'; exit 0; }
printf 'prompt-template-spec: FAILURES\n' >&2; exit 1
