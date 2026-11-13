<?php

/**
 * @file
 * This site's servers. Fill in every CHANGE-ME.
 *
 * The deploy steps come from happiness/drupal-project (deployer/drupal.php),
 * which the deploy workflows check out to .drupal-project/. Deploys run in GitHub
 * Actions only: see docs/release.md in happiness/drupal-project.
 */

namespace Deployer;

require __DIR__ . '/.drupal-project/deployer/drupal.php';

// DEV runs the dev branch.
host('dev')
  // The server's IP address: a domain behind the Cloudflare proxy doesn't reach SSH.
  ->setHostname('CHANGE-ME')
  ->setRemoteUser('deploy')
  // The web server's document root is {{deploy_path}}/current/web.
  ->setDeployPath('CHANGE-ME')
  // The PHP-FPM service to reload, e.g. php8.4-fpm.
  ->set('php_fpm_service', 'CHANGE-ME');

// PROD runs release tags (YYYY-MM-DD-N).
host('prod')
  ->setHostname('CHANGE-ME')
  ->setRemoteUser('deploy')
  ->setDeployPath('CHANGE-ME')
  ->set('php_fpm_service', 'CHANGE-ME');
