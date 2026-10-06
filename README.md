# Drupal DDEV setup script

A throwaway script that applies best-practice scaffolding to a fresh DDEV
Drupal project (`drupal/recommended-project`, i.e. `drupal/core-recommended`).
Run it once, then delete it.

## Usage

```sh
mkdir my-site && cd my-site
ddev config --project-type=drupal11 --docroot=web
ddev composer create-project drupal/recommended-project

curl -fsSL https://raw.githubusercontent.com/<you>/drupal-project/main/setup.sh | bash
# or: bash /path/to/setup.sh [--no-dev-tools] [--install]
rm -f setup.sh
```

`--install` also runs `ddev drush site:install standard` and exports config.
`--no-dev-tools` skips phpcs/phpstan.

## What it does

- Starts DDEV, adds Drush, enables sorted packages and optimized autoloader
- Dev tooling: `drupal/core-dev` (Coder/phpcs), phpstan-drupal, `phpcs.xml.dist`, `phpstan.neon`
- `ddev check` command running phpcs + phpstan on custom code
- `config/sync` outside the docroot, wired up in `settings.php`; `settings.local.php` include enabled and git-ignored
- `.editorconfig`, `.gitignore` additions, `modules/custom` and `themes/custom`

Existing files are never overwritten.
