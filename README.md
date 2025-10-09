# dotfiles with ansible

## Overview

Start and configure a development box as seamlessly and as quickly as possible.

- Use terraform to set up an AWS instance (optional; you can use AWS Console instead)
- Use ansible to set up [daler/dotfiles](https://github.com/daler/dotfiles) on a remote host.
  - Uses a [custom ansible module](library/dotfile_facts.py) to provide facts
    about dotfiles installation on the remote host.
- Scripts to easily connect, start, and stop the instance.

Tested and used on AWS Ubuntu, but the ideas should be valid for other hosts
with modification.

**TL;DR:**


| command             | description                                           |
|---------------------|-------------------------------------------------------|
| `./start`           | Starts the instance if it was stopped                 |
| `terraform apply`   | Build infrastructure, attach devbox storage. 1-2 mins |
| `./run-playbook.sh` | Install conda, dotfiles, and more. ~3 mins            |
| `./connect`         | Connect to host                                       |
| `./stop`            | Stop instance                                         |
| `terraform destroy` | Tear down infra EXCEPT storage                        |


Connect, and go to `/data` for the mounted volume.

## Env var assumptions

The following environment variables are assumed to be available:

| env var               | description                                                                             |
|-----------------------|-----------------------------------------------------------------------------------------|
| TF_VAR_EC2_LOGIN_KEY  | .pem file (if instance created in console), or existing private key file (if terraform) |
| AWS_ACCESS_KEY_ID     | From AWS console                                                                        |
| AWS_SECRET_ACCESS_KEY | From AWS console                                                                        |


## One-time setup

The following needs to be done once; after this you can create/destroy the
infrastructure and redeploy many times.

- [Install terraform](https://developer.hashicorp.com/terraform/install) locally.
- [Install aws-cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) locally.
- Create a keypair in `~/.ssh/aws` (e.g., `ssh-keygen -f ~/.ssh/aws`) that will
  be configured for use with any new instances.
- Run `terraform init` (this sets up AWS provider, for example).
- Run `aws configure` to get a default region.
- Create an EBS volume (or tag an existing one) with the tag `Name` and the
  value `devboxdata`, which will be mounted at `/data` on a new instance. (Edit
  `terraform.tfvars` if you want a different name).
  (Create this volume through the AWS console, it keeps it away from terraform
  to reduce the risk of `terraform destroy` affecting it).
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


## Ansible setup

Run the following:

```bash
`./run-playbook.sh`
```

This takes 2-3 mins.

This does the following:

- installs conda to `/data/miniforge`
- sets up bioconda channel
- installs various tools in [daler/dotfiles](https://github.com/daler/dotfiles):  `fd`, `rg`, `vd`, `fzf`, `npm`, `nvim`
- installs LSPs and plugins for `nvim`
- installs various tools from Ubuntu repository (docker, podman, htop, tmux, and more -- see `playbook.yaml` for the full set)
- Docker setup (add ubuntu user to docker group)
- Match `~/.gitconfig` username and email with what is found locally
- Add support for [GitHub SSH-over-HTTPS](https://docs.github.com/en/authentication/troubleshooting-ssh/using-ssh-over-the-https-port)
- Color bash prompt (so it's clear you're on a different host)
- Enable SSH key forwarding so you don't have to copy key files over to the
  host


## Connecting

Connect to the instance with:

```bash
./connect.sh
```

This reads the `hosts` file, which is populated by terraform or `./start` with
the IP, or was manually updated if using AWS Console instead of terraform.

It expects the env var `$TF_VAR_EC2_LOGIN_KEY` to exist -- this is `~/.ssh/aws`
by default as described above.

## Stopping and (re)starting the instance

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
