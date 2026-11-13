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
    # Drupal's installer makes site directories read-only.
    [ "${TESTDIR}" != "" ] && chmod -R u+w "${TESTDIR}" && rm -rf "${TESTDIR}"
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

@test "setup.sh on a new site" {
  set -eu -o pipefail
  echo "# setup.sh with project ${PROJNAME} in $(pwd)" >&3
  git init -q

  run bash "${DIR}/setup.sh"
  assert_success
  refute_output --partial "warn  web/sites/"

  # The scaffolded .gitignore must be in place even though drupal/ai_best_practices
  # creates a .gitignore of its own first, and keep that plugin's rule.
  assert_file_contains .gitignore '^/vendor/$'
  assert_file_contains .gitignore '^/ai_best_practices.yaml$'
  run git check-ignore -q .env.local
  assert_success
  # The code check configuration is committed as *.dist; the files without .dist are
  # local overrides.
  for f in phpcs.xml phpstan.neon phpunit.xml; do
    assert_file_exists "$f.dist"
    run git check-ignore -q "$f.dist"
    assert_failure
    run git check-ignore -q "$f"
    assert_success
  done
  assert_not_exists assets/scaffold
  run git check-ignore -q web/ref.txt
  assert_success
  run git check-ignore -q web/sites/default/settings.local.php
  assert_success
  run git check-ignore -q web/sites/default/settings.php
  assert_failure
  run git check-ignore -q web/sites/default/settings.env.php
  assert_failure
  assert_file_exists .env.example

  # The branch workflow and just.
  assert_file_exists .github/pull_request_template.md
  assert_file_exists .github/workflows/no-dev-merges.yml
  assert_file_exists .github/workflows/qa.yml
  assert_file_exists .github/workflows/reset-dev.yml
  assert_file_contains justfile "^import 'happiness.just'$"
  assert_file_exists happiness.just
  run grep -c '^<!-- happiness:start -->$' AGENTS.md
  assert_output "1"
  assert_file_contains AGENTS.md '^<!-- ai-best-practices:start -->'

  # settings.php is committed, so it must hold no secrets: DDEV provides them in
  # settings.ddev.php, which DDEV keeps out of git.
  run grep -E "^\\\$settings\['hash_salt'\] = '';$" web/sites/default/settings.php
  assert_success
  run git check-ignore -q web/sites/default/settings.ddev.php
  assert_success
  run ddev drush status --field=bootstrap
  assert_output "Successful"

  # Outside DDEV (a server), the secrets come from .env.local.
  run ddev exec env -u IS_DDEV_PROJECT vendor/bin/drush status --field=bootstrap
  assert_output --partial ".env.local is missing or not readable"
  printf 'DRUPAL_ENV=dev\nDB_NAME=db\nDB_USER=db\nDB_PASSWORD=db\nDB_HOST=db\nHASH_SALT=abc123\n' > .env.local
  run ddev exec env -u IS_DDEV_PROJECT vendor/bin/drush status --field=bootstrap
  assert_output "Successful"

  # With a committed fingerprint, a salt that changed, here by a newline as when it
  # was once moved by hand, stops the site.
  local fingerprint
  fingerprint="$(printf 'abc123' | sha256sum | cut -d' ' -f1)"
  perl -pi -e 's/^(\$settings\[\x27hash_salt_sha256\x27\] = \[)$/$1\n  \x27dev\x27 => \x27'"${fingerprint}"'\x27,/' web/sites/default/settings.php
  run grep -c "  'dev' => '${fingerprint}'," web/sites/default/settings.php
  assert_output "1"
  run ddev exec env -u IS_DDEV_PROJECT vendor/bin/drush status --field=bootstrap
  assert_output "Successful"
  printf 'DRUPAL_ENV=dev\nDB_NAME=db\nDB_USER=db\nDB_PASSWORD=db\nDB_HOST=db\nHASH_SALT="abc123\\n"\n' > .env.local
  run ddev exec env -u IS_DDEV_PROJECT vendor/bin/drush status --field=bootstrap
  assert_output --partial "hash_salt doesn't match \$settings['hash_salt_sha256']['dev']"

  # The right salt in another environment, whose entry is missing, stops it too.
  printf 'DRUPAL_ENV=prod\nDB_NAME=db\nDB_USER=db\nDB_PASSWORD=db\nDB_HOST=db\nHASH_SALT=abc123\n' > .env.local
  run ddev exec env -u IS_DDEV_PROJECT vendor/bin/drush status --field=bootstrap
  assert_output --partial "hash_salt doesn't match \$settings['hash_salt_sha256']['prod']"
  rm .env.local

  # The qa check (.github/scripts/qa.sh) with the committed *.dist configuration:
  # it passes without custom code, runs unit tests, and fails on a code style error.
  cp "${DIR}/.github/scripts/qa.sh" qa.sh
  run ddev exec bash qa.sh
  assert_success
  assert_output --partial "No custom code: skipped."
  mkdir -p web/modules/custom/qa_test/tests/src/Unit
  printf 'name: QA test\ndescription: Tests the qa check.\ntype: module\ncore_version_requirement: ^11\n' > web/modules/custom/qa_test/qa_test.info.yml
  cat > web/modules/custom/qa_test/tests/src/Unit/QaTest.php <<'PHP'
<?php

namespace Drupal\Tests\qa_test\Unit;

use Drupal\Tests\UnitTestCase;
use PHPUnit\Framework\Attributes\Group;

/**
 * Tests that the qa check runs unit tests.
 */
#[Group('qa_test')]
class QaTest extends UnitTestCase {

  /**
   * Tests that TRUE is TRUE.
   */
  public function testTruth(): void {
    $this->assertTrue(TRUE);
  }

}
PHP
  run ddev exec bash qa.sh
  assert_success
  assert_output --partial "1 / 1 (100%)"
  printf '<?php\nfunction qa_test_help( $a ){ return 1; }\n' > web/modules/custom/qa_test/qa_test.module
  run ddev exec bash qa.sh
  assert_failure
  assert_output --partial "One or more code checks failed"
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
