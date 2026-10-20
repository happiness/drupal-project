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

1. Copies `scaffold/{phpcs.xml,phpstan.neon,phpunit.xml,gitignore}` to `assets/scaffold/` and replaces
   `%DDEV_PROJECT_URL%` in `phpunit.xml` with the project's DDEV URL.
2. Copies `scaffold/ddev/*` to `.ddev/`: the commands `ddev phpcs`, `phpcbf`, `phpstan`, `phpunit` and `dr`,
   and the [sanitize hook](#database-sanitization). Adds `fail_on_hook_fail: true` to `.ddev/config.yaml`
   unless it is already set or the project has other DDEV hooks.
3. Composer: Drush, `drupal/ai_best_practices`, `drupal/core-dev` (matching the installed
   `drupal/core-recommended` major version) and `happiness/ai-skills`.
4. Maps the scaffold files into the project root (`gitignore` becomes `.gitignore`) via `extra.drupal-scaffold.file-mapping`
   (`replace` mode, `overwrite: false`) and runs `ddev composer drupal:scaffold`. If the project already
   has a `.gitignore`, it adds `/phpcs.xml`, `/phpstan.neon` and `/phpunit.xml` to it, except files the
   project already commits.
5. Sets `config_sync_directory` to `../config/sync` in `settings.php` (when `settings.ddev.php` exists),
   above the `settings.local.php` include so that `settings.local.php` can override it, and enables that
   include, unless it is already enabled.
6. Creates `config/sync`, `modules/custom` and `themes/custom`, with a `.gitkeep` in each one that is empty.

Existing files are never overwritten.

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

`tests/test.bats` builds a Drupal site and a multisite with fake personal data
in DDEV, installs the sanitize hook as `setup.sh` does and checks that
`ddev import-db` anonymizes them. It runs in GitHub Actions on every push, pull request and weekly.
To run it locally, install `bats-core`, `bats-assert`, `bats-file` and
`bats-support` (e.g. with Homebrew), then:

```sh
bats ./tests/test.bats
```
