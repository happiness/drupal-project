#!/usr/bin/env bash
#
# Resets the local branch dev to origin/<base>, then merges back the open pull
# requests that were on dev, at the commit dev had of each. Run by
# .github/workflows/reset-dev.yml after every release, which pushes the result.
#
# Usage: reset-dev.sh <base-branch> <reason>
#
# Expects origin/<base>, origin/dev (if any) and the pull requests' branches to be
# fetched. Reads the open pull requests with gh, or from PRS_JSON (the output of
# `gh pr list --json number,headRefName,headRefOid,isCrossRepository`). Writes the
# numbers of pull requests that could not be merged back to CONFLICTS_FILE, if set.
set -euo pipefail

base="$1"
reason="$2"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
conflicts_file="${CONFLICTS_FILE:-/dev/null}"
: > "$conflicts_file"

old_dev="$(git rev-parse -q --verify origin/dev || true)"
prs_json="${PRS_JSON:-$(gh pr list --state open --base "$base" --limit 200 \
  --json number,headRefName,headRefOid,isCrossRepository)}"

# A commit of its own on top of the base: branches that start from the base can then
# never be fast-forwarded into dev, which no-dev-merges.sh relies on.
git switch -q -C dev "origin/$base"
git commit -q --allow-empty -m "Reset dev to $base ($reason)."

restored=()
conflicts=()
if [[ -n "$old_dev" ]]; then
  # Commits made on dev itself: a pull request that contains them (dev merged into
  # its branch) was not merged into dev by them.
  dev_own="$(git rev-list --first-parent "$old_dev" --not "origin/$base")"
  while IFS=$'\t' read -r number ref oid cross; do
    [[ "$cross" == true ]] && continue
    git cat-file -e "$oid^{commit}" 2>/dev/null || continue
    # The newest commit of the pull request's own that dev had.
    sha=""
    for c in $(git rev-list "$oid" --not "origin/$base"); do
      grep -qxF "$c" <<< "$dev_own" && continue
      if git merge-base --is-ancestor "$c" "$old_dev"; then sha="$c"; break; fi
    done
    [[ -z "$sha" ]] && continue
    if git merge -q --no-ff -m "Merge branch '$ref' (#$number) into dev" "$sha" >/dev/null 2>&1; then
      restored+=("#$number $ref")
    else
      git merge --abort
      conflicts+=("#$number $ref")
      echo "$number" >> "$conflicts_file"
    fi
  done < <(jq -r 'sort_by(.number)[] | [.number, .headRefName, .headRefOid, .isCrossRepository] | @tsv' <<< "$prs_json")
fi

# What was on dev and is neither in the base nor merged back: merges of branches
# without an open pull request, and commits made on dev directly.
lost=()
if [[ -n "$old_dev" ]]; then
  for c in $(git rev-list --first-parent --reverse "$old_dev" --not "origin/$base"); do
    if [[ -n "$(git rev-parse -q --verify "$c^2" || true)" ]]; then
      git merge-base --is-ancestor "$c^2" HEAD && continue
    fi
    git merge-base --is-ancestor "$c" HEAD && continue
    [[ "$(git log -1 --format=%s "$c")" == "Reset dev to "* ]] && continue
    lost+=("$(git log -1 --format='%h %s' "$c")")
  done
fi

{
  echo "## dev reset to $base ($reason)"
  echo
  echo "Merged back (open pull requests that were on dev):"
  if [[ ${#restored[@]} -eq 0 ]]; then echo "- none"; else printf -- '- %s\n' "${restored[@]}"; fi
  if [[ ${#conflicts[@]} -gt 0 ]]; then
    echo
    echo "Not merged back because of conflicts, merge them into dev again by hand:"
    printf -- '- %s\n' "${conflicts[@]}"
  fi
  if [[ ${#lost[@]} -gt 0 ]]; then
    echo
    echo "No longer on dev (no open pull request, or committed on dev directly):"
    printf -- '- %s\n' "${lost[@]}"
  fi
} | tee -a "$summary"
