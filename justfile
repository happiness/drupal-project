# Tasks for this repository. `just` lists the recipes.

set shell := ["bash", "-euo", "pipefail", "-c"]

[private]
default:
    @just --list --unsorted

# Everything that should be green before a commit, fastest first
check: lint test-workflow

# Lint the shell scripts, the PHP and the justfiles
lint:
    shellcheck setup.sh github-setup.sh .github/scripts/*.sh scaffold/ddev/sanitize/sanitize.sh scaffold/ddev/commands/web/*
    php -l scaffold/settings.env.php
    just --justfile scaffold/justfile --working-directory . --list >/dev/null
    just --justfile scaffold/happiness.just --working-directory . --list >/dev/null

# The branch workflow scripts against real git histories (seconds, no DDEV)
test-workflow:
    bats tests/workflow.bats

# setup.sh and the sanitize hook on real DDEV sites (about 15 minutes)
test-ddev:
    bats tests/test.bats

# All tests
test: test-workflow test-ddev
