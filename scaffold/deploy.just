# Recipes for the branch and release flow of docs/workflow.md and docs/release.md
# (dev, release, reset-dev), imported by the site's justfile. They need git and the
# GitHub CLI (gh). A site that deploys another way doesn't import this file.
#
# Managed by setup.sh from happiness/drupal-project, which overwrites this file:
# change it there (scaffold/deploy.just), not here. Site recipes go in justfile.

# Show a branch on DEV: push it and merge it into dev (just dev, or just dev 123-feature)
dev branch=`git branch --show-current`:
    #!/usr/bin/env bash
    set -euo pipefail
    branch='{{ branch }}'
    if [[ "$branch" == dev || "$branch" == main || "$branch" == master ]]; then
      echo "Run it on the branch to show on DEV, or name it: just dev <branch>" >&2
      exit 1
    fi
    git push -q -u origin "$branch"
    git fetch -q origin dev
    # Local dev is never worked on, and is force-pushed after each release: take origin's.
    git switch -q -C dev origin/dev
    git merge --no-ff --no-edit "$branch"
    git push -q origin dev
    git switch -q "$branch"
    echo "$branch is merged into dev. DEV is deployed from dev."

# Release: tag the default branch with today's date (YYYY-MM-DD-N), which deploys it to PROD
[confirm("Tag the default branch as a release and deploy it to PROD? [y/N]")]
release:
    #!/usr/bin/env bash
    set -euo pipefail
    base="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
    git fetch -q --tags origin "$base"
    today="$(date +%F)"
    n=1
    while git rev-parse -q --verify "refs/tags/$today-$n" >/dev/null; do n=$((n + 1)); done
    tag="$today-$n"
    commit="$(git rev-parse "origin/$base")"
    gh release create "$tag" --target "$commit" --title "$tag" --generate-notes
    echo "Released $tag: $(git log -1 --format='%h %s' "$commit")"
    echo "PROD is being deployed, and dev reset. Follow it with: gh run watch"

# Reset dev to the default branch now, keeping the open pull requests that are on it
reset-dev:
    gh workflow run reset-dev.yml
    @echo "Started. Follow it with: gh run watch"
