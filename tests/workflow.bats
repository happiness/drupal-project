#!/usr/bin/env bats

# Tests the git scripts behind the branch workflow (docs/workflow.md) against real
# git histories. Needs no DDEV, so it runs in seconds:
#   bats ./tests/workflow.bats

setup() {
  set -eu -o pipefail
  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-support

  DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  SCRIPTS="${DIR}/.github/scripts"
  cd "${BATS_TEST_TMPDIR}"
  git init -q -b main repo
  cd repo
  git config user.email test@example.com
  git config user.name Test
  git config commit.gpgsign false
  echo base > file.txt
  git add file.txt
  git commit -q -m "Initial commit."
  # dev as reset-dev.sh leaves it: main plus a commit of its own.
  git switch -q -c dev
  git commit -q --allow-empty -m "Reset dev to main (test)."
  git switch -q main
}

# Commits a new file on a new branch from $2.
branch() {
  git switch -q -c "$1" "$2"
  echo "$1" > "$1.txt"
  git add "$1.txt"
  git commit -q -m "Work on $1."
}

# Makes the branches look fetched from origin, as in GitHub Actions.
publish() {
  for b in "$@"; do git update-ref "refs/remotes/origin/$b" "$b"; done
}

@test "a branch merged into dev passes" {
  branch 101-feature main
  git switch -q dev && git merge -q --no-ff --no-edit 101-feature
  publish main dev 101-feature
  git switch -q 101-feature
  run bash "${SCRIPTS}/no-dev-merges.sh" main 101-feature
  assert_success
  assert_output --partial "contains nothing from dev"
}

@test "a branch with dev merged into it fails, with the way out" {
  branch 101-feature main
  git switch -q dev && git merge -q --no-ff --no-edit 101-feature
  branch 102-other main
  git merge -q --no-ff --no-edit dev
  publish main dev 102-other
  run bash "${SCRIPTS}/no-dev-merges.sh" main 102-other
  assert_failure
  assert_output --partial "This branch contains commits from dev"
  assert_output --partial "Merge branch '101-feature' into dev"
  assert_output --partial "git switch -c 102-other-2 origin/main"
}

@test "a branch started from dev fails" {
  branch 103-from-dev dev
  publish main dev 103-from-dev
  run bash "${SCRIPTS}/no-dev-merges.sh" main 103-from-dev
  assert_failure
  assert_output --partial "Reset dev to main"
}

@test "without a dev branch there is nothing to check" {
  git branch -q -D dev
  branch 104-feature main
  publish main 104-feature
  run bash "${SCRIPTS}/no-dev-merges.sh" main 104-feature
  assert_success
  assert_output --partial "There is no dev branch"
}

@test "reset-dev puts back open pull requests and lists the rest" {
  # On dev: #1 (open, then moved on), #2 (released), #3 (open, conflicts with the
  # release), a branch without a pull request and a commit made on dev directly.
  branch 201-open main
  branch 202-released main
  git switch -q -c 203-conflict main
  echo "from 203" > file.txt && git commit -q -am "Change file in 203."
  branch 204-poc main
  git switch -q dev
  for b in 201-open 202-released 203-conflict 204-poc; do git merge -q --no-ff --no-edit "$b"; done
  echo direct > direct.txt && git add direct.txt && git commit -q -m "Committed on dev directly."
  local on_dev
  on_dev="$(git rev-parse 201-open)"
  git switch -q 201-open
  echo more >> 201-open.txt && git commit -q -am "More work on 201, not on dev yet."
  # The release: #2 and a change that conflicts with #3.
  git switch -q main
  git merge -q --no-ff --no-edit 202-released
  echo "from main" > file.txt && git commit -q -am "Change file on main."
  publish main dev

  export PRS_JSON="[
    {\"number\": 3, \"headRefName\": \"203-conflict\", \"headRefOid\": \"$(git rev-parse 203-conflict)\", \"isCrossRepository\": false},
    {\"number\": 1, \"headRefName\": \"201-open\", \"headRefOid\": \"$(git rev-parse 201-open)\", \"isCrossRepository\": false}
  ]"
  export CONFLICTS_FILE="${BATS_TEST_TMPDIR}/conflicts"
  run bash "${SCRIPTS}/reset-dev.sh" main "release 2026-11-13-1"
  assert_success
  assert_output --partial "- #1 201-open"
  assert_output --partial "Not merged back because of conflicts"
  assert_output --partial "- #3 203-conflict"
  assert_output --partial "Merge branch '204-poc' into dev"
  assert_output --partial "Committed on dev directly."
  refute_output --partial "202-released"
  refute_output --partial "Reset dev to main (test)"
  run cat "${CONFLICTS_FILE}"
  assert_output "3"

  # dev is the release plus #1 as dev had it, not its later commit.
  [ "$(git rev-parse --abbrev-ref HEAD)" = dev ]
  git merge-base --is-ancestor main dev
  git merge-base --is-ancestor "${on_dev}" dev
  run git merge-base --is-ancestor 201-open dev
  assert_failure
  run git log -1 --format=%s dev~1
  assert_output "Reset dev to main (release 2026-11-13-1)."

  # A branch from main still can't be fast-forwarded into the new dev.
  publish dev 201-open
  git switch -q 201-open
  run bash "${SCRIPTS}/no-dev-merges.sh" main 201-open
  assert_success
}

@test "reset-dev doesn't put back a pull request that only contains dev" {
  # #5 merged dev into its branch but was never merged into dev itself.
  branch 205-dev-merged-in main
  git merge -q --no-ff --no-edit dev
  publish main dev
  export PRS_JSON="[{\"number\": 5, \"headRefName\": \"205-dev-merged-in\", \"headRefOid\": \"$(git rev-parse 205-dev-merged-in)\", \"isCrossRepository\": false}]"
  run bash "${SCRIPTS}/reset-dev.sh" main "release 2026-11-13-2"
  assert_success
  refute_output --partial "#5"
  run git rev-list --count main..dev
  assert_output "1"
}
