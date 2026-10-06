# Drupal DDEV setup script

A throwaway script that applies best-practice scaffolding to a fresh DDEV
Drupal project (`drupal/recommended-project`, i.e. `drupal/core-recommended`).
Run it once, then delete it.

## Usage

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
2. Copies `scaffold/ddev/commands/*` to `.ddev/commands/` (`ddev phpcs`, `phpcbf`, `phpstan`, `phpunit`, `dr`).
3. Composer: Drush, `drupal/ai_best_practices`, `drupal/core-dev` (matching the installed
   `drupal/core-recommended` major version) and `happiness/ai-skills`.
4. Maps the scaffold files into the project root (`gitignore` becomes `.gitignore`) via `extra.drupal-scaffold.file-mapping`
   (`replace` mode, `overwrite: false`) and runs `ddev composer drupal:scaffold`.
5. Sets `config_sync_directory` to `../config/sync` in `settings.php` (when `settings.ddev.php` exists)
   and enables the `settings.local.php` include.
6. Creates `config/sync`, `modules/custom` and `themes/custom`.

Existing files are never overwritten.
