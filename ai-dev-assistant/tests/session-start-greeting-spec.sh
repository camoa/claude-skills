#!/usr/bin/env bash
# session-start-greeting-spec.sh — what the session greeting says at each of the
# two moments it can fire.
#
# Both branches were written for the moment work is ABOUT to start, and only one
# of them said so. The unregistered branch argues at length that findings made
# before a project exists have nowhere to go. The registered branch said "run
# /next to pick up where you left off" — inert when there is nothing in progress,
# and silent about new work arriving. Observed live: a session in a registered
# project with an empty in_progress/ was asked for a concrete fix and went
# straight to work, never mentioning the project it was inside.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

[ -f "$HOOK" ] || { printf 'FAIL: %s not found\n' "$HOOK" >&2; exit 1; }

HOME_DIR=$(mktemp -d)
trap 'rm -rf "$HOME_DIR"' EXIT
CODE="$HOME_DIR/code"; PROJ="$HOME_DIR/projects/demo"
mkdir -p "$CODE" "$PROJ" "$HOME_DIR/reg"
printf '# Demo\n' > "$PROJ/project_state.md"
cat > "$HOME_DIR/reg/active_projects.json" <<EOF
{"projects":[{"name":"demo","path":"$PROJ","codePath":"$CODE"}]}
EOF

run_in() { ( cd "$1" && AIDA_REGISTRY="$HOME_DIR/reg/active_projects.json" bash "$HOOK" 2>/dev/null ); }

REG_OUT=$(run_in "$CODE")
UNREG_OUT=$(run_in "$HOME_DIR")

# --- the registered branch names the project and speaks to NEW work -----------
printf '%s' "$REG_OUT" | grep -q 'demo' \
  && pass_check "a registered directory is told which project owns it" \
  || fail_check "a registered directory must be told which project owns it"

printf '%s' "$REG_OUT" | grep -qi 'new work' \
  && pass_check "the registered greeting speaks to work that is arriving, not only resuming" \
  || fail_check "the registered greeting must address new work, not only how to resume"

printf '%s' "$REG_OUT" | grep -q 'ai-dev-assistant:scope' \
  && pass_check "it names the command that opens a task" \
  || fail_check "it must name /scope — otherwise there is nothing to act on"

# The call is the model's; what is NOT optional is saying which way it went. A
# greeting that only offers a task lets "too small to track" be decided in
# silence, which looks exactly like never having considered it.
printf '%s' "$REG_OUT" | grep -Eqi 'out loud|say (where|which)|before you start' \
  && pass_check "the choice has to be stated, not made silently" \
  || fail_check "the greeting must require the track-or-not choice to be said out loud"

printf '%s' "$REG_OUT" | grep -Eqi 'does not|just do it|one-line' \
  && pass_check "small work is explicitly allowed to skip the lifecycle" \
  || fail_check "the greeting must permit skipping a task for genuinely small work"

# --- the unregistered branch keeps its argument -------------------------------
printf '%s' "$UNREG_OUT" | grep -q 'ai-dev-assistant:new' \
  && pass_check "an unregistered directory is told how to set a project up" \
  || fail_check "an unregistered directory must be told how to set a project up"

printf '%s' "$UNREG_OUT" | grep -qi 'nowhere to go' \
  && pass_check "the unregistered branch still says why setup comes before analysis" \
  || fail_check "the unregistered branch must keep its reason, not just its command"

# --- the two branches are distinct, and neither is empty ----------------------
[ -n "$REG_OUT" ] && [ -n "$UNREG_OUT" ] \
  && pass_check "both branches produce output" \
  || fail_check "a branch produced nothing"
[ "$REG_OUT" != "$UNREG_OUT" ] \
  && pass_check "the two moments read differently" \
  || fail_check "registered and unregistered must not render the same text"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome invariants FAILED for hooks/session-start.sh.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for the session-start greeting.\n'
exit 0
