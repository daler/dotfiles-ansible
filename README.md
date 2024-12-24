# dotfiles with ansible

Sets up [daler/dotfiles](https://github.com/daler/dotfiles) on a remote host. Tested and used on AWS Ubuntu 22, but
the ideas should be valid for other hosts with some modification.

Uses a [custom ansible module](library/dotfile_facts.py) to provide facts about dotfiles installation on
the remote host.

## Usage

- In AWS Console, start a new AWS instance running Ubuntu 24.04 LTS
- Once running, add public IP from AWS Console to `hosts` file
- `./run-playbook.sh` to set everything up
  - Expects `EC2_PEM` env var to be set, which is the .pem file used when setting up the instance.

## Post-ansible setup

Some specific setup when working on github repos and specifically bioconda:

- Run `./copy-keys.sh` to copy over ssh keys from local machine to instance. Expects the following env vars:
  - `EC2_PEM`: path to .pem file used when setting up instance
  - `EC2_SSH_KEY`: path to private SSH key to be copied over (public will be copied over too)
  - `EC2_FIRST_LAST`: quoted first and last name to be added to `~/.gitconfig`
  - `EC2_EMAIL`: email to be added to `~/.gitconfig`
- Run `scp set-up-bioconda.sh ubuntu@$(grep -v ec2):~/` to copy over setup script
  (which needs ssh passphrase, so run this interactively on remote)
  - `./connect`, then on remote, `./set-up-bioconda.sh`

## Before terminating

Of course it depends on what you were doing, but may need to copy stuff
locally:

```bash
# copy back here when shutting down instance
REMOTE="/home/ubuntu/proj/bioconda-utils"
LOCAL="~/proj/bioconda-utils"
rsync -avr -e "ssh -i $EC2_PEM" --exclude env ubuntu@$(grep -v ec2 hosts):$REMOTE $LOCAL
```
