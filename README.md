# dotfiles with ansible

- Use terraform to set up an instance (optional; you can use AWS Console instead)
- Use ansible to set up [daler/dotfiles](https://github.com/daler/dotfiles) on a remote host.

Tested and used on AWS Ubuntu, but the ideas should be valid for other hosts
with modification.

Uses a [custom ansible module](library/dotfile_facts.py) to provide facts about
dotfiles installation on the remote host.

## Env var assumptions

The following environment variables are assumed to be available:

| env var                    | description                                                                             |
|----------------------------|-----------------------------------------------------------------------------------------|
| TF_VAR_EC2_LOGIN_KEY       | .pem file (if instance created in console), or existing private key file (if terraform) |
| TF_VAR_EC2_INSTALL_SSH_KEY | SSH key to be copied over to instance to enable e.g. github access                      |
| AWS_ACCESS_KEY_ID          | From AWS console                                                                        |
| AWS_SECRET_ACCESS_KEY      | From AWS console                                                                        |


## Host creation (manual)

- In AWS Console, start a new AWS instance running Ubuntu 24.04 LTS
- Edit `hosts` file with public IP listed in AWS Console, to look like this:

```
[ec2]
<IP address here>
```

- Ensure `$TF_VAR_EC2_LOGIN_KEY` is set to the .pem file you used when creating
  the instance, which is used by `./connect`.

## Host creation (terraform)

Assumptions:

- You have installed terraform and aws-cli locally
- You have run `terraform init` (this sets up aws provider, for example)
- `aws configure` has been run with a default region
- You have an existing volume with the tag `Name` with the value `devboxdata`,
  which will be mounted at `/data` on the instance.
- `terraform.tfvars` has been edited appropriately.
- The following env vars are configured:

| env var               | description      |
|-----------------------|------------------|
| AWS_ACCESS_KEY_ID     | From AWS console |
| AWS_SECRET_ACCESS_KEY | From AWS console |

Run the following:

```bash
terraform apply
```

If all looks good, answer "yes". Provisioning takes 1-2 mins.

## Ansible setup

Run the following:

```bash
`./run-playbook.sh`
```

This takes 2-3 mins.

If you intend on doing e.g. GitHub development work, you can optionally copy
over a local SSH key (that has been added to GitHub), and set the remote
`~/.gitconfig` to reflect your local copy. Specifically, the local values of
`git config --get user.email` and `git config --get user.name` will be added to
the remote `~/.gitconfig`.


```bash
# optional
./copy-keys.sh
```

## Connecting

Connect to the instance with:

```bash
./connect.sh
```

This reads the `hosts` file, which is populated by terraform or `./start` with
the IP or must be manually updated if using AWS Console.

It expects the env var `$TF_VAR_EC2_LOGIN_KEY`.

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

## Destroy

To terminate the instance (and remove VPC and subnet), run:

```bash
terraform destroy
```

Note that this will NOT delete the persistent volume you set up previously (and
which was attached to `/data` on the instance), but it **WILL delete everything
in the root partition**. So upon starting a new instance, you'll need to re-run
`./run-playbook` and `copy-keys` again.

Recall that the stopped instance does not accumlate *running* charges, but it
does accumlate *storage* charges. So the decision is, "do I want to destroy (and
pay the ~5 mins setup time later) or keep it stopped and pay for instance storage?".
