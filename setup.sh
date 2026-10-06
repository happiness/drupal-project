#!/usr/bin/env bash
#
# Throwaway Drupal best-practice setup for a fresh DDEV Drupal project.
#
# Run from the project root (where .ddev/ and composer.json live), then delete it:
#   curl -fsSL <url>/setup.sh | bash     # or: bash setup.sh
#
# Prerequisite (standard DDEV quickstart):
#   mkdir my-site && cd my-site
#   ddev config --project-type=drupal11 --docroot=web
#   ddev composer create-project drupal/recommended-project
#
# Options: --no-dev-tools   skip phpcs/phpstan tooling
#          --install        run drush site:install afterwards
set -euo pipefail

DEV_TOOLS=1
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --no-dev-tools) DEV_TOOLS=0 ;;
    --install) INSTALL=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v ddev >/dev/null || { echo "ddev is required" >&2; exit 1; }
[[ -d .ddev ]] || { echo "No .ddev/ here. Run 'ddev config --project-type=drupal11 --docroot=web' first." >&2; exit 1; }
grep -q '"drupal/core-recommended"' composer.json 2>/dev/null \
  || { echo "No Drupal project found. Run 'ddev composer create-project drupal/recommended-project' first." >&2; exit 1; }

# Docroot as configured in DDEV (default: web).
DOCROOT="$(sed -n 's/^docroot: *//p' .ddev/config.yaml | tr -d '"' | head -1)"
DOCROOT="${DOCROOT:-web}"

write() { # write <path> ; content on stdin; never overwrites existing files
  if [[ -e "$1" ]]; then echo "  skip  $1 (exists)"; cat >/dev/null; return; fi
  mkdir -p "$(dirname "$1")"; cat > "$1"; echo "  write $1"
}

echo "==> Starting DDEV"
ddev start

echo "==> Composer"
ddev composer config sort-packages true
ddev composer config optimize-autoloader true
ddev composer require drush/drush
if [[ $DEV_TOOLS -eq 1 ]]; then
  ddev composer config allow-plugins.phpstan/extension-installer true
  ddev composer config allow-plugins.dealerdirect/phpcodesniffer-composer-installer true
  # Match core-dev to the installed core version, allowing dependency updates.
  CORE="$(ddev composer show drupal/core-recommended | sed -n 's/^versions *: *\* *\([0-9]*\)\..*/\1/p' | head -1)"
  CORE="${CORE:-11}"
  ddev composer require --dev -W "drupal/core-dev:^$CORE" mglaman/phpstan-drupal \
    phpstan/extension-installer phpstan/phpstan-deprecation-rules
fi

echo "==> Files"
write .editorconfig <<'X'
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.md]
trim_trailing_whitespace = false
X

if [[ -f .gitignore ]]; then
  for p in "/$DOCROOT/sites/*/settings.local.php" "/$DOCROOT/sites/*/services.local.yml" ".env" "*.sql.gz"; do
    grep -qxF "$p" .gitignore || echo "$p" >> .gitignore
  done
else
  write .gitignore <<X
/vendor/
/$DOCROOT/core/
/$DOCROOT/modules/contrib/
/$DOCROOT/themes/contrib/
/$DOCROOT/profiles/contrib/
/$DOCROOT/libraries/
/$DOCROOT/sites/*/files/
/$DOCROOT/sites/*/settings.local.php
/$DOCROOT/sites/*/services.local.yml
.env
.idea/
*.sql.gz
X
fi

mkdir -p config/sync "$DOCROOT/modules/custom" "$DOCROOT/themes/custom"
touch config/sync/.gitkeep "$DOCROOT/modules/custom/.gitkeep" "$DOCROOT/themes/custom/.gitkeep"

if [[ $DEV_TOOLS -eq 1 ]]; then
  write phpcs.xml.dist <<X
<?xml version="1.0"?>
<ruleset name="project">
  <file>$DOCROOT/modules/custom</file>
  <file>$DOCROOT/themes/custom</file>
  <arg name="extensions" value="php,module,inc,install,test,profile,theme,css,info,txt,yml"/>
  <rule ref="Drupal"/>
  <rule ref="DrupalPractice"/>
</ruleset>
X
  write phpstan.neon <<X
parameters:
  level: 5
  paths:
    - $DOCROOT/modules/custom
    - $DOCROOT/themes/custom
  drupal:
    drupal_root: $DOCROOT
X
  # Custom DDEV command: `ddev check` runs phpcs + phpstan in the web container.
  write .ddev/commands/web/check <<X
#!/usr/bin/env bash
## Description: Run phpcs and phpstan on custom code
## Usage: check
set -e
vendor/bin/phpcs
if [ -n "\$(find $DOCROOT/modules/custom $DOCROOT/themes/custom -name '*.php' -o -name '*.module' | head -1)" ]; then
  vendor/bin/phpstan analyse --memory-limit=1G
fi
X
  chmod +x .ddev/commands/web/check
fi

# Config sync lives outside the docroot and is committed. DDEV's generated
# settings.php includes settings.ddev.php, which only sets a default if unset.
SETTINGS="$DOCROOT/sites/default/settings.php"
if [[ -f "$SETTINGS" ]] && ! grep -qE "^\\\$settings\['config_sync_directory'\]" "$SETTINGS"; then
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
  ddev check           phpcs + phpstan on custom code
MSG
