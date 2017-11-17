#!/usr/bin/env bash

USERNAME=$(cat ./testdata.json | jq -r '.login.username')

drush user-cancel ${USERNAME} --yes