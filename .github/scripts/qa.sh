#!/usr/bin/env bash
#
# The code checks a pull request must pass, on the site's custom code: PHP_CodeSniffer,
# PHPStan and the unit and kernel tests. Run by .github/workflows/qa.yml from the
# site's root, after composer install. Uses the site's committed *.dist configuration.
#
# A check with nothing to check is skipped, so a new site without custom code passes.
# Kernel tests use SQLite unless SIMPLETEST_DB says otherwise.
set -euo pipefail

custom=()
for d in web/modules/custom web/themes/custom; do [[ -d "$d" ]] && custom+=("$d"); done
php_files=""
if [[ ${#custom[@]} -gt 0 ]]; then
  php_files="$(find "${custom[@]}" -type f \( -name '*.php' -o -name '*.module' -o -name '*.inc' \
    -o -name '*.install' -o -name '*.theme' -o -name '*.profile' \) -print -quit)"
fi
status=0

echo "::group::PHP_CodeSniffer"
if [[ -n "$php_files" ]] || [[ ${#custom[@]} -gt 0 && -n "$(find "${custom[@]}" -name '*.yml' -print -quit)" ]]; then
  vendor/bin/phpcs --standard=phpcs.xml.dist || status=1
else
  echo "No custom code: skipped."
fi
echo "::endgroup::"

echo "::group::PHPStan"
if [[ -n "$php_files" ]]; then
  vendor/bin/phpstan analyse --configuration=phpstan.neon.dist --no-progress || status=1
else
  echo "No custom PHP: skipped."
fi
echo "::endgroup::"

echo "::group::PHPUnit (unit and kernel)"
if [[ -n "$(find web/modules/custom -type d \( -path '*/tests/src/Unit' -o -path '*/tests/src/Kernel' \) -print -quit 2>/dev/null)" ]]; then
  (cd web && SIMPLETEST_DB="${SIMPLETEST_DB:-sqlite://localhost//tmp/qa.sqlite}" \
    ../vendor/bin/phpunit --configuration ../phpunit.xml.dist --testsuite unit,kernel) || status=1
else
  echo "No unit or kernel tests: skipped."
fi
echo "::endgroup::"

if [[ $status -ne 0 ]]; then
  echo "::error::One or more code checks failed. Run them locally with: just check"
fi
exit $status
