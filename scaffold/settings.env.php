<?php

/**
 * @file
 * Reads the site's secrets from .env.local.
 *
 * Included from settings.php, above the site's own settings, which can map
 * further keys from $env_local. The hash_salt check is the last thing in
 * settings.php. See docs/settings.md in happiness/drupal-project.
 *
 * On a server, the secrets come from .env.local in the project root: values
 * only, no logic. In DDEV, settings.ddev.php provides the database and
 * hash_salt, and .env.local is optional.
 *
 * Outside DDEV the site refuses to start when .env.local is missing or lacks a
 * required key, or when a settings.local.php exists: that file is for local
 * development only.
 */

use Dotenv\Dotenv;

$happiness_ddev = getenv('IS_DDEV_PROJECT') === 'true';
$happiness_env_file = dirname($app_root) . '/.env.local';

// Keys from .env.local. Never copied into the process environment, so they
// don't show up in phpinfo().
$env_local = [];
if (is_readable($happiness_env_file)) {
  $env_local = Dotenv::parse(file_get_contents($happiness_env_file));
}
elseif (!$happiness_ddev) {
  throw new \RuntimeException("$happiness_env_file is missing or not readable. See docs/settings.md.");
}

if (!$happiness_ddev) {
  if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
    throw new \RuntimeException("$site_path/settings.local.php is for local development only. Secrets go in .env.local, see docs/settings.md.");
  }

  foreach (['DRUPAL_ENV', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'HASH_SALT'] as $happiness_key) {
    if (!isset($env_local[$happiness_key]) || $env_local[$happiness_key] === '') {
      throw new \RuntimeException("$happiness_key is missing in .env.local. See docs/settings.md.");
    }
  }

  $databases['default']['default'] = [
    'database' => $env_local['DB_NAME'],
    'username' => $env_local['DB_USER'],
    'password' => $env_local['DB_PASSWORD'],
    'host' => ($env_local['DB_HOST'] ?? '') ?: 'localhost',
    'port' => ($env_local['DB_PORT'] ?? '') ?: '3306',
    'driver' => 'mysql',
    'prefix' => '',
    'collation' => 'utf8mb4_general_ci',
  ];
  $settings['hash_salt'] = $env_local['HASH_SALT'];
}

unset($happiness_ddev, $happiness_env_file, $happiness_key);
