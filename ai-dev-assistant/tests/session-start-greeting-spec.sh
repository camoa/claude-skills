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

OFFERS="$HOME_DIR/reg/project_offers.json"
run_in() { ( cd "$1" && AIDA_REGISTRY="$HOME_DIR/reg/active_projects.json" AIDA_OFFERS="$OFFERS" \
             bash "$HOOK" 2>/dev/null ); }
run_unattended_in() { ( cd "$1" && AIDA_REGISTRY="$HOME_DIR/reg/active_projects.json" \
             AIDA_OFFERS="$OFFERS" AIDA_UNATTENDED=1 bash "$HOOK" 2>/dev/null ); }

REG_OUT=$(run_in "$CODE")
UNREG_OUT=$(run_in "$HOME_DIR")

# --- the registered branch names the project and speaks to NEW work -----------
printf '%s' "$REG_OUT" | grep -q 'demo' \
  && pass_check "a registered directory is told which project owns it" \
  || fail_check "a registered directory must be told which project owns it"

printf '%s' "$REG_OUT" | grep -qi 'new work' \
  && pass_check "the registered greeting speaks to work that is arriving, not only resuming" \
  || fail_check "the registered greeting must address new work, not only how to resume"

# It has to name a command, and the command has to be the one that opens a task. This asserted
# `/scope` until 2026-09-03, which is how the greeting told every session in this repo the wrong
# front door: `/scope` scaffolds a folder on a miss, so the claim was superficially true and
# substantively wrong, since it charged a scope contract for the act of capturing a task. Creation
# is `/next`, and it offers the contract afterwards.
printf '%s' "$REG_OUT" | grep -q 'ai-dev-assistant:next' \
  && pass_check "it names the command that opens a task" \
  || fail_check "it must name /next — otherwise there is nothing to act on"
printf '%s' "$REG_OUT" | grep -q 'ai-dev-assistant:scope' \
  && fail_check "it must not name /scope as the way to open a task; capturing one costs no contract" \
  || pass_check "and it does not send the reader to /scope to create one"

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

# --- the setup proposal is an offer, and an offer can be turned down ----------------------------
# Until 2026-09-03 the paragraph above was unconditional, so a person who had already said no paid
# the same interruption every session and nothing anywhere recorded that they had answered. The two
# halves of the greeting are now different things: the one-line fact that this code is unregistered,
# which every session gets, and the argument for setting up a project before analysing anything,
# which is the proposal and stops once it has been answered.
WRITER="${PLUGIN_ROOT}/scripts/project-offer-write.sh"
DECLINED="$HOME_DIR/declined"; mkdir -p "$DECLINED"
AIDA_OFFERS="$OFFERS" bash "$WRITER" --dir "$DECLINED" --answer declined >/dev/null 2>&1 \
  && pass_check "a decline can be recorded for a directory with no project to record it in" \
  || fail_check "recording a decline for an unregistered directory must succeed"

DECLINED_OUT=$(run_in "$DECLINED")
printf '%s' "$DECLINED_OUT" | grep -qi 'nowhere to go' \
  && fail_check "a directory whose setup proposal was declined must not be argued at again" \
  || pass_check "the proposal is not repeated once it has been declined"

# Criterion 2 still holds after a decline: the session is told where it is and how to change it.
# Suppressing the whole branch would be a different bug wearing this fix as a disguise.
printf '%s' "$DECLINED_OUT" | grep -q 'ai-dev-assistant:new' \
  && pass_check "a declined directory is still told how to set a project up if it changes its mind" \
  || fail_check "declining the proposal must not hide how to set a project up"
[ -n "$DECLINED_OUT" ] \
  && pass_check "a declined directory still gets a greeting" \
  || fail_check "declining must not silence the greeting entirely"

# THE EXCLUSION: a directory that has declined nothing still gets the proposal. Re-running the
# original unregistered case AFTER a decline exists somewhere else is the check that matters — a
# suppression keyed on the store existing rather than on this directory's answer passes every
# assertion above and fails here.
UNREG_AFTER=$(run_in "$HOME_DIR")
printf '%s' "$UNREG_AFTER" | grep -qi 'nowhere to go' \
  && pass_check "a directory that has not declined still gets the proposal" \
  || fail_check "the proposal must still fire for everyone who has not turned it down"

# --- nobody to answer, so nothing is asked ------------------------------------------------------
UNATT_OUT=$(run_unattended_in "$HOME_DIR")
printf '%s' "$UNATT_OUT" | grep -qi 'nowhere to go' \
  && fail_check "an unattended run must not be handed a proposal nobody can answer" \
  || pass_check "an unattended run is not proposed anything"
printf '%s' "$UNATT_OUT" | grep -q 'ai-dev-assistant:new' \
  && pass_check "an unattended run is still told the directory is unregistered and how to fix it" \
  || fail_check "an unattended run must still get the plain fact of being unregistered"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome invariants FAILED for hooks/session-start.sh.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for the session-start greeting.\n'
exit 0
