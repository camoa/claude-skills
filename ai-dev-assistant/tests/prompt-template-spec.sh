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
#
# Writing the templates did not fix it. On the first live run after they shipped, both
# prompts that fired were composed fresh anyway. One of them told a person which file was
# missing which section and asked about a numbered phase — the exact wording its template
# was written to replace. Nothing had gone wrong mechanically: "show the literal template"
# was a sentence in a command body, so there was no artifact and no way to check one.
#
# So the templates are now rendered by scripts/prompt-render.sh and the command shows what
# the script printed. These checks follow that: a citation is a call to the renderer, and
# the renderer itself has to refuse the two ways a prompt can reach a person malformed.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPTS="${PLUGIN_ROOT}/references/gate-hardening-prompts.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -f "$PROMPTS" ] || { printf 'FAIL: %s missing\n' "$PROMPTS" >&2; exit 1; }

# --------------------------------------------------- every citation resolves to a template

CITED=$( { grep -rhoE 'prompts:[a-z0-9-]+' "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/references" \
             | sed 's/prompts://'
           grep -rhoE 'prompt-render\.sh [a-z0-9-]+' "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/references" \
             | sed 's/prompt-render\.sh //'
         } | sort -u )
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
  if grep -q "prompt-render\.sh $2" "$PLUGIN_ROOT/commands/$1"; then
    pass_check "$1 renders $3 rather than wording it"
  else
    fail_check "$1 no longer renders $2 — $3 goes back to improvised wording"
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

# ------------------------------------------------- every template appears in the index

# The three templates written in v5.30.0 were never added to the index table above them,
# so the file's own summary said this framework had ten prompts when it had thirteen. A
# reader looking for the guides prompt found no row and concluded there was no template,
# which is one of the two ways the wording got improvised.
DEFINED=$(grep -oE '^## Template ID: `[a-z0-9-]+`' "$PROMPTS" | sed 's/.*`\(.*\)`/\1/' | sort)
INDEXED=$(grep -oE '^\| `[a-z0-9-]+`' "$PROMPTS" | sed 's/.*`\(.*\)`/\1/' | sort -u)
UNINDEXED=$(comm -23 <(printf '%s\n' "$DEFINED") <(printf '%s\n' "$INDEXED") | tr '\n' ' ')
PHANTOM=$(comm -13 <(printf '%s\n' "$DEFINED") <(printf '%s\n' "$INDEXED") | tr '\n' ' ')
if [ -n "$(printf '%s' "$UNINDEXED" | tr -d ' ')" ]; then
  fail_check "template(s) defined but absent from the index: $UNINDEXED"
elif [ -n "$(printf '%s' "$PHANTOM" | tr -d ' ')" ]; then
  fail_check "index row(s) for template(s) that do not exist: $PHANTOM"
else
  pass_check "every template has an index row and every index row has a template"
fi

# ------------------------------------------------ the renderer refuses a malformed prompt

RENDER="$PLUGIN_ROOT/scripts/prompt-render.sh"
if [ -x "$RENDER" ]; then
  pass_check "prompt-render.sh exists and is executable"

  # A filled render must be the template body, character for character. If the renderer
  # can drift from the file, the file has stopped being the source of the wording.
  GOT=$("$RENDER" scope-contract-offer task_name=T level=L 2>/dev/null || true)
  WANT=$(awk '/^## Template ID: `scope-contract-offer`/{t=1; next}
              t && /^## /{exit}
              t && /^```/{f=!f; next}
              t && f{print}' "$PROMPTS" \
         | sed 's/{{task_name}}/T/g; s/{{level}}/L/g')
  if [ "$GOT" = "$WANT" ]; then
    pass_check "a rendered prompt is the template body verbatim"
  else
    fail_check "rendered output differs from the template body in the file"
  fi

  # An unfilled marker must stop. A prompt showing its own machinery is worse than no
  # prompt: the reader cannot tell which part was meant for them.
  OUT=$("$RENDER" scope-contract-offer task_name=T 2>/dev/null || true)
  set +e
  "$RENDER" scope-contract-offer task_name=T >/dev/null 2>&1
  RC=$?
  set -e
  if [ "$RC" -eq 2 ] && [ -z "$OUT" ]; then
    pass_check "an unfilled placeholder stops the render and prints nothing"
  else
    fail_check "an unfilled placeholder rendered anyway (exit $RC, $(printf '%s' "$OUT" | wc -c | tr -d ' ') bytes out)"
  fi

  # An id that does not exist must not fall through to improvisation.
  set +e
  "$RENDER" no-such-template-id >/dev/null 2>&1
  RC=$?
  set -e
  if [ "$RC" -eq 1 ]; then
    pass_check "an unknown template id fails instead of returning nothing"
  else
    fail_check "an unknown template id exited $RC, not 1"
  fi
else
  fail_check "scripts/prompt-render.sh is missing — every prompt is improvised wording again"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'prompt-template-spec: all checks passed\n'; exit 0; }
printf 'prompt-template-spec: FAILURES\n' >&2; exit 1
