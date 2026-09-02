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

  # A value read from a file (key@=<path>) reaches the body byte for byte. Two critics measured the
  # inline form on a real criterion and a real recipe block: inside a double-quoted argument every
  # backtick and $(...) ran, the code vanished, and the render exited 0 looking clean.
  VT=$(mktemp); printf 'a `tick` and $(id) and `whoami` and {{not_a_placeholder}} and $HOME\n```yaml\nk: v\n```' > "$VT"
  GOT=$("$RENDER" scope-contract-offer task_name@="$VT" level=L 2>/dev/null || true)
  if printf '%s' "$GOT" | grep -q -F 'a `tick` and $(id) and `whoami` and {{not_a_placeholder}} and $HOME' \
     && printf '%s' "$GOT" | grep -q -F '```yaml'; then
    pass_check "a key@=<path> value is read verbatim: backticks, \$(...), \$VAR, fences and {{...}} survive"
  else
    fail_check "a key@=<path> value was altered on the way into the body"
  fi
  rm -f "$VT"

  # A {{...}} inside a VALUE is data, not an unfilled placeholder: the residual set is the
  # template's own markers minus the keys supplied, decided before substitution. Before this a
  # recipe body with Twig interpolation exited 2 and printed nothing, and a critic was never sent.
  set +e
  "$RENDER" scope-contract-offer task_name='{{ twig }}' level=L >/dev/null 2>&1
  RC=$?
  set -e
  if [ "$RC" -eq 0 ]; then
    pass_check "a {{...}} inside a supplied value does not read as an unfilled placeholder"
  else
    fail_check "a {{...}} inside a supplied value stopped the render (exit $RC)"
  fi
else
  fail_check "scripts/prompt-render.sh is missing — every prompt is improvised wording again"
fi

# ------------------------------------------- the renderer fills, it does not evaluate
# The pre-analysis verdict shipped as one template carrying three
# {{#if decision == "..."}} branches. prompt-render.sh substitutes {{key}} and
# evaluates nothing, so a live run printed all three branches and the raw {{#if}} /
# {{/if}} markers to a person, who then had to be told which block was theirs. The
# unfilled-placeholder guard did not catch it either: it matched {{lower_snake}} only,
# so the markers that were actually there were invisible to the check built to stop
# exactly this. One verdict, one template, rendered whole.

# Only the fenced literal blocks under a Template ID heading are template bodies;
# the prose between them is documentation and may legitimately mention a marker.
TEMPLATE_BODIES="$(awk '
  /^## Template ID: `/ { seen=1; next }
  seen && /^```$/       { infence = !infence; next }
  infence               { print }
' "$PROMPTS")"
if [ -z "$TEMPLATE_BODIES" ]; then
  fail_check "no template bodies extracted — the fence scan is looking in the wrong place"
elif printf '%s' "$TEMPLATE_BODIES" | grep -qE '\{\{[#/]'; then
  fail_check "a template body carries a conditional or loop marker — the renderer has no evaluator, so those markers reach the reader verbatim"
else
  pass_check "no template body carries a marker the renderer cannot fill"
fi

for id in pre-analysis-decision-epic-candidate pre-analysis-decision-keep-flat pre-analysis-decision-insufficient-info; do
  if grep -q "^## Template ID: \`${id}\`$" "$PROMPTS"; then
    pass_check "$id is its own template rather than a branch inside one"
  else
    fail_check "$id is missing — the verdict prompt is back to one template with branches"
  fi
done

# The guard must refuse ANY residual marker, not just a {{lower_snake}} placeholder.
# Built as a throwaway plugin tree so the shipped script needs no test-only override.
GTMP="$(mktemp -d)"
mkdir -p "$GTMP/scripts" "$GTMP/references"
cp "$PLUGIN_ROOT/scripts/prompt-render.sh" "$GTMP/scripts/"
cat > "$GTMP/references/gate-hardening-prompts.md" <<'TPL'
## Template ID: `conditional-probe`

```
Verdict: {{decision}}
{{#if decision == "x"}}
branch text
{{/if}}
```
TPL
# The probe is SUPPOSED to exit 2, so both captures must survive `set -e`:
# a bare assignment from a failing command substitution aborts the script.
GOUT="$(bash "$GTMP/scripts/prompt-render.sh" conditional-probe decision=x 2>&1)" && GRC=0 || GRC=$?
GSTDOUT="$(bash "$GTMP/scripts/prompt-render.sh" conditional-probe decision=x 2>/dev/null)" || true
if [ "$GRC" -eq 2 ] && [ -z "$GSTDOUT" ] && printf '%s' "$GOUT" | grep -q '#if'; then
  pass_check "a conditional marker stops the render, prints nothing, and is named in the error"
else
  fail_check "a conditional marker rendered anyway (rc=$GRC, stdout=$(printf '%s' "$GSTDOUT" | head -c 60))"
fi
rm -rf "$GTMP"

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'prompt-template-spec: all checks passed\n'; exit 0; }
printf 'prompt-template-spec: FAILURES\n' >&2; exit 1
