#!/usr/bin/env bash
#
# Sanitizes every site of the project after `ddev import-db`. Runs in the web
# container. DDEV doesn't tell hooks which database was imported (`--database`),
# so each site with a database is sanitized, which is safe to repeat.
set -euo pipefail

cd /var/www/html

# Databases that hold a Drupal site, i.e. have a users table, with or without
# a table prefix.
user_databases="$(mysql -N -e "SELECT DISTINCT table_schema FROM information_schema.tables WHERE table_name REGEXP 'users_field_data\$' ORDER BY table_schema")"

sanitized=()
for settings in "${DDEV_DOCROOT:-web}"/sites/*/settings.php; do
  site="$(basename "$(dirname "$settings")")"
  db="$(drush --uri="$site" status --field=db-name 2>/dev/null || true)"
  # Skip sites without a database config, or whose database hasn't been imported.
  if [[ -z "$db" ]] || ! grep -qxF "$db" <<< "$user_databases"; then
    echo "Skipping site $site (no database with users)"
    continue
  fi
  echo "Sanitizing site $site (database $db)"
  drush --uri="$site" sql:sanitize -y --sanitize-email=user+%uid@localhost --sanitize-password=password
  drush --uri="$site" php:script /var/www/html/.ddev/sanitize/sanitize.php
  drush --uri="$site" cr
  sanitized+=("$db")
done

# A database no site points to (e.g. `ddev import-db --database=<typo>`) was
# not sanitized above. Fail loudly instead of leaving real data behind.
leftover=()
while read -r db; do
  if [[ -n "$db" && " ${sanitized[*]:-} " != *" $db "* ]]; then leftover+=("$db"); fi
done <<< "$user_databases"
if (( ${#leftover[@]} )); then
  for db in "${leftover[@]}"; do
    echo "DATABASE NOT SANITIZED: $db is not used by any site in ${DDEV_DOCROOT:-web}/sites, so it may hold real data." >&2
    echo "  If you don't need it, drop it: ddev mysql -uroot -proot -e 'DROP DATABASE \`$db\`'" >&2
  done
  if (( ${#sanitized[@]} )); then
    echo "The databases of the sites (${sanitized[*]}) were sanitized." >&2
  fi
  exit 1
fi
