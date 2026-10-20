<?php

/**
 * @file
 * Extra anonymization run after `drush sql:sanitize`.
 *
 * Executed with `drush php:script` so tables that only exist on some sites
 * (dblog, webform, contact_storage) can be checked before they're touched.
 */

$db = \Drupal::database();
$schema = $db->schema();

$empty = function (string $table) use ($db, $schema): void {
  if ($schema->tableExists($table)) {
    $db->truncate($table)->execute();
    echo "Emptied $table\n";
  }
};

// Usernames: two-phase rename so the final names can't collide with existing
// ones on the user__name unique key. Done in a transaction so a failure can't
// leave accounts with temporary names.
$transaction = $db->startTransaction();
try {
  $db->update('users_field_data')
    ->expression('name', "CONCAT('sanitize-tmp-', uid)")
    ->condition('uid', 0, '>')
    ->execute();
  $db->update('users_field_data')
    ->expression('name', "CONCAT('user', uid)")
    ->condition('uid', 1, '>')
    ->execute();
  $db->update('users_field_data')
    ->fields(['name' => 'admin'])
    ->condition('uid', 1)
    ->execute();
  // "init" keeps the email address the account was registered with.
  $db->update('users_field_data')
    ->expression('init', 'mail')
    ->condition('uid', 0, '>')
    ->execute();
}
catch (\Exception $e) {
  $transaction->rollBack();
  throw $e;
}
unset($transaction);
echo "Anonymized usernames\n";

// Commenter IP addresses.
if ($schema->tableExists('comment_field_data')) {
  $db->update('comment_field_data')
    ->fields(['hostname' => '127.0.0.1'])
    ->execute();
  echo "Anonymized comment IP addresses\n";
}

// Core keeps the name of the last anonymous commenter per entity.
if ($schema->tableExists('comment_entity_statistics')) {
  $db->update('comment_entity_statistics')
    ->fields(['last_comment_name' => 'Anonymous'])
    ->condition('last_comment_uid', 0)
    ->condition('last_comment_name', '', '<>')
    ->execute();
  echo "Anonymized last commenter names\n";
}

// Log messages and flood entries contain usernames, emails and IPs.
$empty('watchdog');
$empty('flood');

// Expirable key/value data: private and shared tempstore (unsaved form input,
// with its owner), form state and other short-lived entries.
$empty('key_value_expire');

// Free-form submissions can't be anonymized field by field, so remove them.
foreach (['webform_submission', 'webform_submission_data', 'webform_submission_log'] as $table) {
  $empty($table);
}
$empty('contact_message');
// findTables() treats "_" as a wildcard, so check the prefix literally.
foreach ($schema->findTables('contact_message__%') as $table) {
  if (str_starts_with($table, 'contact_message__')) {
    $empty($table);
  }
}

// Fail loudly if `drush sql:sanitize` or anything above didn't apply. DDEV
// only warns about a failed hook, so this message is what tells the developer
// the imported database still holds real data. Keep "@localhost" in sync
// with --sanitize-email in sanitize.sh.
$leftover = $db->select('users_field_data', 'u')
  ->condition('uid', 0, '>')
  ->condition($db->condition('OR')
    ->condition('mail', '%' . $db->escapeLike('@localhost'), 'NOT LIKE')
    ->condition('init', '%' . $db->escapeLike('@localhost'), 'NOT LIKE')
    ->condition('name', 'sanitize-tmp-%', 'LIKE'))
  ->countQuery()
  ->execute()
  ->fetchField();
if ($leftover) {
  throw new \RuntimeException("DATABASE NOT SANITIZED: $leftover user account(s) still have real data. Do not use this database until the sanitize hook succeeds.");
}
echo "Verified user accounts are sanitized\n";
