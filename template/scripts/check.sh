#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p web/modules/custom web/themes/custom
vendor/bin/phpcs
vendor/bin/phpstan analyse --memory-limit=1G
