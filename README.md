# dotfiles with ansible

## Overview

The goal of this repo is to start and configure a development box as seamlessly
and as quickly as possible.

This uses *terraform* to manage infrastructure (server and associated things like
firewalls) and *ansible* to manage configuration of the server once it's created.

There are two options for providers here, **AWS** and **Hetzner**.

**AWS** lets you start/stop instances so that you don't pay for compute on stopped
instances. You do pay for storage of the image, but that's a tiny fraction of
the compute cost. This is a good option if you plan to have long periods of
inactivity but want to keep the instance available (it usually takes less than
a minute to start a stopped instance).

**Hetzner** servers are about 10x cheaper than AWS for a month of compute. But
you cannot start/stop them, you need to create/destroy the server completely.
This is a good option if you know you will be using it fairly frequently.

## Install dependencies

- [Install terraform](https://developer.hashicorp.com/terraform/install) locally.
- [Install aws-cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) locally (only needed if you're using AWS)
- [Install ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) locally.

You can install them in to a conda env with:

```bash
conda create -p ./env -c conda-forge terraform awscli ansible
conda activate ./env
```

## Hetzner

This is a combination of manual steps in the console and automated setup.
Creating a project with API keys needs to be manual because it's using the
Hetzner console for initial authentication.

Creating a volume manually ensures we don't inadvertently delete it with
`terraform destroy`. However, with Hetzner we can only create a volume if it is
attached to a server so we need to make sure the server is created first.

### Initial setup

1. Manually create a new Hetzner project on https://console.hetzner.com/projects.
2. In the new project's dashboard, create a new read/write API token (Security
   -> API -> API tokens). Store it in `TF_VAR_hetzner_token` environment
   variable. This API key is scoped to the project, so whatever you create will
   be in this project.
3. Decide on an SSH key to use to connect to the new host, creating one if
   needed. Store this in the `TF_VAR_hcloud_ssh_key_file` environment variable.

So you should have these env vars set:

| env var                    | description                                       |
|----------------------------|---------------------------------------------------|
| TF_VAR_hcloud_ssh_key_file | existing private key file, e.g., `~/.ssh/hetzner` |
| TF_VAR_hetzner_token       | API token for project                             |


### Infrastructure creation

Change to the `hetzner` directory.

1. Edit `terraform.tfvars`, following the comments in that file. This
   includes location and server type.
1. Run `terraform init`. This will make sure you have the hcloud provider
   installed for terraform.
3. Run `terraform apply`. This will show you what will be created. Type "yes"
   if it all looks good. This will:
   - Create a server of the type and location configured, using configured SSH key to log in
   - if a volume with the label `name=devboxdata` exists, mount it -- otherwise don't mount anything yet.
   - create a firewall allowing SSH from anywhere
   - Create a local `hosts` file with the public IP for use with Ansible (below)
4. In the project's dashboard, verify that a new server has been created.
5. If an existing volume in the location has the label `name=devboxdata` then
   this will be mounted automatically. Otherwise, create a new volume in the
   Hetzner Console and attach it to this new server.
    - Make sure you select "Automatic" for mount options.
    - Filesystem should be EXT4
    - Add a label `name=devboxdata`

### Configuration

Run `./run-playbook.sh`. It will ask if you want to connect to the host, type
`yes`. This will do many things (see "Details of ansible configuration" below)
but the Hetzner-specific pieces are the following, which makes the server look
similar to an AWS instance:

- Create `ubuntu` user with sudo privileges
- Ensure the volume you created is persistently mounted at `/data`

The other tasks run in the playbook are common to Hetzner and AWS and are
described below.

### Usage

Run `./connect` to connect to the server.

This uses SSH forwarding so your local keys can be used on the server (e.g., to
push to GitHub).

### Deletion

Run `terraform destroy` to delete the server.

- If you really want to delete the volume, do so in the console.

- If you really want to delete the project, do so in the console.

### Re-using

Next time you want to spin up a server:

1. `terraform apply` (this will automatically detect and auto-mount an existing volume with the `name=devboxdata` label)
2. `./run-playbook.sh`
3. `./connect`
4. `terraform destroy` when done

## AWS


### Initial setup

1. Set environment variables for AWS, `AWS_ACCESS_KEY_ID` and
   `AWS_SECRET_ACCESS_KEY`, which you can get from the AWS Console.
1. Run `aws configure` to get a default region set up. This only has to be done once.
3. In the AWS Console, manually create an EBS volume (or tag an existing one)
   with the tag `Name` and the value `devboxdata`, which will be mounted at
   `/data` on a new instance. (Edit `terraform.tfvars` if you want a different
   name).
    - EC2 > Elastic Block Store > Volumes > Create volume > make sure to add
      tag with key `Name` and value `devboxdata`.
    - Creating this persistent volume through the AWS Console keeps it away
      from terraform to reduce the risk of `terraform destroy` affecting it.
4. Choose an email to use for notifications, and store this in the
   `TF_VAR_NOTIFICATION_EMAIL` env var.
5. Choose or create a private key file to use, and set as the `TF_VAR_EC2_LOGIN_KEY` env var.

So you should have the following environment variables set:

| env var                   | description                                                                                       |
|---------------------------|---------------------------------------------------------------------------------------------------|
| TF_VAR_EC2_LOGIN_KEY      | .pem file (if instance was created in console), or existing private key file (if using terraform) |
| TF_VAR_NOTIFICATION_EMAIL | email for notifications on instance                                                               |
| AWS_ACCESS_KEY_ID         | From AWS console                                                                                  |
| AWS_SECRET_ACCESS_KEY     | From AWS console                                                                                  |



### Infrastructure creation

Change to the `aws` directory.

1. Edit `terraform.tfvars`, following the comments in that file.
2. Run `terraform init` to make sure the AWS terraform provider is installed.
3. Run `terraform apply`. Type `yes` if all looks good. This will:
    - Create a VPC with public subnet, internet gateway, and route table for
      internet access
    - Allow SSH access (port 22) from anywhere
    - Upload `~/.ssh/aws.pub` public key to AWS for instance access
    - Create an Ubuntu server using the latest HVM SSD AMD64 image, with
      auto-mounting script for the persistent volume
    - Attach existing `devboxdata` EBS volume to `/data` on the server
    - Create a local `hosts` file with the public IP for use with Ansible (below) and keep
      track of instance ID in `.instance_id` for start/stop scripts
    - Create a lambda function that will run at the scheduled rate (default: every
      6 hrs) until you do `terraform destroy`, and send you an email reminding you
      the instance is still up. Technially, this sets up an SNS topic, an IAM role,
      a Python script in a zip file that is uploaded to be executed as a Lambda,
      a CloudWatch event for checking the instance, and an EventBridge rule for
      scheduling.
4. Check the email configured above, and click the link to subscribe to alerts.

<details>
<summary>About notifications</summary>

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
</details>

Note: I looked into SMS messages instead of email, but that ends up being
overly cumbersome and expensive (and requires getting approval from AWS and an
originator number)...so email it is.

</details>

### Configuration

Run `./run-playbook.sh`. It will ask if you want to connect to the host, type
`yes`. This will do many things; see "Details of ansible configuration" below.

### Usage

Run `./connect` to connect to the server. This uses SSH forwarding so your
local keys can be used on the server (e.g., to push to GitHub).

Run `./stop` to stop the server. You will not pay for compute, but you will
still pay for the storage of the image -- but this is a tiny fractio of the
compute cost.

Run `./start` to start the server so you can `./connect` again. This will
repopulate the `.instance_id` and `hosts` files with instance ID and IP address
respectively.

### Deletion

Run `terraform destroy` to terminate the server, and delete the VPC, Lambda
function, and CloudWatch event.

If you really want to delete the volume, do so in the AWS Console.

### Re-using

If you have run `terraform destroy` and want to get set up again:

1. `terraform apply` (this will automatically detect and auto-mount an existing volume with the `name=devboxdata` label)
2. `./run-playbook.sh`
3. `./connect`
4. `terraform destroy` when done

## Details of ansible configuration

The ansible playbook is split into these pieces:

- `playbook.yaml`, top-level playbook that refers to others, including:
- `hetzner-root-setup.yaml` runs only for Hetzner; it:
  - uses the root user to create an `ubuntu` user to match that of an AWS instance
  - detects and mounts volume to `/data` 
- `common-system.yaml`, which:
  - Installs docker, podman, htop, tmux, build tools, and more
  - Adds the ubuntu user to docker group
  - Allows agent forwarding for SSH
  - Does an `apt upgrade` to ensure things are up-to-date
- `common-dotfiles.yaml`, which:
  - Uses [daler/dotfiles](https://github.com/daler/dotfiles)
  - Uses a [custom ansible module](library/dotfile_facts.py) to provide facts about dotfiles installation
  - Installs conda to `/data/miniforge`
  - Sets up bioconda channel
  - Installs tools like `fd`, `rg`, `vd`, `fzf`, `npm`, `nvim`
  - Installs LSPs and plugins for `nvim`
  - Docker setup (add ubuntu user to docker group)
  - Match `~/.gitconfig` username and email with what is found locally
  - Add support for [GitHub SSH-over-HTTPS](https://docs.github.com/en/authentication/troubleshooting-ssh/using-ssh-over-the-https-port)
  - Color bash prompt (so it's clear you're on a different host)
  - Enable SSH key forwarding

The `aws/run-playbook.sh` and `hetzner/run-playbook.sh` scripts call the main
ansbile playbook to restrict hosts according to the provider (see those scripts
for details).

Sometimes there is a failure or error. It's fine to run `./run-playbook.sh`
multiple times, if a configuration is already completed it will skip and move
on to the next.
