#!/usr/bin/env bash
# Every agent whose return a caller branches on must be able to write, and must have a documented
# sidecar contract.
#
# WHY. The plugin already had this mechanism and a written list of agents excused from it. The list
# was wrong about all three agents on it, in the direction that hides a failure: each one's empty
# return produced a passing verdict rather than the re-dispatch the list promised. A fourth agent,
# the one that actually failed in the field, was on neither the covered list nor the excused one.
#
# A list is only as good as something that checks it. This checks:
#   1. Every agent in the load-bearing set carries Write in `tools:` and has a documented contract.
#   2. The excepted agent is excepted deliberately, named with its reason, rather than by omission.
#   3. No command tells an orchestrator to read the agent's message where a file is the contract.
#   4. No deliver-by-file agent hands the writing back to its caller in its own instructions.
#
# HOW THE CONTRACT HALF USED TO PASS ON NOTHING. It searched references/ for the SUBSTRING
# `_prior-art-`. `_prior-art-confirm-<slug>.json` is a DIFFERENT agent's sidecar and contains that
# substring, so prior-art-researcher's contract was satisfied by prior-art-verdict-confirmer's.
# Measured: deleting references/prior-art-researcher-schema.md AND the gate-audit-schema.md row —
# every genuine mention of `_prior-art-<aspect>.json` in the tree — left this spec green, crediting
# references/internal-prior-art.md, which documents only the confirmer.
#
# The rule now attributes a whole FILENAME to exactly one agent: the one whose prefix is the LONGEST
# that the filename starts with. `_prior-art-confirm-x.json` goes to the confirmer, `_prior-art-x.json`
# to the researcher, and neither can stand in for the other. The attribution rule is itself asserted
# below, because a rule nobody tested is the thing that produced the defect.
#
# What it still cannot check is that the SET is right. An agent added tomorrow that gates something
# and appears in neither list is invisible here, which is exactly how the original gap happened. That
# limit is stated in references/internal-prior-art.md next to the test a reader should apply.
#
# Exit: 0 = every agent in the set is covered; 1 = a gap, or a file is missing.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$DIR/../agents"
COMMANDS="$DIR/../commands"
SCHEMA="$DIR/../references/gate-audit-schema.md"
LIST="$DIR/../references/internal-prior-art.md"
REFS="$DIR/../references"
fail=0
checked=0

for f in "$SCHEMA" "$LIST"; do
  [ -f "$f" ] || { echo "FAIL: not found: $f"; exit 1; }
done

# The load-bearing set: an agent owes a sidecar when a caller branches on its return.
# Each entry is <agent>:<the sidecar filename PREFIX its contract must document>.
#
# The prefix, not the agent name, is what proves a CONTRACT exists. An agent name appears in prose
# for many reasons; its sidecar filename appears only where the file is specified. And the contract
# does not all live in one reference: the distill seam is documented in
# orchestration-context-hygiene.md, which the first draft of this spec did not know, so it failed a
# correctly-documented agent. Searching all of references/ is the fix.
LOAD_BEARING="wo-critic:.critic- distill-agent:_distill.json prior-art-verdict-confirmer:_prior-art-confirm- spec-axis-reviewer:_spec.json architecture-validator:_arch-validate- analysis-agent:_analysis- prior-art-researcher:_prior-art- guides-matcher:_guides-match- ai-test-selector:_test-selection-"

# Deliberately excepted, and the spec asserts the exception is WRITTEN rather than assumed.
EXCEPTED="pattern-recommender"

# attribute <filename> — prints the one agent that filename belongs to, or nothing.
# The LONGEST matching token wins, so a longer agent's filename never satisfies a shorter agent's
# token. This is the whole fix; it is asserted directly further down.
#
# Containment rather than a leading match, because one sidecar carries its subject first:
# wo-critic writes `<component>.critic-<lens>.json`. Containment on its own is what the old spec
# did wrong, so the length rule is what does the work here, not the match.
# ATTR_TABLE is what attribute() reads, so the self-test can hand it a hostile ORDER. The first
# draft could not tell longest-token from first-match-wins: the two agree on the real table only
# because the confirmer happens to be listed before the researcher. Reversing the table separates
# them, and that is the assertion below.
ATTR_TABLE="$LOAD_BEARING"
attribute() {
  local fn="$1" best="" bestlen=0 entry a p
  for entry in $ATTR_TABLE; do
    a=${entry%%:*}
    p=${entry#*:}
    case "$fn" in
      *"$p"*)
        if [ "${#p}" -gt "$bestlen" ]; then best="$a"; bestlen=${#p}; fi
        ;;
    esac
  done
  printf '%s' "$best"
}

# --- the attribution rule is asserted before it is trusted ---
selftest=0
if [ "$(attribute '_prior-art-confirm-mechanism.json')" = "prior-art-verdict-confirmer" ]; then
  echo "PASS: _prior-art-confirm-<slug>.json attributes to the confirmer, not to prior-art-researcher"
  selftest=$((selftest + 1))
else
  echo "FAIL: _prior-art-confirm-<slug>.json attributed to '$(attribute '_prior-art-confirm-mechanism.json')';"
  echo "      a longer agent's filename must never satisfy a shorter agent's prefix"
  fail=1
fi
if [ "$(attribute '_prior-art-caching.json')" = "prior-art-researcher" ]; then
  echo "PASS: _prior-art-<aspect>.json attributes to prior-art-researcher"
  selftest=$((selftest + 1))
else
  echo "FAIL: _prior-art-<aspect>.json attributed to '$(attribute '_prior-art-caching.json')'"
  fail=1
fi
if [ "$(attribute 'kernel.critic-security.json')" = "wo-critic" ]; then
  echo "PASS: <component>.critic-<lens>.json attributes to wo-critic"
  selftest=$((selftest + 1))
else
  echo "FAIL: <component>.critic-<lens>.json attributed to '$(attribute 'kernel.critic-security.json')'"
  fail=1
fi
ATTR_TABLE="prior-art-researcher:_prior-art- prior-art-verdict-confirmer:_prior-art-confirm-"
fwd=$(attribute '_prior-art-confirm-mechanism.json')
ATTR_TABLE="prior-art-verdict-confirmer:_prior-art-confirm- prior-art-researcher:_prior-art-"
rev=$(attribute '_prior-art-confirm-mechanism.json')
ATTR_TABLE="$LOAD_BEARING"
if [ "$fwd" = "prior-art-verdict-confirmer" ] && [ "$rev" = "prior-art-verdict-confirmer" ]; then
  echo "PASS: attribution is decided by token length, not by list order"
  selftest=$((selftest + 1))
else
  echo "FAIL: attribution flipped with list order ('$fwd' forwards, '$rev' reversed)."
  echo "      First-match-wins is not longest-token-wins; on this table they agree by accident."
  fail=1
fi
if [ "$(attribute 'marketplace.json')" = "" ]; then
  echo "PASS: a .json that is nobody's sidecar attributes to nobody"
  selftest=$((selftest + 1))
else
  echo "FAIL: marketplace.json was attributed to '$(attribute 'marketplace.json')'"
  fail=1
fi
if [ "$selftest" -ne 5 ]; then
  echo "FAIL: the attribution self-test ran $selftest of 5 assertions"
  fail=1
fi

# --- every sidecar filename documented under references/, and who documents it ---
# A filename token is anything ending in .json that is not preceded by a path separator, so
# `<task_folder>/_prior-art-<aspect>.json` yields `_prior-art-<aspect>.json`.
OWNED=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  src=${hit%%:*}
  fn=${hit#*:}
  who=$(attribute "$fn")
  [ -n "$who" ] || continue
  OWNED="$OWNED
$who|$fn|${src#"$DIR"/../}"
done <<<"$(grep -roE --include='*.md' '[<._A-Za-z0-9][A-Za-z0-9_<>.-]*\.json' "$REFS" 2>/dev/null | awk -F: '!seen[$2]++')"

for entry in $LOAD_BEARING; do
  a=${entry%%:*}
  prefix=${entry#*:}
  f="$AGENTS/$a.md"
  if [ ! -f "$f" ]; then
    echo "FAIL: $a is in the load-bearing set and has no agent file"
    fail=1
    continue
  fi
  checked=$((checked + 1))

  TOOLS=$(grep -m1 '^tools:' "$f" | sed 's/^tools: *//')
  case ",${TOOLS// /}," in
    *,Write,*) echo "PASS: $a grants Write in tools:" ;;
    *) echo "FAIL: $a is load-bearing and has no Write in tools:, so it cannot write a sidecar"
       fail=1 ;;
  esac

  # Granting Write is not the same as having it. `disallowedTools` DOES bind on an explicit
  # dispatch, and it wins over `tools:`. This spec asserted the opposite in a comment, and four
  # agents shipped in 5.37.0 carrying Write in both lists: the release that made them deliver by
  # file left every one of them unable to write. Measured on a live dispatch: the agent reported
  # "No such tool available: Write", and a general-purpose agent in the same session wrote fine.
  # Reading one line and not the line under it is how a grant and a denial coexist.
  DISALLOWED=$(grep -m1 '^disallowedTools:' "$f" | sed 's/^disallowedTools: *//')
  case ",${DISALLOWED// /}," in
    *,Write,*) echo "FAIL: $a grants Write in tools: and denies it in disallowedTools:, which wins."
               echo "      The agent runs without Write and cannot write its sidecar ${prefix}*.json"
               fail=1 ;;
    *) echo "PASS: $a does not deny the Write it was granted" ;;
  esac

  HIT=$(printf '%s\n' "$OWNED" | grep -m1 "^$a|" || true)
  if [ -n "$HIT" ]; then
    fn=${HIT#*|}; src=${fn#*|}; fn=${fn%%|*}
    echo "PASS: $a's sidecar $fn is specified in $src"
  else
    echo "FAIL: $a is load-bearing and no reference specifies a sidecar filename of its own."
    echo "      Nothing under references/ names a .json file starting ${prefix} that does not"
    echo "      belong to another agent, so its contract is undocumented."
    fail=1
  fi
done

for a in $EXCEPTED; do
  checked=$((checked + 1))
  if grep -q "$a" "$LIST"; then
    echo "PASS: $a's exception is written down"
  else
    echo "FAIL: $a is excepted from the sidecar rule and the exception is nowhere in"
    echo "      references/internal-prior-art.md. An exception by omission is how the original gap happened."
    fail=1
  fi
done

# The absent-state value has to be documented, or a consumer has nothing to record.
if grep -q 'no_return' "$SCHEMA"; then
  echo "PASS: the absent-sidecar value is documented"
  checked=$((checked + 1))
else
  echo "FAIL: no_return is not documented in references/gate-audit-schema.md"
  fail=1
fi

# A spec that checked nothing has not passed.
EXPECTED=$(( $(printf '%s\n' $LOAD_BEARING | wc -w) + $(printf '%s\n' $EXCEPTED | wc -w) + 1 ))
if [ "$checked" -ne "$EXPECTED" ]; then
  echo "FAIL: checked $checked agents, expected $EXPECTED"
  fail=1
fi

# --- no command tells an orchestrator to pipe the agent's MESSAGE into the normalizer ---
# The file is the contract. `/implement` handed the agent an output path, said to read the verdict
# off that file, and in the next sentence told the reader to pipe `"<the agent's JSON>"` into
# analysis-agent-normalize.sh on stdin. A reader following the sentence normalizes the message and
# branches on it, which is the channel the release removed.
cmds=0
cmd_bad=0
for f in "$COMMANDS"/*.md; do
  [ -f "$f" ] || continue
  cmds=$((cmds + 1))
  if grep -qE 'normalize\.sh +-( |$|`)' "$f"; then
    cmd_bad=$((cmd_bad + 1))
    echo "FAIL: ${f##*/} tells the caller to pipe a payload into a normalizer on stdin."
    echo "      The agent was handed an output path; the file is the deliverable and the message is not."
    grep -noE '.{0,60}normalize\.sh +-.{0,30}' "$f" | sed 's/^/      /'
    fail=1
  fi
done
if [ "$cmds" -eq 0 ]; then
  echo "FAIL: no command files found; this check looked at nothing"
  fail=1
elif [ "$cmd_bad" -eq 0 ]; then
  echo "PASS: none of $cmds commands routes an agent's message into a normalizer"
fi

# --- no deliver-by-file agent hands the writing back to its caller ---
# prior-art-researcher's Process ended "Return structured research to the caller (the command writes
# to files)" while the same file's delivery section said the opposite. An agent reads its own
# Process; a contradicted instruction is an instruction.
dbf=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  dbf=$((dbf + 1))
  if grep -qnE 'the (command|caller|dispatcher) (writes|will write)' "$f"; then
    echo "FAIL: ${f##*/} says its caller does the writing, and its own delivery section says it does not."
    grep -nE 'the (command|caller|dispatcher) (writes|will write)' "$f" | sed 's/^/      /'
    fail=1
  else
    echo "PASS: ${f##*/} does not hand its write back to the caller"
  fi
done <<<"$(grep -rl '^## Deliver by file, not by message' "$AGENTS" 2>/dev/null | sort)"
if [ "$dbf" -eq 0 ]; then
  echo "FAIL: no agent carries a 'Deliver by file, not by message' section; this check looked at nothing"
  fail=1
fi

# --- the schema's claim about who reads the normalizer's exit code matches the tree ---
# It said all five call sites read the exit code. One did. The claim is now two lines in the
# reference, and this compares them against the commands, so neither half can move alone.
DOC="$REFS/analysis-agent-schema.md"
sites=$(grep -rln 'analysis-agent-normalize\.sh' "$COMMANDS" 2>/dev/null | while IFS= read -r f; do printf 'commands/%s\n' "${f##*/}"; done | sort -u)
reads=""
noreads=""
for rel in $sites; do
  if grep -qiE '[Rr]ead its exit code|[Rr]ead the exit code' "$COMMANDS/${rel#commands/}"; then
    reads="$reads $rel"
  else
    noreads="$noreads $rel"
  fi
done
# Both sides go through the same normalizer, or an empty list on one side and an empty list on
# the other compare unequal on whitespace alone and the check fails for a reason nobody can act on.
setnorm() { printf '%s\n' "$1" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '; }
declared_reads=$(setnorm "$(grep -m1 '^- \*\*Reads the exit code:\*\*' "$DOC" | grep -oE 'commands/[a-z-]+\.md')")
declared_noreads=$(setnorm "$(grep -m1 '^- \*\*Normalizes and does not read the exit code:\*\*' "$DOC" | grep -oE 'commands/[a-z-]+\.md')")
measured_reads=$(setnorm "$reads")
measured_noreads=$(setnorm "$noreads")
if [ -z "$sites" ]; then
  echo "FAIL: no command invokes analysis-agent-normalize.sh; this check looked at nothing"
  fail=1
elif [ -z "$declared_reads$declared_noreads" ]; then
  echo "FAIL: references/analysis-agent-schema.md declares no exit-code reader list to compare against"
  fail=1
elif [ "$declared_reads" = "$measured_reads" ] && [ "$declared_noreads" = "$measured_noreads" ]; then
  echo "PASS: the schema's exit-code reader list matches all $(printf '%s\n' $sites | wc -w | tr -d ' ') call sites"
else
  echo "FAIL: references/analysis-agent-schema.md disagrees with the commands about who reads the exit code."
  echo "      declared reads   : $declared_reads"
  echo "      measured reads   : $measured_reads"
  echo "      declared no-reads: $declared_noreads"
  echo "      measured no-reads: $measured_noreads"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "OK   sidecar contract: $checked agents, $(printf '%s\n' $LOAD_BEARING | wc -w) load-bearing, $(printf '%s\n' $EXCEPTED | wc -w) excepted, $cmds commands, $dbf deliver-by-file agents"
exit "$fail"
