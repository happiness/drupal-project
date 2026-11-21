# Recipes every Happiness Drupal site shares, imported by the site's justfile.
#
# Managed by setup.sh from happiness/drupal-project, which overwrites this file:
# change it there (scaffold/happiness.just), not here. Site recipes go in justfile.
# The branch and release recipes are in deploy.just.

set shell := ["bash", "-euo", "pipefail", "-c"]

[private]
default:
    @just --list --unsorted

# Start DDEV
up:
    ddev start

# Install PHP dependencies
install:
    ddev composer install

# Stop DDEV
down:
    ddev stop

# Everything that should be green before a commit, fastest first
check: cs stan test

# Check the code style; pass paths to limit the scope (just cs web/modules/custom/foo)
cs *args:
    ddev exec vendor/bin/phpcs {{ args }}

# Fix the code style automatically
fix *args:
    ddev exec vendor/bin/phpcbf {{ args }}

# PHPStan
stan *args:
    ddev exec vendor/bin/phpstan {{ args }}

# PHPUnit, from the docroot as Drupal's functional tests need; uses phpunit.xml if it exists, else phpunit.xml.dist (just test --filter FooTest)
test *args:
    ddev exec 'config=/var/www/html/phpunit.xml; [ -f "$config" ] || config=/var/www/html/phpunit.xml.dist; cd /var/www/html/web && ../vendor/bin/phpunit --configuration "$config" {{ args }}'

# Run the Drupal CLI (just dr list)
dr *args:
    ddev exec vendor/bin/dr {{ args }}

# Run a Drush command (just drush status)
drush *args:
    ddev drush {{ args }}

# Clear all caches
cr:
    ddev drush cache:rebuild

# Run database updates, import config and clear caches, as a deploy does
update:
    ddev drush deploy

# Export config to config/sync
cex:
    ddev drush config:export -y

# Import config from config/sync
cim:
    ddev drush config:import -y

# One-time login link for the admin user
login:
    ddev drush user:login
