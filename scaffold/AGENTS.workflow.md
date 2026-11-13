<!-- happiness:start -->
## Happiness workflow

Managed by `setup.sh` from happiness/drupal-project: edit `scaffold/AGENTS.workflow.md`
there, not this block. Background in its `docs/workflow.md` and `docs/settings.md`.

### Branches and pull requests

- Work on a branch per ticket, started from the default branch (`main` or `master`)
  and named after the ticket, as the `git-branch-naming` skill says. Never commit to
  the default branch or to `dev`.
- Open a pull request to the default branch for every branch, as a draft until it is
  ready. Fill in `.github/pull_request_template.md`. Write commit messages as the
  `commit-messages` skill says.
- `dev` is what DEV runs: unfinished work, shown to the client. To show a branch on
  DEV, merge it into `dev` with `git switch dev && git pull && git merge --no-ff <branch> && git push`.
  Never merge `dev` into another branch and never start a branch from it: the
  `no-dev-merges` check then stops the pull request.
- Only the site's maintainers team can merge to the default branch and create
  release tags (`YYYY-MM-DD-N`, e.g. `2026-11-13-1`). When the user asks you to merge or release, do it with their
  account. GitHub refuses if they are not in the team: say so, don't look for a way
  around it.
- Every release tag resets `dev` to the default branch and merges back the open pull
  requests that were on it (`.github/workflows/reset-dev.yml`). A branch without a
  pull request is not put back.

### Settings and secrets

- `settings.php` is committed and holds all logic. Secrets are only values in
  `.env.local` on each server, never in `settings.php` or in git.
- Never read, print or change `.env.local` or `settings.ddev.php`. To use a new
  secret, add its key to `.env.example` and map it from `$env_local` in `settings.php`,
  then tell the user which value to add on each server.
<!-- happiness:end -->
