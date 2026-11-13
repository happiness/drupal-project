# Branches, pull requests and DEV

How code moves from a ticket to the default branch (`main` or `master`) on every
Drupal site we build. Most of this work is done by AI agents. They follow the
instructions `setup.sh` writes into the site's `AGENTS.md`. GitHub enforces what
matters, so a mistake by a person or an agent is stopped, with a message that says
what to do instead. The git commands you know still work.

| Environment | Runs | Deployed |
|---|---|---|
| DEV | `dev` | on every push to `dev` |
| TEST, where a site has one | the default branch | on every merge |
| PROD | a release tag (`v*`) on the default branch | when the maintainers tag a release |

How releases are tagged and deployed is described separately (to come). Whatever the
tool, every deploy writes the full commit id it deployed to `web/ref.txt`, so anyone
can see what a server runs:

```sh
curl -s https://<site>/ref.txt
git log -1 --oneline "$(curl -s https://<site>/ref.txt)"
```

The file is never committed (`.gitignore`).

## The flow

1. **A branch per ticket**, from the default branch, named after the ticket
   (`123-short-description`).
2. **A pull request to the default branch** for every branch, as a draft until it's
   ready, with `.github/pull_request_template.md` filled in.
3. **Shown on DEV** when the client should see it: the branch is merged into `dev`
   (`just dev`). The client accepts it on DEV.
4. **Merged by the site's maintainers** once the checks are green.
5. **Released** by the maintainers with a release tag. After every release, `dev` is
   reset to the default branch (see below).

## What GitHub enforces

`github-setup.sh` sets up these rulesets on every site's repository:

- Nobody pushes to the default branch directly: everything goes through a pull
  request.
- The `no-dev-merges` check must pass. It stops a pull request with commits made on
  `dev`, that is, when `dev` was merged into the branch or the branch was started
  from `dev`. Its summary says how to fix it: a new branch from the default branch,
  with your own commits cherry-picked onto it.
- **Only the site's maintainers team merges** to the default branch and creates
  release tags. No approval is required: a merge by the maintainers is the decision,
  whether they click it or ask an agent to. GitHub logs who merged. The team uses the
  normal merge button: a branch protection rule restricts who can merge, because a
  ruleset doing the same makes even the team tick "bypass rules" on every merge. The
  organisation's owners can always merge, as an emergency way in.
- Pull requests are merged with a merge commit. Squash and rebase are off, because
  the `dev` check and reset rely on the branches' commits ending up in the default
  branch.
- Release tags are never moved or deleted.

## dev

`dev` is unfinished work shown to the client. Merge branches into it, never the
other way:

```sh
just dev                 # from the branch you want to show
just dev 123-feature     # or name it
```

By hand, that is `git switch dev && git pull && git merge --no-ff <branch> && git push`.
Use `--no-ff`: a fast-forward makes the branch's own commits part of `dev`, and the
check then stops its pull request.

**After every release**, the `reset-dev` workflow resets `dev` to the default branch
and merges back the open pull requests that were on it, as `dev` had them. Its
summary lists what is no longer on `dev`: branches without an open pull request and
commits made on `dev` directly. A pull request that no longer merges cleanly gets a
comment saying so: merge it into `dev` again by hand. `just reset-dev` runs the
reset without a release.

Changes a removed branch made to DEV's database (fields, content, update hooks)
stay until DEV's database is refreshed.

## The maintainers team

Every site has a team `<repository>-maintainers` (under `site-maintainers`): the
person responsible for the site and a deputy. The team has the Maintain role on the
repository and is in `CODEOWNERS`, so it gets the review requests.

- **Review requests** go to the responsible person. The deputy gets them only when
  the responsible person's GitHub status is **Busy**: set it, with an end date, when
  you're away.
- **Longer absence or a new responsible person:** run `github-setup.sh` again with the
  new people, and remove the old ones from the team on GitHub.

## Setting up a site

1. Run `setup.sh` (see the README). Among other things it writes
   `.github/pull_request_template.md`, the workflows `.github/workflows/no-dev-merges.yml`
   and `reset-dev.yml`, `happiness.just`, a `justfile`, and the workflow block in
   `AGENTS.md`.
2. As an organisation owner, from the site's checkout:

   ```sh
   gh auth refresh -h github.com -s admin:org
   curl -fsSL https://raw.githubusercontent.com/happiness/drupal-project/main/github-setup.sh | bash -s -- <responsible> <deputy>
   ```

   Add `--dry-run` to see what it would change first. It writes
   `.github/CODEOWNERS`.
3. Commit the new files in a pull request. The `no-dev-merges` check runs on that pull
   request already.

The workflows' logic lives in this repository (`.github/workflows/` and
`.github/scripts/`). The sites call it, so a fix here reaches every site.

## just

Every site has a `justfile` that imports `happiness.just`, the recipes all sites
share: `just` lists them. `setup.sh` keeps `happiness.just` up to date, so change it
here (`scaffold/happiness.just`). The site's own recipes go in its `justfile`. An
existing `justfile` is left alone: add `import 'happiness.just'` to it and remove
its recipes of the same names.

Install just with `sudo apt install just` (Debian and Ubuntu), `brew install just` or
`cargo install just`.

## Sites without GitHub

For a client who won't have their repository on GitHub, the code lives in a bare
repository on their server. The same flow applies, without pull requests: the
responsible person reviews the branch and merges it, and the server's git
permissions decide who can push to the default branch. It will be set up when the
first client chooses it.
