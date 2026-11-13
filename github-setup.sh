#!/usr/bin/env bash
#
# Sets up a site's GitHub repository for the branch workflow in docs/workflow.md:
#
# - the team <repo>-maintainers (under site-maintainers) with the responsible person
#   and the deputy, with the Maintain role on the repository,
# - the team's review assignment: the responsible person gets every review request,
#   the deputy only when the responsible person's GitHub status is Busy,
# - Write for the developers team,
# - rulesets: no direct pushes to the default branch, the no-dev-merges check must
#   pass, only the team creates release tags (v*), and release tags are never moved
#   or deleted,
# - a branch protection rule: only the team merges to the default branch (and the
#   organisation's owners, as admins),
# - .github/CODEOWNERS in the working tree, for you to commit.
#
# Run it from the site's checkout, as an organisation owner, with gh logged in with
# the admin:org scope (gh auth refresh -s admin:org). Running it again updates
# everything to match; it never removes team members.
#
# Usage: github-setup.sh <responsible> <deputy> [--dry-run]
#   --dry-run  only read, and print what would be changed
set -euo pipefail

PARENT_TEAM=site-maintainers
DEVELOPERS_TEAM=developers
STATUS_CHECK="no-dev-merges / check"

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

DRY_RUN=0
people=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *) people+=("$arg") ;;
  esac
done
[[ ${#people[@]} -eq 2 ]] || usage 1
responsible="${people[0]}"
deputy="${people[1]}"
[[ "$responsible" != "$deputy" ]] || { echo "The responsible person and the deputy must be two people." >&2; exit 1; }

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
org="${repo%%/*}"
team_name="${repo#*/}-maintainers"

# gh api for changes, with the JSON body in $BODY. With --dry-run it prints the call
# (to stderr, as the response is often captured) and responds with {}. Reads always run.
write() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  would: gh api $*" >&2
    if [[ -n "${BODY:-}" ]]; then jq . <<< "$BODY" | sed 's/^/         /' >&2; fi
    echo '{}'
  elif [[ -n "${BODY:-}" ]]; then
    gh api "$@" --input - <<< "$BODY"
  else
    gh api "$@"
  fi
}

# Prints the team's JSON, or nothing when the organisation has no such team.
team_by_name() {
  gh api --paginate "orgs/$org/teams" | jq -c --arg name "$1" '.[] | select(.name == $name)'
}

echo "==> $repo: team $team_name, responsible $responsible, deputy $deputy"
for user in "$responsible" "$deputy"; do
  gh api "orgs/$org/members/$user" --silent 2>/dev/null \
    || { echo "$user is not a member of $org" >&2; exit 1; }
done

echo "==> Teams"
parent="$(team_by_name "$PARENT_TEAM")"
if [[ -z "$parent" ]]; then
  parent="$(BODY="$(jq -n --arg name "$PARENT_TEAM" '{name: $name, privacy: "closed",
    description: "Parent of the teams that merge and release each site."}')" \
    write -X POST "orgs/$org/teams")"
  echo "  create $PARENT_TEAM"
fi
parent_id="$(jq -r '.id // empty' <<< "$parent")"

team="$(team_by_name "$team_name")"
created_team=0
if [[ -z "$team" ]]; then
  created_team=1
  team="$(BODY="$(jq -n --arg name "$team_name" --arg repo "$repo" --argjson parent "${parent_id:-null}" \
    '{name: $name, privacy: "closed", parent_team_id: $parent,
      description: "Merges and releases \($repo), see happiness/drupal-project docs/workflow.md."}')" \
    write -X POST "orgs/$org/teams")"
  echo "  create $team_name"
fi
team_slug="$(jq -r '.slug // empty' <<< "$team")"
team_id="$(jq -r '.id // empty' <<< "$team")"
team_node_id="$(jq -r '.node_id // empty' <<< "$team")"
# In a dry run against a new team there is no id yet.
team_slug="${team_slug:-<new team>}"
team_id="${team_id:-0}"

for user in "$responsible" "$deputy"; do
  BODY='{"role":"member"}' write -X PUT "orgs/$org/teams/$team_slug/memberships/$user" >/dev/null
  echo "  member $user"
done
# GitHub makes whoever creates a team its maintainer, which would let them merge.
me="$(gh api user --jq .login)"
if [[ "$created_team" -eq 1 && "$me" != "$responsible" && "$me" != "$deputy" ]]; then
  BODY='' write -X DELETE "orgs/$org/teams/$team_slug/memberships/$me" >/dev/null
  echo "  remove $me (added by GitHub as the team's creator)"
fi
if [[ $DRY_RUN -eq 0 ]]; then
  others="$(gh api "orgs/$org/teams/$team_slug/members" --jq '.[].login' \
    | grep -vxF -e "$responsible" -e "$deputy" || true)"
  [[ -z "$others" ]] || echo "  warn  $team_slug also has: $(tr '\n' ' ' <<< "$others")(not removed)"
fi

echo "==> Permissions"
BODY='{"permission":"maintain"}' write -X PUT "orgs/$org/teams/$team_slug/repos/$repo" >/dev/null
echo "  maintain $team_slug"
BODY='{"permission":"push"}' write -X PUT "orgs/$org/teams/$DEVELOPERS_TEAM/repos/$repo" >/dev/null
echo "  write    $DEVELOPERS_TEAM"

echo "==> Review assignment"
deputy_node_id="$(gh api "users/$deputy" --jq .node_id)"
# shellcheck disable=SC2016 # GraphQL variables, not shell ones.
query='mutation($team: ID!, $excluded: [ID!]) {
  updateTeamReviewAssignment(input: {id: $team, enabled: true, algorithm: ROUND_ROBIN,
    teamMemberCount: 1, notifyTeam: false, removeTeamRequest: true,
    countMembersAlreadyRequested: true, includeChildTeamMembers: false,
    excludedTeamMemberIds: $excluded}) { team { slug } } }'
if [[ $DRY_RUN -eq 1 ]]; then
  echo "  would: assign every review request to $responsible; to the team when $responsible is Busy"
else
  gh api graphql -f query="$query" -f team="$team_node_id" -f excluded[]="$deputy_node_id" >/dev/null
  echo "  $responsible gets the review requests, $deputy when $responsible is Busy"
fi

echo "==> Rulesets"
existing="$(gh api "repos/$repo/rulesets" --paginate)"
# Creates the ruleset named in the JSON $1, or replaces the one with that name.
ruleset() {
  local name id
  name="$(jq -r .name <<< "$1")"
  id="$(jq -r --arg name "$name" '.[] | select(.name == $name) | .id' <<< "$existing")"
  if [[ -n "$id" ]]; then
    BODY="$1" write -X PUT "repos/$repo/rulesets/$id" >/dev/null
    echo "  update $name"
  else
    BODY="$1" write -X POST "repos/$repo/rulesets" >/dev/null
    echo "  create $name"
  fi
}
team_bypass() { jq -n --argjson id "$team_id" --arg mode "$1" \
  '[{actor_id: $id, actor_type: "Team", bypass_mode: $mode},
    {actor_id: 5, actor_type: "RepositoryRole", bypass_mode: $mode}]'; }

# Only the team merges to the default branch. A branch protection rule, not a ruleset:
# a ruleset's "Restrict updates" makes even its bypass list tick "bypass rules" on
# every merge, while this gives the team the normal merge button. Repository admins
# (the organisation's owners) can always merge, as an emergency way in.
default_branch="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
BODY="$(jq -n --arg team "$team_slug" '{
  required_status_checks: null, enforce_admins: false, required_pull_request_reviews: null,
  restrictions: {users: [], teams: [$team], apps: []}}')" \
  write -X PUT "repos/$repo/branches/$default_branch/protection" >/dev/null
echo "  protect $default_branch: only $team_slug merges"

ruleset "$(jq -n --arg check "$STATUS_CHECK" '{
  name: "default branch: pull requests and checks", target: "branch", enforcement: "active",
  conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
  bypass_actors: [],
  rules: [
    {type: "deletion"},
    {type: "non_fast_forward"},
    {type: "pull_request", parameters: {
      required_approving_review_count: 0, dismiss_stale_reviews_on_push: false,
      require_code_owner_review: false, require_last_push_approval: false,
      required_review_thread_resolution: false, allowed_merge_methods: ["merge"]}},
    {type: "required_status_checks", parameters: {
      strict_required_status_checks_policy: false, do_not_enforce_on_create: false,
      required_status_checks: [{context: $check}]}}
  ]}')"
ruleset "$(jq -n --argjson bypass "$(team_bypass always)" '{
  name: "release tags: only maintainers create", target: "tag", enforcement: "active",
  conditions: {ref_name: {include: ["refs/tags/v*"], exclude: []}},
  bypass_actors: $bypass,
  rules: [{type: "creation"}]}')"
ruleset "$(jq -n '{
  name: "release tags: never moved or deleted", target: "tag", enforcement: "active",
  conditions: {ref_name: {include: ["refs/tags/v*"], exclude: []}},
  bypass_actors: [],
  rules: [{type: "update"}, {type: "deletion"}, {type: "non_fast_forward"}]}')"

echo "==> CODEOWNERS"
owners="* @$org/$team_slug"
if [[ ! -e .github/CODEOWNERS ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  would: write .github/CODEOWNERS: $owners"
  else
    mkdir -p .github
    printf '# Review requests go to the team that merges and releases this site.\n%s\n' "$owners" > .github/CODEOWNERS
    echo "  write .github/CODEOWNERS: commit it in a pull request"
  fi
elif ! grep -qF "@$org/$team_slug" .github/CODEOWNERS; then
  echo "  warn  .github/CODEOWNERS doesn't mention @$org/$team_slug. Add: $owners"
fi

cat <<MSG

Done. When away, $responsible sets their GitHub status to Busy (with an end date),
and review requests go to $deputy. To change who is responsible, run this again
with the new people and remove the old ones from the team $team_slug.
MSG
