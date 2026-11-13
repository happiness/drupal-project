#!/usr/bin/env bash
#
# Fails when HEAD contains commits made on dev, which must never reach the base
# branch (main). Run by .github/workflows/no-dev-merges.yml on every pull request.
#
# Usage: no-dev-merges.sh <base-branch> <head-branch-name>
#
# Expects origin/<base> and, if the repository has one, origin/dev to be fetched.
# Commits made on dev itself (its merges, and anything committed there directly)
# are dev's first-parent line. Branches merged into dev with --no-ff are not on it,
# so they pass.
set -euo pipefail

base="$1"
head_ref="$2"

if ! git rev-parse --verify -q origin/dev >/dev/null; then
  echo "There is no dev branch, so there is nothing to check."
  exit 0
fi

found="$(git rev-list HEAD --not "origin/$base" \
  | grep -Fxf <(git rev-list --first-parent origin/dev --not "origin/$base") || true)"
if [[ -z "$found" ]]; then
  echo "The branch contains nothing from dev."
  exit 0
fi

{
  echo "## This branch contains commits from dev"
  echo
  echo "Code reaches $base only from feature branches. These commits were made on dev, usually because dev was merged into this branch or the branch was started from dev:"
  echo
  echo '```'
  for c in $found; do git log -1 --format='%h %s' "$c"; done
  echo '```'
  echo
  echo "To fix it, start a new branch from $base, copy your own commits to it and open a new pull request:"
  echo
  echo '```'
  echo "git fetch origin"
  echo "git switch -c ${head_ref}-2 origin/$base"
  echo "git log --oneline --no-merges origin/$base..origin/${head_ref}   # find your own commits"
  echo "git cherry-pick <commit> ..."
  echo '```'
  echo
  echo "To show a branch on DEV, merge it into dev, never the other way: \`git switch dev && git merge --no-ff ${head_ref}\`."
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "::error::This branch contains commits from dev. See the job summary for how to fix it."
exit 1
