#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the repository root:
#   bats ./tests/test.bats
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-drupal-project"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  export CI=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site --project-type=drupal11 --docroot=web
  assert_success
  run ddev start -y
  assert_success

  # A small Drupal site with real-looking personal data: an admin, two users
  # whose names collide with the sanitized ones (uid 2 "user3", uid 3 "user2"),
  # an anonymous comment, a log entry and a flood entry.
  run ddev composer create-project drupal/recommended-project
  assert_success
  run ddev composer require drush/drush -n
  assert_success
  run ddev drush site:install minimal -y --account-name=jane.admin --account-mail=jane@example.com --account-pass=secret
  assert_success
  run ddev drush user:create user3 --mail=john@example.com --password=secret
  assert_success
  run ddev drush user:create user2 --mail=mary@example.com --password=secret
  assert_success
  run ddev drush pm:install comment -y
  assert_success
  cp "${DIR}/tests/testdata/comments.php" "${TESTDIR}/comments.php"
  run ddev drush php:script /var/www/html/comments.php
  assert_success
  run ddev drush php:eval "\Drupal::logger('test')->notice('Login from john@example.com'); \Drupal::flood()->register('test', 3600, '203.0.113.7');"
  assert_success
  run ddev export-db --file="${TESTDIR}/db.sql.gz"
  assert_success
}

# Installs the sanitize hook the way setup.sh does on a new site: copies the
# scaffold files and adds fail_on_hook_fail, with DDEV already running and no
# `ddev restart`.
install_hook() {
  cp "${DIR}/scaffold/ddev/config.sanitize.yaml" .ddev/
  cp -R "${DIR}/scaffold/ddev/sanitize" .ddev/
  echo "fail_on_hook_fail: true" >> .ddev/config.yaml
}

# Imports the database again, which runs the post-import-db hook.
import_and_check() {
  run ddev import-db --file="${TESTDIR}/db.sql.gz"
  assert_success

  run ddev drush sql:query "SELECT CONCAT(uid, ':', name, ':', mail) FROM users_field_data WHERE uid > 0 ORDER BY uid"
  assert_success
  assert_line "1:admin:user+1@localhost"
  assert_line "2:user2:user+2@localhost"
  assert_line "3:user3:user+3@localhost"
  refute_output --partial "example.com"

  run ddev drush sql:query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0 AND init NOT LIKE '%@localhost'"
  assert_success
  assert_output "0"

  run ddev drush php:eval "\$account = \Drupal\user\Entity\User::load(2); echo \Drupal::service('password')->check('password', \$account->getPassword()) ? 'password ok' : 'password not reset';"
  assert_success
  assert_output "password ok"

  run ddev drush sql:query "SELECT CONCAT(name, ':', COALESCE(mail, ''), ':', hostname) FROM comment_field_data"
  assert_success
  assert_output --partial ":127.0.0.1"
  refute_output --partial "Visitor Jane"
  refute_output --partial "example.com"
  refute_output --partial "203.0.113.9"

  run ddev drush sql:query "SELECT last_comment_name FROM comment_entity_statistics"
  assert_success
  assert_output "Anonymous"

  # The hook's own drush commands may log again, so check the test entries.
  run ddev drush sql:query "SELECT (SELECT COUNT(*) FROM watchdog WHERE variables LIKE '%example.com%' OR message LIKE '%example.com%') + (SELECT COUNT(*) FROM flood)"
  assert_success
  assert_output "0"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${TESTDIR}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "sanitize hook" {
  set -eu -o pipefail
  echo "# sanitize hook with project ${PROJNAME} in $(pwd)" >&3
  install_hook
  import_and_check

  # --skip-hooks imports the database as is.
  run ddev import-db --skip-hooks --file="${TESTDIR}/db.sql.gz"
  assert_success
  run ddev drush sql:query "SELECT mail FROM users_field_data WHERE uid = 2"
  assert_output "john@example.com"

  # If email sanitizing doesn't happen, the final check must say so, and
  # fail_on_hook_fail must make the import fail.
  sed -i.bak 's/--sanitize-email=user+%uid@localhost/--sanitize-email=no/' .ddev/sanitize/sanitize.sh
  rm .ddev/sanitize/sanitize.sh.bak
  run ddev import-db --file="${TESTDIR}/db.sql.gz"
  assert_failure
  assert_output --partial "DATABASE NOT SANITIZED: 3 user account(s)"
}

@test "multisite" {
  set -eu -o pipefail
  echo "# multisite with project ${PROJNAME} in $(pwd)" >&3
  install_hook

  # site2 has its own database with real-looking data, and a table prefix. DDEV's db user can't
  # create databases, so create it as root.
  run ddev mysql -uroot -proot -e "CREATE DATABASE site2; GRANT ALL ON site2.* TO 'db'@'%';"
  assert_success
  run ddev drush site:install minimal -y --sites-subdir=site2 --db-url=mysql://db:db@db/site2 --db-prefix=s2_ --account-name=bob.admin --account-mail=bob@example.com --account-pass=secret
  assert_success
  run ddev drush --uri=site2 user:create carol --mail=carol@example.com --password=secret
  assert_success
  run ddev export-db --database=site2 --file="${TESTDIR}/site2.sql.gz"
  assert_success
  # site3's database hasn't been imported yet.
  mkdir -p web/sites/site3
  printf '<?php\n$databases["default"]["default"] = ["database" => "site3", "username" => "db", "password" => "db", "host" => "db", "driver" => "mysql"];\n' > web/sites/site3/settings.php

  # Importing site2 sanitizes every site with a database and skips site3.
  run ddev import-db --database=site2 --file="${TESTDIR}/site2.sql.gz"
  assert_success
  assert_output --partial "Sanitizing site site2 (database site2)"
  assert_output --partial "Skipping site site3"
  run ddev drush --uri=site2 sql:query "SELECT CONCAT(uid, ':', name, ':', mail) FROM s2_users_field_data WHERE uid > 0 ORDER BY uid"
  assert_success
  assert_line "1:admin:user+1@localhost"
  assert_line "2:user2:user+2@localhost"
  refute_output --partial "example.com"
  run ddev drush sql:query "SELECT COUNT(*) FROM users_field_data WHERE mail LIKE '%example.com'"
  assert_output "0"

  # A database no site uses can't be sanitized, so the import must fail.
  run ddev import-db --database=orphan --file="${TESTDIR}/db.sql.gz"
  assert_failure
  assert_output --partial "DATABASE NOT SANITIZED: orphan is not used by any site"
}
