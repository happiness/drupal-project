#!/usr/bin/env bash
#
# Create a new Drupal project based on drupal/recommended-project
# (which requires drupal/core-recommended) and apply best-practice scaffolding.
#
# Usage: bin/create-project.sh <target-dir> [--version "^11"] [--no-dev-tools] [--git]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/template"

TARGET=""
VERSION="^11"
DEV_TOOLS=1
GIT_INIT=0

usage() { sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    --no-dev-tools) DEV_TOOLS=0; shift ;;
    --git) GIT_INIT=1; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *) TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || usage 1
command -v composer >/dev/null || { echo "composer is required" >&2; exit 1; }
[[ ! -e "$TARGET" ]] || { echo "$TARGET already exists" >&2; exit 1; }

echo "==> Creating Drupal project in $TARGET (drupal/recommended-project:$VERSION)"
composer create-project "drupal/recommended-project:$VERSION" "$TARGET" --no-interaction --no-install

cd "$TARGET"

echo "==> Applying composer best practices"
composer config sort-packages true
composer config optimize-autoloader true
composer config allow-plugins.dealerdirect/phpcodesniffer-composer-installer true
composer config allow-plugins.phpstan/extension-installer true
composer require --no-update drush/drush

if [[ $DEV_TOOLS -eq 1 ]]; then
  echo "==> Adding dev tooling"
  composer require --dev --no-update \
    drupal/core-dev \
    mglaman/phpstan-drupal \
    phpstan/extension-installer \
    phpstan/phpstan-deprecation-rules
fi

echo "==> Installing dependencies"
composer update --no-interaction

echo "==> Copying scaffolding"
cp -a "$TEMPLATE/." .
mv gitignore .gitignore 2>/dev/null || true
chmod +x scripts/*.sh

# Point Drupal at the committed config sync directory.
SETTINGS_SNIPPET='
$settings["config_sync_directory"] = "../config/sync";
if ($salt = getenv("DRUPAL_HASH_SALT")) {
  $settings["hash_salt"] = $salt;
}
if (file_exists($app_root . "/" . $site_path . "/settings.local.php")) {
  include $app_root . "/" . $site_path . "/settings.local.php";
}
'
mkdir -p web/sites/default
cp web/core/assets/scaffold/files/default.settings.php web/sites/default/settings.php
printf '%s\n' "$SETTINGS_SNIPPET" >> web/sites/default/settings.php
cp web/sites/example.settings.local.php web/sites/default/settings.local.php 2>/dev/null || true

if [[ $GIT_INIT -eq 1 ]]; then
  git init -q && git add -A && git commit -q -m "Initial Drupal project"
fi

cat <<MSG

Done. Next steps:
  cd $TARGET
  vendor/bin/drush site:install standard --db-url=sqlite://sites/default/files/.ht.sqlite -y
  vendor/bin/drush runserver        # or point your web server at ./web
  scripts/check.sh                  # phpcs + phpstan
MSG
