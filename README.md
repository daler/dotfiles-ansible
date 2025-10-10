# dotfiles with ansible

## Overview

Start and configure a development box as seamlessly and as quickly as possible.

- Use terraform to set up an AWS instance (optional; you can use AWS Console instead)
- Use ansible to set up [daler/dotfiles](https://github.com/daler/dotfiles) on a remote host.
- Scripts to easily connect, start, and stop the instance.

Tested and used on AWS Ubuntu, but the ideas should be valid for other hosts
with modification.

**TL;DR:**


| command             | description                                           |
|---------------------|-------------------------------------------------------|
| `./start`           | Starts the instance if it was stopped                 |
| `terraform apply`   | Build infrastructure, attach devbox storage. 1-2 mins |
| `./connect`         | Connect to host                                       |
| `./run-playbook.sh` | Install conda, dotfiles, and more. ~3 mins            |
| `./stop`            | Stop instance                                         |
| `terraform destroy` | Tear down infra EXCEPT storage                        |


Connect, and go to `/data` for the mounted volume.

## Env var assumptions

The following environment variables are assumed to be available:

| env var                   | description                                                                             |
|---------------------------|-----------------------------------------------------------------------------------------|
| TF_VAR_EC2_LOGIN_KEY      | .pem file (if instance created in console), or existing private key file (if terraform) |
| TF_VAR_NOTIFICATION_EMAIL | email for notifications on instance                                                     |
| AWS_ACCESS_KEY_ID         | From AWS console                                                                        |
| AWS_SECRET_ACCESS_KEY     | From AWS console                                                                        |


## One-time setup

The following needs to be done once; after this you can create/destroy the
infrastructure and redeploy many times.


- [Install terraform](https://developer.hashicorp.com/terraform/install) locally.
- [Install aws-cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) locally.
- [Install ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) locally.

Note: you can install all of these with conda, e.g.

```bash
conda create -p ./env -c conda-forge terraform awscli ansible
conda activate ./env
```

- Create a keypair in `~/.ssh/aws` (e.g., `ssh-keygen -f ~/.ssh/aws`). This will
  be configured to be the key to log in to any new instances.

- Run `terraform init`. The primary thing this does is set up the AWS provider.

- Run `aws configure` to get a default region.

- In the AWS Console, manually create an EBS volume (or tag an existing one)
  with the tag `Name` and the value `devboxdata`, which will be mounted at
  `/data` on a new instance. (Edit `terraform.tfvars` if you want a different
  name). EC2 > Elastic Block Store > Volumes > Create volume > make sure to add
  tag with key `Name` and value `devboxdata`. Creating this persistent volume
  through the AWS Console keeps it away from terraform to reduce the risk of
  `terraform destroy` affecting it.

- Review and edit `terraform.tfvars`.


## Infrastructure provisioning

Run the following:

```bash
terraform apply
```
If all looks good, answer "yes". Provisioning takes 1-2 mins.

It will do the following:

- Creates a VPC with public subnet, internet gateway, and route table for internet access
- Allows SSH access (port 22) from anywhere
- Uploads `~/.ssh/aws.pub` public key to AWS for instance access
- Creates Ubuntu server using the latest HVM SSD AMD64 image, with auto-mounting script for the persistent volume
- Attaches existing `devboxdata` EBS volume to `/data`
- Creates `hosts` file with the public IP for use with Ansible (below) and keep
  track of instance ID in `.instance_id` for start/stop scripts
- Creates a lambda function that will run at the scheduled rate (default: every
  6 hrs) until you do `terraform destroy`, and send you an email reminding you
  the instance is still up. Technially, this sets up an SNS topic, an IAM role,
  a Python script in a zip file that is uploaded to be executed as a Lambda,
  a CloudWatch event for checking the instance, and an EventBridge rule for
  scheduling.


## About notifications

Upon successful `terraform apply`, you will get an email confirming the
subscription to this notification. You'll need to click the link to get any
more. If you do `terraform destroy` and then `terraform apply` again, that sets
up a new notification that you'll need to subscribe to again.

The Lambda will be run until you do `terraform destroy` again. In practice,
I'll often start/stop an instance many times over a couple of weeks, which
means that Lambda will be running every N hours (every 6 hrs by default). This
is inexpensive ($1 a month if running continously every 6 hrs for a month), but
be aware.

For testing the notifications, you can *temporarily* set the rate to `rate(1
minute)` in `terraform.tfvars`, re-apply, and check the logs with:

```bash
terraform apply  # should only be changing the rate
aws logs tail /aws/lambda/check-instance-uptime --follow
```

If the instance is up, you're getting emails, and the log doesn't report
errors, then set it back to some longer interval like `rate(6 hours)`, and
re-apply with `terraform apply` so you're not running the Lambda so often.

Note: I looked into SMS messages instead of email, but that ends up being
overly cumbersome and expensive (and requires getting approval from AWS and an
originator number)...so email it is.

## Host creation (manual)

<details>
<summary>Click to expand manual host creation instructions</summary>

If you don't want to use terraform, start an instance manually:

- In AWS Console, start a new AWS instance running Ubuntu 24.04 LTS. Make sure to mount `devbox`.
- Edit `hosts` file with public IP listed in AWS Console, to look like this:

```
[ec2]
<IP address here>
```

When creating the instance, ensure `$TF_VAR_EC2_LOGIN_KEY` is set to the .pem
file you use, because the file indicated by that env var is used by
`./connect`.

</details>

## Connecting

Connect to the instance with:

```bash
./connect.sh
```

This reads the `hosts` file, which is populated by terraform or `./start` with
the IP, or was manually updated if using AWS Console instead of terraform.

It expects the env var `$TF_VAR_EC2_LOGIN_KEY` to exist -- this is `~/.ssh/aws`
by default as described above.

You will need to say "yes" to connecting to this host. Once you confirm you can
successfully connect, exit the host and then continue on to running the Ansible
setup locally.

## Ansible setup

Run the following:

```bash
./run-playbook.sh
```

This takes 2-3 mins.

This does the following:

- Installs conda to `/data/miniforge`
- Sets up bioconda channel
- Installs various tools in
  [daler/dotfiles](https://github.com/daler/dotfiles):  `fd`, `rg`, `vd`,
  `fzf`, `npm`, `nvim`. Uses a [custom ansible
  module](library/dotfile_facts.py) to provide facts about dotfiles
  installation on the remote host.
- Installs LSPs and plugins for `nvim`
- Installs various tools from Ubuntu repository (docker, podman, htop, tmux, and more -- see `playbook.yaml` for the full set)
- Docker setup (add ubuntu user to docker group)
- Match `~/.gitconfig` username and email with what is found locally
- Add support for [GitHub SSH-over-HTTPS](https://docs.github.com/en/authentication/troubleshooting-ssh/using-ssh-over-the-https-port)
- Color bash prompt (so it's clear you're on a different host)
- Enable SSH key forwarding so you don't have to copy key files over to the
  host

Now you should be able to run:

```bash
./connect
```

and the various tools (`rg`, `fd`, `conda`, `nvim`, etc) should be available.


## Stopping and (re)starting the instance

Stopping an instance means you don't pay for the compute any more. You do pay
for the storage (like the root volume) but this is a tiny cost compared to the
cost of compute.

Either use the AWS Console, or if you used terraform (and therefore you have an
`.instance_id` file automatically created with the instance ID), then use:

```bash
# stops instance and waits until it's stopped before exiting
./stop
```

and

```bash
# starts instance, waits until started, and updates./hosts file with new IP
./start
```

These scripts use the contents of `.instance_id`, which are created by
terraform. They will wait until the instance is started/stopped before exiting.
They can be run multiple times; e.g. you can keep running `./start`
until it reports "running". 

## Copying files

If you need to copy files from the remote instance to your local machine, you can use:

```bash
./copy-to-local <remote-file-path>
```

which will copy to the current directory.

## Destroy

To terminate the instance (and remove VPC and subnet), run:

```bash
terraform destroy
```

Note that this will NOT delete the persistent volume you set up previously (and
which was attached to `/data` on the instance), but it **WILL delete everything
in the root partition**. So upon starting a new instance, you'll need to re-run
`./run-playbook` again.

Recall that the stopped instance does not accumlate *running* charges, but it
does accumlate *storage* charges. So the decision is, "do I want to destroy (and
pay the ~5 mins setup time later) or keep it stopped and pay for instance storage?".
