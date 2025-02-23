#!/bin/bash

set -eo pipefail

[ -z "$TF_VAR_EC2_LOGIN_KEY" ] && (echo 'Missing $TF_VAR_EC2_LOGIN_KEY (.pem used when creating instance)'; exit 1)
[ -z "$TF_VAR_EC2_INSTALL_SSH_KEY" ] && (echo 'Missing $TF_VAR_EC2_INSTALL_SSH_KEY (private key)'; exit 1)

GIT_FIRST_LAST=$(git config --get user.name)
GIT_EMAIL=$(git config --get user.email)

set -ux

scp -i "${TF_VAR_EC2_LOGIN_KEY}" \
        "${TF_VAR_EC2_INSTALL_SSH_KEY}" \
        "${TF_VAR_EC2_INSTALL_SSH_KEY}.pub" \
        ubuntu@$(grep -v ec2 hosts):/home/ubuntu/.ssh

ssh -i "$TF_VAR_EC2_LOGIN_KEY" ubuntu@$(grep -v ec2 hosts) /bin/bash << EOF
chmod 0600 .ssh/$(basename ${TF_VAR_EC2_INSTALL_SSH_KEY})
git config --global user.name "$GIT_FIRST_LAST"
git config --global user.email "$GIT_EMAIL"
EOF
