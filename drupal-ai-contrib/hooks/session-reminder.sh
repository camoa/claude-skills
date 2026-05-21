#!/usr/bin/env bash
# drupal-ai-contrib — SessionStart reminder.
#
# Speaks one line only when the working directory looks like a *Drupal* contribution
# workspace; silent (exit 0) otherwise, so non-contribution sessions are not disturbed.
set -u

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
is_contrib=0

# A bare .gitlab-ci.yml is not Drupal-specific — require a Drupal signal in it.
if [ -f "$proj/.gitlab-ci.yml" ] && \
   grep -qi 'gitlab_templates\|drupal' "$proj/.gitlab-ci.yml" 2>/dev/null; then
  is_contrib=1
fi
[ -d "$proj/.drupal-ai-contrib" ] && is_contrib=1
for f in "$proj"/*.info.yml; do
  [ -e "$f" ] && is_contrib=1
  break
done

if [ "$is_contrib" -eq 1 ]; then
  echo "drupal-ai-contrib: re-confirm the AI-contribution policy and eval guidance for this contribution — they move fast and verify's AI-policy gate fetches them live. Evidence over assertion: every gate passes on a captured artifact, never on a claim."
fi
exit 0
