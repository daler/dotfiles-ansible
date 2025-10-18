#!/bin/bash

PROVIDER="${1:-aws}"

# Validate provider
case "$PROVIDER" in
    aws|ec2)
        PROVIDER="aws"
        HOSTS_LIMIT="ec2"
        HOSTS_FILE="hosts-ec2"
        SSH_USER="ubuntu"
        ;;
    hetzner)
        PROVIDER="hetzner"
        HOSTS_LIMIT="hetzner"
        HOSTS_FILE="hosts-hetzner"
        SSH_USER="root"
        ;;
    *)
        echo "Unknown provider: $PROVIDER"
        echo "Usage: $0 [aws|ec2|hetzner] [additional ansible-playbook options]"
        exit 1
        ;;
esac

shift  # Remove provider argument so remaining args can be passed to ansible-playbook

[ -z $TF_VAR_EC2_LOGIN_KEY ] && echo 'Missing $TF_VAR_EC2_LOGIN_KEY (.pem file or SSH key prefix)' && exit 1

echo "Running playbook for provider: $PROVIDER (user: $SSH_USER)"
ansible-playbook playbook.yaml \
    -i "$HOSTS_FILE" \
    --limit "$HOSTS_LIMIT" \
    --private-key $TF_VAR_EC2_LOGIN_KEY \
    -u "$SSH_USER" \
    -e "provider=$PROVIDER" \
    "$@"
