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
# Paths relative to .ddev/ (and to scaffold/ddev/).
DDEV_FILES=(
  commands/web/dr commands/web/phpcbf commands/web/phpcs commands/web/phpstan commands/web/phpunit
  config.sanitize.yaml sanitize/sanitize.php
)
SCAFFOLD_URL="${SCAFFOLD_URL:-https://raw.githubusercontent.com/happiness/drupal-project/main/scaffold}"
# Local scaffold/ next to the script, if run from a clone (empty when piped from curl).
SCAFFOLD_SRC=""
if [[ -n "${BASH_SOURCE[0]:-}" && -d "$(dirname "${BASH_SOURCE[0]}")/scaffold" ]]; then
  SCAFFOLD_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scaffold"
fi

# Copy scaffold/<path> ($1) to $2, from the clone or from SCAFFOLD_URL. Writes to a
# temporary file first: existing files are skipped on later runs, so an interrupted
# download must not leave a truncated file at $2.
fetch() {
  if [[ -n "$SCAFFOLD_SRC" ]]; then
    cp "$SCAFFOLD_SRC/$1" "$2.tmp"
  else
    curl -fsSL "$SCAFFOLD_URL/$1" -o "$2.tmp"
  fi || { rm -f "$2.tmp"; return 1; }
  mv "$2.tmp" "$2"
}

main() {
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

  if ddev describe -j 2>/dev/null | grep -q '"status":"running"'; then
    echo "==> DDEV is already running"
  else
    echo "==> Starting DDEV"
    ddev start
  fi

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
    fetch "$f" "assets/scaffold/$f"
  done
  PROJECT_URL="$(ddev exec 'echo -n "$DDEV_PRIMARY_URL"' | tr -d '\r')"
  # `-i.bak` (and removing the backup) is the one form of in-place sed that works on both GNU and BSD/macOS.
  sed -i.bak "s|%DDEV_PROJECT_URL%|$PROJECT_URL|g" assets/scaffold/phpunit.xml
  rm -f assets/scaffold/phpunit.xml.bak
  echo "  assets/scaffold ready (DDEV URL: $PROJECT_URL)"

  echo "==> DDEV commands and sanitize hook"
  for f in "${DDEV_FILES[@]}"; do
    dest=".ddev/$f"
    [[ -e "$dest" ]] && { echo "  skip  $dest (exists)"; continue; }
    mkdir -p "$(dirname "$dest")"
    fetch "ddev/$f" "$dest"
    [[ "$f" == commands/* ]] && chmod +x "$dest"
    echo "  write $dest"
  done
  # DDEV only warns when a hook fails, so a failed sanitize would leave real
  # data in the database without failing `ddev import-db`. The setting applies
  # to all of the project's hooks, so only add it when there are no others that
  # could start failing `ddev start` or `ddev import-db`.
  FAIL_ON_HOOK_FAIL="$(sed -n 's/^fail_on_hook_fail: *//p' .ddev/config.yaml | head -1)"
  OTHER_HOOKS="$(grep -l '^hooks:' .ddev/config.yaml .ddev/config.*.yaml 2>/dev/null \
    | grep -vx '.ddev/config.sanitize.yaml' | tr '\n' ' ' || true)"
  if [[ -z "$FAIL_ON_HOOK_FAIL" && -z "$OTHER_HOOKS" ]]; then
    [[ -n "$(tail -c1 .ddev/config.yaml)" ]] && echo >> .ddev/config.yaml
    echo "fail_on_hook_fail: true" >> .ddev/config.yaml
    echo "  add   fail_on_hook_fail: true to .ddev/config.yaml"
  elif [[ -z "$FAIL_ON_HOOK_FAIL" ]]; then
    echo "  warn  Not adding fail_on_hook_fail: true, which would also apply to the hooks in" \
      "${OTHER_HOOKS% }. A failed sanitize will not fail 'ddev import-db'. Check its output for DATABASE NOT SANITIZED."
  elif [[ "$FAIL_ON_HOOK_FAIL" != true ]]; then
    echo "  warn  .ddev/config.yaml has fail_on_hook_fail: $FAIL_ON_HOOK_FAIL, so a failed sanitize" \
      "will not fail 'ddev import-db'. Check its output for DATABASE NOT SANITIZED."
  fi

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

  # Sync skills (ai_best_practices + happiness/ai-skills) to .agents/skills, then
  # expose them to Claude Code.
  ddev composer drupal-ai skills-sync
  mkdir -p .claude
  if [[ -e .claude/skills || -L .claude/skills ]]; then
    echo "  skip  .claude/skills (exists)"
  else
    ln -s ../.agents/skills .claude/skills
    echo "  link  .claude/skills -> ../.agents/skills"
  fi

  # The scaffolded .gitignore is never overwritten. If the project already has one,
  # append ignore rules for the scaffolded testing config instead. The leading `/`
  # anchors each rule to the project root so nested files of the same name stay tracked.
  # A file the project already commits is its own config (drupal:scaffold won't
  # overwrite it), so it is not ignored.
  if [[ -f .gitignore ]]; then
    echo "==> Appending testing config to existing .gitignore"
    [[ -n "$(tail -c1 .gitignore)" ]] && echo >> .gitignore
    for p in /phpcs.xml /phpstan.neon /phpunit.xml; do
      if git ls-files --error-unmatch -- "${p#/}" >/dev/null 2>&1; then
        echo "  skip  $p (tracked by git)"
        continue
      fi
      grep -qxF "$p" .gitignore || { echo "$p" >> .gitignore; echo "  add   $p"; }
    done
  fi

  echo "==> Mapping scaffold files in composer.json"
  for f in "${SCAFFOLD_FILES[@]}"; do
    dest="$f"; [[ "$f" == gitignore ]] && dest=.gitignore # stored without the dot in scaffold/
    ddev composer config --json --merge extra.drupal-scaffold.file-mapping \
      "{\"[project-root]/$dest\": {\"path\": \"assets/scaffold/$f\", \"mode\": \"replace\", \"overwrite\": false}}"
  done
  ddev composer drupal:scaffold

  echo "==> Files"
  # .gitkeep only where git would otherwise drop the empty directory.
  for d in config/sync "$DOCROOT/modules/custom" "$DOCROOT/themes/custom"; do
    mkdir -p "$d"
    if [[ -z "$(ls -A "$d")" ]]; then touch "$d/.gitkeep"; fi
  done

  # Config sync lives outside the docroot and is committed. DDEV's generated
  # settings.php includes settings.ddev.php, which only sets a default if unset.
  SETTINGS="$DOCROOT/sites/default/settings.php"
  if [[ -f "$DOCROOT/sites/default/settings.ddev.php" && -f "$SETTINGS" ]] && ! grep -qE "^\\\$settings\['config_sync_directory'\]" "$SETTINGS"; then
    chmod u+w "$SETTINGS" "$(dirname "$SETTINGS")"
    # Insert it above the settings.local.php include and the comment block that
    # documents it, so settings.local.php can still override it. Without an
    # include, append it.
    awk -v sync="\$settings['config_sync_directory'] = '../config/sync';" '
      { l[NR] = $0 }
      END {
        at = NR + 1
        for (i = 1; i <= NR; i++) {
          if (l[i] ~ /^(# ?)?if \(file_exists\(\$app_root.*settings\.local\.php/) { at = i; break }
        }
        for (i = at - 1; at <= NR && i > 0 && l[i] ~ /^(#.*|[[:space:]]*\*.*|\/\*\*.*|[[:space:]]*)$/; i--) {
          if (l[i] ~ /^\/\*\*/) { at = i; break }
        }
        for (i = 1; i <= NR; i++) { if (i == at) print sync "\n"; print l[i] }
        if (at > NR) print "\n" sync
      }' "$SETTINGS" > "$SETTINGS.tmp"
    # Write back in place to keep the file's permissions.
    cat "$SETTINGS.tmp" > "$SETTINGS"
    rm -f "$SETTINGS.tmp"
    # Enable the (commented-out) settings.local.php include at the end of settings.php,
    # unless the project already includes it, which would include it twice.
    if ! grep -qE "^[[:space:]]*include .*settings\.local\.php" "$SETTINGS"; then
      sed -i.bak '/^# if (file_exists(\$app_root.*settings\.local\.php/,/^# }/s/^# \{0,1\}//' "$SETTINGS"
      rm -f "$SETTINGS.bak"
    fi
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
  ddev import-db       imports are sanitized (every password is "password")
MSG
}

# Everything is wrapped in main() and called last so that bash has read the whole
# script before running it; otherwise `curl | bash` lets ddev swallow the rest of
# the script from stdin.
main "$@"
