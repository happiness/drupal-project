#!/usr/bin/env bash

USERNAME=$(cat ./testdata.json | jq -r '.login.username')
PASSWORD=$(cat ./testdata.json | jq -r '.login.password')
MAIL=$(cat ./testdata.json | jq -r '.login.mail')

drush user-create ${USERNAME} --mail="${MAIL}" --password="${PASSWORD}"
drush user-add-role "member" ${USERNAME}