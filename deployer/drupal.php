<?php

/**
 * @file
 * Deployer recipe for every Happiness Drupal site. See docs/release.md.
 *
 * Required by the site's deploy.php, which only lists its hosts. The deploy
 * workflow checks this repository out to .drupal-project/ and builds the site
 * first (composer install --no-dev), so the servers need neither access to
 * GitHub nor Composer: the built code is uploaded with rsync.
 *
 * A deploy uploads the build to a new release, links the shared .env.local and
 * files, runs `drush deploy` in the new release (a failure stops before the
 * switch), writes web/ref.txt, switches `current` to it and reloads PHP-FPM.
 */

namespace Deployer;

require 'recipe/common.php';

// The built project to upload: the workflow's checkout.
set('build_path', fn () => getenv('BUILD_PATH') ?: getcwd());

// What is deployed, for the log: the branch or tag the workflow checked out.
set('what', fn () => getenv('DEPLOY_REF') ?: 'the build');

set('keep_releases', 5);

// Kept between releases, in {{deploy_path}}/shared. See docs/settings.md.
set('shared_files', ['.env.local']);
set('shared_dirs', ['web/sites/default/files', 'private']);

// PHP-FPM runs as the deploy user, which owns everything.
set('writable_dirs', []);

// The PHP-FPM service to reload after the switch, e.g. php8.4-fpm. The deploy user
// may run only `sudo systemctl reload <service>` (docs/release.md). Empty: skipped.
set('php_fpm_service', '');

// Never uploaded: version control, local tooling and what lives on the server.
set('upload_excludes', [
  '.git',
  '.github',
  '.ddev',
  '.drupal-project',
  'node_modules',
  '.env',
  '.env.local',
  'web/sites/*/files',
  'web/sites/*/settings.local.php',
  'web/sites/*/settings.ddev.php',
  'private',
]);

// The site reads .env.local, not .env: don't create a .env from .env.example.
task('deploy:env', function () {})->hidden();

desc('Uploads the built project to the new release');
task('deploy:update_code', function () {
  $revision = runLocally('git -C {{build_path}} rev-parse HEAD');
  if (!preg_match('/^[0-9a-f]{40}$/', $revision)) {
    throw new \RuntimeException("Not a commit id: $revision");
  }
  $options = array_map(fn ($exclude) => "--exclude=$exclude", get('upload_excludes'));
  upload('{{build_path}}/', '{{release_path}}/', ['options' => $options]);
  // The commit, for Deployer (REVISION) and for anyone over HTTP (web/ref.txt).
  run("echo $revision > {{release_path}}/REVISION");
  run("echo $revision > {{release_path}}/web/ref.txt");
});

desc('Runs database updates, imports config and rebuilds caches');
task('drupal:deploy', function () {
  // drush.php, not vendor/bin/drush: that is a shell script, which `php` would
  // only print, successfully.
  run('cd {{release_path}} && {{bin/php}} vendor/drush/drush/drush.php deploy --yes');
});

desc('Reloads PHP-FPM, which also clears the opcode cache');
task('php-fpm:reload', function () {
  if (!get('php_fpm_service')) {
    warning('php_fpm_service is not set: PHP-FPM was not reloaded.');
    return;
  }
  run('sudo -n systemctl reload {{php_fpm_service}}');
});

// drush deploy runs in the new release before the switch: if it fails, the site
// keeps running the previous release.
after('deploy:prepare', 'drupal:deploy');
after('deploy:symlink', 'php-fpm:reload');
after('deploy:failed', 'deploy:unlock');
