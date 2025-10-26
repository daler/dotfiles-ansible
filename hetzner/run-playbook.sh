#!/bin/bash

PROVIDER=hetzner
SSH_USER=root

[ -z $TF_VAR_EC2_LOGIN_KEY ] && echo 'Missing $TF_VAR_EC2_LOGIN_KEY (.pem file or SSH key prefix)' && exit 1

ansible-playbook ../playbook.yaml \
    -i "hosts" \
    --limit "$PROVIDER" \
    --private-key $TF_VAR_EC2_LOGIN_KEY \
    -u "$SSH_USER" \
    -e "provider=$PROVIDER" \
    "$@"
