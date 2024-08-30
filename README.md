Sets up daler/dotfiles on a remote host. Tested and used on AWS Ubuntu 22, but
the ideas should be valid for other hosts with some modification.

Uses a custom ansible module to provide facts about dotfiles installation on
the remote host.

Usage:

- start a new AWS instance running Ubuntu 22 LTS
- copy the public IP, and put that in `hosts` file
- run `ansible-playbook playbook.yaml -i hosts --private-key <PATH TO PRIVATE KEY> -u ubuntu`


```bash
# Post-ansible setup when working on github repos
# TODO:
#  Possibly have ansible optionally do this, or use some sort of secrets
#  management functionality

PEM="<PATH TO PRIVATE AWS KEY>"
SSH_KEY="<PATH TO PRIVATE SSH KEY>"

scp -i $PEM ${SSH_KEY} ubuntu@$(grep -v ec2 hosts):/home/ubuntu/${SSH_KEY}
scp -i $PEM ${SSH_KEY}.pub ubuntu@$(grep -v ec2 hosts):/home/ubuntu/${SSH_KEY}.pub

ssh -i $PEM ubuntu@$(grep -v ec2 hosts)
chmod 0600 ${SSH_KEY}
git config --global user.name "first last"
git config --global user.email "email here"

```


```bash
# Set up bioconda stuff.
# Expects SSH keys to be copied and git config set up.
for i in recipes containers utils docs; do
  git clone git@github.com:bioconda/bioconda-$i ~/proj/bioconda-$i
done

(
  cd proj/bioconda-utils
  conda create \
    -p ./env \
    -y \
    --file bioconda_utils/bioconda_utils-requirements.txt \
    --file test-requirements.txt
)

# copy back here when shutting down instance
REMOTE="/home/ubuntu/proj/bioconda-utils"
LOCAL="~/proj/bioconda-utils"
rsync -avr -e "ssh -i $PEM" --exclude env ubuntu@$(grep -v ec2 hosts):$REMOTE $LOCAL

```
