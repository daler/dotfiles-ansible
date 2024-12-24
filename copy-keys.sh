#!/bin/bash

set -eo pipefail

[ -z "$EC2_PEM" ] && (echo 'Missing $EC2_PEM (.pem used when creating instance)'; exit 1)
[ -z "$EC2_SSH_KEY" ] && (echo 'Missing $EC2_SSH_KEY (private key)'; exit 1)
[ -z "$EC2_FIRST_LAST" ] && (echo 'Missing $EC2_FIRST_LAST (for git config)'; exit 1)
[ -z "$EC2_EMAIL" ] && (echo 'Missing $EC2_EMAIL (for git configz)'; exit 1)

set -ux

scp -i "$EC2_PEM" \
        ${EC2_SSH_KEY} \
        ${EC2_SSH_KEY}.pub \
        ubuntu@$(grep -v ec2 hosts):/home/ubuntu/.ssh

ssh -i $EC2_PEM ubuntu@$(grep -v ec2 hosts) /bin/bash << EOF
chmod 0600 .ssh/$(basename ${EC2_SSH_KEY})
git config --global user.name "$EC2_FIRST_LAST"
git config --global user.email "$EC2_EMAIL"
EOF
