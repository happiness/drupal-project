#!/usr/bin/env bash
#
# Throwaway Drupal best-practice setup for a fresh DDEV Drupal project.
#
# Run from the project root (where .ddev/ and composer.json live), then delete it:
#   curl -fsSL https://raw.githubusercontent.com/happiness/drupal-project/main/setup.sh | bash
#   (or: bash /path/to/this/repo/setup.sh, which uses the local scaffold/ directory)
#
# Prerequisite:
#   mkdir my-site && cd my-site
#   ddev config --project-type=drupal11 --docroot=web
# If there is no composer.json yet, the script runs
# `ddev composer create-project drupal/recommended-project`; if there is one but no
# vendor/ directory, it runs `ddev composer install`.
#
# Options: --install   run drush site:install afterwards
set -euo pipefail

SCAFFOLD_FILES=(phpcs.xml phpstan.neon phpunit.xml gitignore)
DDEV_COMMANDS=(web/dr web/phpcbf web/phpcs web/phpstan web/phpunit)
SCAFFOLD_URL="${SCAFFOLD_URL:-https://raw.githubusercontent.com/happiness/drupal-project/main/scaffold}"
# Local scaffold/ next to the script, if run from a clone (empty when piped from curl).
SCAFFOLD_SRC=""
if [[ -n "${BASH_SOURCE[0]:-}" && -d "$(dirname "${BASH_SOURCE[0]}")/scaffold" ]]; then
  SCAFFOLD_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scaffold"
fi

INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v ddev >/dev/null || { echo "ddev is required" >&2; exit 1; }
[[ -d .ddev ]] || { echo "No .ddev/ here. Run 'ddev config --project-type=drupal11 --docroot=web' first." >&2; exit 1; }

# Docroot as configured in DDEV (default: web).
DOCROOT="$(sed -n 's/^docroot: *//p' .ddev/config.yaml | tr -d '"' | head -1)"
DOCROOT="${DOCROOT:-web}"

echo "==> Starting DDEV"
ddev start

if [[ ! -f composer.json ]]; then
  echo "==> Creating Drupal project (drupal/recommended-project)"
  ddev composer create-project drupal/recommended-project
elif [[ ! -d vendor ]]; then
  echo "==> Installing Composer dependencies"
  ddev composer install
fi
grep -q '"drupal/core-recommended"' composer.json \
  || { echo "composer.json does not require drupal/core-recommended" >&2; exit 1; }

echo "==> Scaffold files"
mkdir -p assets/scaffold
for f in "${SCAFFOLD_FILES[@]}"; do
  [[ -e "assets/scaffold/$f" ]] && continue
  if [[ -n "$SCAFFOLD_SRC" ]]; then
    cp "$SCAFFOLD_SRC/$f" "assets/scaffold/$f"
  else
    curl -fsSL "$SCAFFOLD_URL/$f" -o "assets/scaffold/$f"
  fi
done
PROJECT_URL="$(ddev exec 'echo -n "$DDEV_PRIMARY_URL"' | tr -d '\r')"
sed -i "s|%DDEV_PROJECT_URL%|$PROJECT_URL|g" assets/scaffold/phpunit.xml
echo "  assets/scaffold ready (DDEV URL: $PROJECT_URL)"

echo "==> DDEV commands"
for c in "${DDEV_COMMANDS[@]}"; do
  dest=".ddev/commands/$c"
  [[ -e "$dest" ]] && { echo "  skip  $dest (exists)"; continue; }
  mkdir -p "$(dirname "$dest")"
  if [[ -n "$SCAFFOLD_SRC" ]]; then
    cp "$SCAFFOLD_SRC/ddev/commands/$c" "$dest"
  else
    curl -fsSL "$SCAFFOLD_URL/ddev/commands/$c" -o "$dest"
  fi
  chmod +x "$dest"
  echo "  write $dest"
done

echo "==> Composer"
ddev composer config sort-packages true
ddev composer config optimize-autoloader true
ddev composer require drush/drush
ddev composer config allow-plugins.drupal/ai_best_practices true
ddev composer require --dev drupal/ai_best_practices:@dev
# Match core-dev to the installed drupal/core-recommended major version.
CORE="$(ddev composer show drupal/core-recommended | sed -n 's/^versions *: *\* *\([0-9]*\)\..*/\1/p' | head -1)"
[[ -n "$CORE" ]] || { echo "Could not detect drupal/core-recommended version" >&2; exit 1; }
ddev composer require "drupal/core-dev:^$CORE" --dev -W
ddev composer config repositories.happiness-ai-skills vcs git@github.com:happiness/ai-skills.git
ddev composer require happiness/ai-skills:^1.0

echo "==> Mapping scaffold files in composer.json"
for f in "${SCAFFOLD_FILES[@]}"; do
  dest="$f"; [[ "$f" == gitignore ]] && dest=.gitignore # stored without the dot in scaffold/
  ddev composer config --json --merge extra.drupal-scaffold.file-mapping \
    "{\"[project-root]/$dest\": {\"path\": \"assets/scaffold/$f\", \"mode\": \"replace\", \"overwrite\": false}}"
done
ddev composer drupal:scaffold

echo "==> Files"
mkdir -p config/sync "$DOCROOT/modules/custom" "$DOCROOT/themes/custom"
touch config/sync/.gitkeep "$DOCROOT/modules/custom/.gitkeep" "$DOCROOT/themes/custom/.gitkeep"

# Config sync lives outside the docroot and is committed. DDEV's generated
# settings.php includes settings.ddev.php, which only sets a default if unset.
SETTINGS="$DOCROOT/sites/default/settings.php"
if [[ -f "$DOCROOT/sites/default/settings.ddev.php" && -f "$SETTINGS" ]] && ! grep -qE "^\\\$settings\['config_sync_directory'\]" "$SETTINGS"; then
  chmod u+w "$SETTINGS" "$(dirname "$SETTINGS")"
  cat >> "$SETTINGS" <<'X'

$settings['config_sync_directory'] = '../config/sync';
X
  # Enable the (commented-out) settings.local.php include at the end of settings.php.
  sed -i '/^# if (file_exists(\$app_root.*settings\.local\.php/,/^# }/s/^# \{0,1\}//' "$SETTINGS"
  echo "  patch $SETTINGS"
fi

if [[ $INSTALL -eq 1 ]]; then
  echo "==> Installing Drupal"
  ddev drush site:install standard -y
  ddev drush config:export -y
fi

cat <<MSG

Done. You can delete this script now.
  ddev launch          open the site
  ddev drush uli       one-time login link
  ddev phpcs | phpcbf | phpstan | phpunit | dr
MSG
