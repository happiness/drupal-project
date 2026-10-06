# Drupal project scaffolding

Creates a new Drupal project from `drupal/recommended-project` (which pulls in
`drupal/core-recommended`) and layers on best-practice defaults.

## Usage

```sh
bin/create-project.sh my-site            # Drupal ^11, with dev tools
bin/create-project.sh my-site --version "^10.4" --git
```

Options: `--version <constraint>`, `--no-dev-tools`, `--git` (init repo + first commit).

## What you get

- Composer project with `drupal/core-recommended`, Drush, sorted packages, optimized autoloader
- Dev tooling: `drupal/core-dev`, Coder (phpcs, via core-dev), phpstan-drupal
- `config/sync` committed outside the web root, wired up in `settings.php`
- `settings.local.php` for local overrides (git-ignored); hash salt from `DRUPAL_HASH_SALT`
- `.gitignore`, `.editorconfig`, `phpcs.xml.dist`, `phpstan.neon`, `scripts/check.sh`
- `web/modules/custom` and `web/themes/custom` for project code

Customize the generated output by editing files under `template/`
(`template/gitignore` is renamed to `.gitignore` on copy).
