<?php

/**
 * @file
 * Test fixture: an article with a comment from an anonymous visitor.
 *
 * Run with `drush php:script` after enabling the comment module.
 */

use Drupal\comment\Entity\Comment;
use Drupal\comment\Entity\CommentType;
use Drupal\comment\Plugin\Field\FieldType\CommentItemInterface;
use Drupal\field\Entity\FieldConfig;
use Drupal\field\Entity\FieldStorageConfig;
use Drupal\node\Entity\Node;
use Drupal\node\Entity\NodeType;

NodeType::create(['type' => 'article', 'name' => 'Article'])->save();
CommentType::create([
  'id' => 'comment',
  'label' => 'Comment',
  'target_entity_type_id' => 'node',
])->save();
FieldStorageConfig::create([
  'entity_type' => 'node',
  'field_name' => 'comment',
  'type' => 'comment',
  'settings' => ['comment_type' => 'comment'],
])->save();
FieldConfig::create([
  'entity_type' => 'node',
  'bundle' => 'article',
  'field_name' => 'comment',
  'label' => 'Comments',
])->save();

$node = Node::create([
  'type' => 'article',
  'title' => 'Hello',
  'uid' => 1,
  'comment' => ['status' => CommentItemInterface::OPEN],
]);
$node->save();

Comment::create([
  'entity_type' => 'node',
  'entity_id' => $node->id(),
  'field_name' => 'comment',
  'comment_type' => 'comment',
  'uid' => 0,
  'name' => 'Visitor Jane',
  'mail' => 'visitor@example.com',
  'hostname' => '203.0.113.9',
  'subject' => 'Hi',
  'status' => 1,
])->save();
