#!/usr/bin/env bash

# Setup
./scripts/setup.sh

# Tests
casperjs test tests/frontpage.js
casperjs test tests/login.js
casperjs test tests/take-part.js

# Tear down
./scripts/teardown.sh
