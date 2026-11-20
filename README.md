# Drupal DDEV setup script

A throwaway script that applies best-practice scaffolding to a fresh DDEV
Drupal project (`drupal/recommended-project`, i.e. `drupal/core-recommended`).
Run it once, then delete it.

## Usage existing site

```sh
ddev composer config allow-plugins.phpstan/extension-installer true
ddev composer config allow-plugins.dealerdirect/phpcodesniffer-composer-installer true

curl -fsSL https://raw.githubusercontent.com/happiness/drupal-project/main/setup.sh | bash
```

Existing files are left alone, so an older project needs some clean-up afterwards. Commit each
step on its own, on a ticket branch.

1. **Old scaffolded check configuration.** Many older projects scaffold `phpcs.xml`, `phpstan.neon` and
   `phpunit.xml` from `assets/scaffold/` through `drupal-scaffold` in `composer.json`, with
   `"overwrite": false`. The copy is created once and then drifts from what CI uses. Remove those
   `[project-root]/...` entries from `extra.drupal-scaffold.file-mapping` (and `assets/scaffold/` files that
   nothing else uses), then run `ddev composer update --lock`. Delete the project's local `phpcs.xml`,
   `phpstan.neon` and `phpunit.xml`, or turn them into overrides that reference the `.dist` file
   (`<rule ref="./phpcs.xml.dist"/>` and `includes: - phpstan.neon.dist`). The tools read `phpcs.xml` and
   `phpstan.neon` before the `.dist` file, so an old copy wins and nothing is shared. Tell the team to do the same
   locally. If the project already committed its own `phpcs.xml.dist` or `phpstan.neon.dist`, `setup.sh` keeps it:
   compare it with `scaffold/` and keep the project's rules only where they differ on purpose.
2. **The `justfile`.** An existing `justfile` is kept. Add `import 'happiness.just'` (and `import 'deploy.just'` if
   the site uses the GitHub branch and release flow) and remove its own recipes of the same names: just doesn't
   allow a recipe in both files. Keep the site's other recipes.
3. **Sites that don't use the GitHub flow**, for example one that deploys with DeployHQ: leave out the
   `deploy.just` import, and delete the workflows `no-dev-merges.yml`, `reset-dev.yml`, `deploy-dev.yml` and
   `deploy-prod.yml` in `.github/workflows/`, `deploy.php`, and the happiness block in `AGENTS.md`. `setup.sh`
   writes missing files again on a later run, so delete them again after one.
4. **Old DDEV commands.** Earlier versions of `setup.sh` copied `phpcs`, `phpcbf`, `phpstan`, `phpunit` and `dr`
   to `.ddev/commands/web/`. The `justfile` recipes `cs`, `fix`, `stan`, `test` and `dr` replace them, so delete
   those files and update any documentation that mentions `ddev phpcs` and the like.
5. **Many existing violations.** Add a baseline instead of fixing everything at once, so CI can block on new
   ones. For PHPStan: `ddev exec vendor/bin/phpstan analyse --generate-baseline` and include
   `phpstan-baseline.neon` from `phpstan.neon.dist`. For phpcs: require the dev dependency
   `digitalrevolution/php-codesniffer-baseline`, allow it under `config.allow-plugins` and commit the generated
   `phpcs.baseline.xml`. PHPStan reports baseline entries that no longer match, phpcs doesn't, so regenerate the
   phpcs baseline now and then.

## Usage new site

```sh
mkdir my-site && cd my-site
ddev config --project-type=drupal11 --docroot=web
ddev composer create-project drupal/recommended-project

curl -fsSL https://raw.githubusercontent.com/happiness/drupal-project/main/setup.sh | bash
# or from a clone (uses the local scaffold/ directory): bash /path/to/setup.sh [--install]
```

`--install` also runs `ddev drush site:install standard` and exports config.
Set `SCAFFOLD_URL` to fetch scaffold files from another location when piping from curl.

## What it does

1. Writes the code checks' configuration to the project root as `phpcs.xml.dist`, `phpstan.neon.dist` and
   `phpunit.xml.dist` (with the project's DDEV URL), to be committed: the tools and CI's `qa` check read them.
   `phpcs.xml`, `phpstan.neon` and `phpunit.xml` stay free for ignored local overrides.
2. Copies `scaffold/ddev/*` to `.ddev/`: the [sanitize hook](#database-sanitization). Adds `fail_on_hook_fail: true` to `.ddev/config.yaml`
   unless it is already set or the project has other DDEV hooks.
3. Composer: Drush, `vlucas/phpdotenv`, `drupal/ai_best_practices` and `drupal/core-dev` (matching the installed
   `drupal/core-recommended` major version). The company's own skills are not installed with Composer: they come
   from the Happiness organisation on claude.ai.
4. On a new site, writes `.gitignore` from `scaffold/gitignore`, keeping any rules a Composer plugin added.
   If the project already had a `.gitignore`, it adds `/phpcs.xml`, `/phpstan.neon` and `/phpunit.xml` to
   it, except files the project already commits, and `/.env.local`, `/web/sites/*/settings.local.php` and
   `/web/ref.txt`.
5. Sets `config_sync_directory` to `../config/sync` in `settings.php` (when `settings.ddev.php` exists),
   above the `settings.local.php` include so that `settings.local.php` can override it, and enables that
   include, unless it is already enabled.
6. Adds `.env.example` and `web/sites/default/settings.env.php`, which reads a server's secrets from
   `.env.local`. Includes it in `settings.php` above the `settings.local.php` include and ends `settings.php`
   with the optional `hash_salt` check, unless `settings.php` already sets secrets of its own. See
   [settings.php and secrets](docs/settings.md).
7. Warns when a `settings.php` is ignored by git or sets `hash_salt` or a database password, and when
   `.env.local` or a `settings.local.php` is tracked by git.
8. Adds the [branch workflow](docs/workflow.md): `.github/pull_request_template.md`, the workflows
   `.github/workflows/no-dev-merges.yml`, `qa.yml` and `reset-dev.yml`, and its block in `AGENTS.md`; and
   for [deploys](docs/release.md), `deploy.php` with the site's hosts to fill in and the workflows
   `deploy-dev.yml` and `deploy-prod.yml`. Writes
   `happiness.just`, the shared `just` recipes, `deploy.just`, the recipes of the branch and release flow,
   and a `justfile` that imports them.
9. Creates `config/sync`, `modules/custom` and `themes/custom`, with a `.gitkeep` in each one that is empty.

Existing files are never overwritten, except the files this repository manages: `happiness.just`, `deploy.just` and
the workflow block in `AGENTS.md` are brought up to date on every run.

`github-setup.sh` sets up the site's repository on GitHub: its maintainers team, permissions and
rulesets. See [Setting up a site](docs/workflow.md#setting-up-a-site).

## Routines

How every Drupal site we build is run:

- [settings.php and secrets](docs/settings.md): `settings.php` in git with all the logic,
  secrets only as values in `.env.local` on each server, and how that file is created
  and changed.
- [Branches, pull requests and DEV](docs/workflow.md): a branch and pull request per ticket,
  `dev` for showing work on DEV, only the site's maintainers merge, and `just`.
- [Releases and deploys](docs/release.md): `just release` tags `YYYY-MM-DD-N`, GitHub Actions
  deploys `dev` to DEV and release tags to PROD with Deployer, and how a server is set up for it.

## Database sanitization

Every `ddev import-db` anonymizes the imported database, so production copies used
for local development carry no real personal data. The `post-import-db` hook in
`.ddev/config.sanitize.yaml` runs `.ddev/sanitize/sanitize.sh`, which does the
following for every site in `web/sites/*/` whose database has been imported:

1. `drush sql:sanitize` with emails set to `user+<uid>@localhost` and every
   password set to `password`.
2. `.ddev/sanitize/sanitize.php`, which also:
   - renames users to `user<uid>` (uid 1 becomes `admin`) and sets `init` to
     the sanitized email,
   - sets commenter IP addresses to `127.0.0.1` and the stored name of the
     last anonymous commenter to `Anonymous`,
   - empties `watchdog`, `flood` and `key_value_expire` (tempstore and other
     expirable data),
   - empties Webform submissions and Contact messages, when those tables exist,
   - checks that every user account was sanitized, and fails with
     `DATABASE NOT SANITIZED` if not.
3. `drush cr`.

**Multisite:** DDEV doesn't tell the hook which database `ddev import-db
--database=<name>` imported into, so every site with an imported database is
sanitized on each import, which is safe to repeat. Sites without a database
(not imported yet) are skipped. If a database with Drupal users belongs to no
site, for example after `--database=<typo>`, the hook fails with
`DATABASE NOT SANITIZED`, because it can't sanitize it.

**Skipping it:** to keep the real data, for example to debug something that
depends on it, run `ddev import-db --skip-hooks --file=<dump>`. This skips all
of the project's `post-import-db` hooks. The local database then holds real
personal data, so import it again without `--skip-hooks` when you're done.

With `fail_on_hook_fail: true`, `ddev import-db` fails if any step fails. The
setting applies to all of the project's hooks, so the script doesn't add it if
`.ddev/config.yaml` or another `.ddev/config.*.yaml` already defines hooks,
because those hooks could then start failing `ddev start` or `ddev import-db`.
It also leaves an existing `fail_on_hook_fail: false` in place. In both cases it
prints a warning. Without the setting, a failed sanitize only prints a warning
and the import still succeeds, so check the output for `DATABASE NOT SANITIZED`.
Add `fail_on_hook_fail: true` yourself once the other hooks are known to succeed.
Log in with `ddev drush uli`, or as any user with the password `password`.

Limitations:

- **Multisite needs Drush to find each site by its directory name**
  (`drush --uri=<directory>`), and a MySQL or MariaDB database.
- **Coverage is not complete.** Personal data can remain in custom entities and
  tables, `path_alias` (e.g. Pathauto aliases containing usernames), `queue`,
  `file_managed` file names and search indexes. Review your site's data.
- **Every account's password is `password`**, including uid 1. Don't expose a
  sanitized site with `ddev share` or on a shared network.

Commit `.ddev/config.sanitize.yaml` and `.ddev/sanitize/`, so everyone on the
project gets the same hook. They are plain project files, so edit them to cover
site-specific data.

**Upgrading an existing project:** `setup.sh` never overwrites these files.
Projects set up before multisite support, or with the old
`ddev-drupal-sanitize` add-on, keep a hook that only sanitizes the default site,
and `setup.sh` warns about it. To upgrade, copy `scaffold/ddev/config.sanitize.yaml`
and `scaffold/ddev/sanitize/` from this repository over the project's files in
`.ddev/`.

## Tests

`tests/test.bats` builds Drupal sites in DDEV: it runs `setup.sh` on a new site and
checks `.gitignore`, `settings.php` and `.env.local`, and checks that `ddev import-db`
anonymizes a site and a multisite with fake personal data. `tests/workflow.bats` runs
the branch workflow's scripts against real git histories, in seconds. Both run in
GitHub Actions on every push, pull request and weekly.

To run them locally, install `just`, `shellcheck`, `bats`, `bats-assert`, `bats-file`
and `bats-support` (`sudo apt install just shellcheck bats bats-assert bats-file bats-support`,
or with Homebrew), then:

```sh
just check      # lint and the workflow tests, in seconds
just test-ddev  # the DDEV tests, about 15 minutes
```
