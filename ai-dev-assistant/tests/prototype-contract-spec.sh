#!/usr/bin/env bash
# Contract test for /prototype (the throwaway-spike capability).
#
# /prototype is command-prose (Claude executes it), so this is a doc-contract
# test: it asserts commands/prototype.md carries every required contract clause.
# Guards against prose regressions that would silently let a spike become
# entangled with the real build, or blur the throwaway guarantee.
#
# Exit: 0 = all clauses present; 1 = a clause is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="$DIR/../commands/prototype.md"
fail=0

if [ ! -f "$CMD" ]; then
  echo "FAIL: prototype.md not found at $CMD"
  exit 1
fi

check() { # <description> <grep -E pattern>
  if grep -Eq "$2" "$CMD"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1  (missing pattern: $2)"
    fail=1
  fi
}

# --- Frontmatter / usage ---
check "argument-hint frontmatter present"                'argument-hint:.*<design-question>'
check "allowed-tools frontmatter present"                'allowed-tools:'
check "trigger phrasing present (model-invocable)"       "Trigger:"

# --- The one question ---
check "restates the ONE question being answered"         'ONE (design|question)'

# --- Throwaway / disposable guarantee ---
check "throwaway guarantee stated"                        'throwaway'
check "disposable language present"                       'disposable'
check "never commit spike files"                           'never commit'

# --- Isolated-location clause ---
check "isolated scratch location named (.prototypes/)"    '\.prototypes/'
check "gitignore verify step present"                      'check-ignore'
check "location rationale: not a branch"                   'not a throwaway branch|not.*branch'

# --- Logic vs UI split ---
check "LOGIC/STATE path present"                            'LOGIC/STATE'
check "UI/SHAPE path present"                                'UI/SHAPE'
check "runnable terminal program for logic path"           'runnable terminal program'
check "at least 2 toggleable variants for UI path"          '>=2|at least 2|≥2'
check "toggleable from one entry point"                     'toggleable'

# --- Answer-then-discard clause ---
check "explicit answer block required"                      'Prototype answer'
check "answer derived from spike, then discarded"           'This code is throwaway'

# --- Not production / rebuild properly ---
check "never promote to production language"                'promote.*production|NOT to be promoted'
check "rebuild flows through /design -> /implement"         '/design.*->.*implement|/design.*/implement'

# --- Pointer-only integration (no edits to design.md / mechanism-challenge) ---
check "feeds /design as prose evidence pointer"             '/ai-dev-assistant:design'
check "feeds mechanism-challenge as evidence pointer"        'mechanism-challenge'
check "pointer only — does not edit those surfaces"          'does not edit|without editing them|neither.*touches'

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS — prototype contract present in prototype.md"
  exit 0
else
  echo "CONTRACT FAILED — prototype.md missing one or more contract clauses"
  exit 1
fi
