# Hetzner Setup with Terraform

This guide shows how to use Terraform to provision a Hetzner Cloud server with persistent storage.

## Prerequisites

1. **Hetzner Cloud Account**: Sign up at https://console.hetzner.cloud/
2. **API Token**: Create an API token in the Hetzner Cloud Console:
   - Go to Security → API Tokens
   - Click "Generate API Token"
   - Give it Read & Write permissions
   - Save the token securely

3. **Environment Setup**:
   ```bash
   # Set your Hetzner API token
   export TF_VAR_hetzner_token="your-api-token-here"

   # Set your SSH key path (if different from default)
   export TF_VAR_ssh_key_file="~/.ssh/aws"
   ```

## Quick Start

1. **Initialize Terraform** (if not already done):
   ```bash
   terraform init
   ```

2. **Review Configuration**:
   Edit `terraform.tfvars` or create one based on `terraform.tfvars.hetzner.example`:
   ```bash
   cp terraform.tfvars.hetzner.example terraform.tfvars
   ```

   Configure your preferences:
   - `hetzner_server_type`: Server size (default: cx21)
   - `hetzner_location`: Datacenter location (default: nbg1)
   - `hetzner_volume_size`: Volume size in GB (default: 100)

3. **Create Infrastructure**:
   ```bash
   # Preview changes
   terraform plan -target=hcloud_server.devbox

   # Apply only Hetzner resources
   terraform apply -target=hcloud_server.devbox \
                   -target=hcloud_volume.devbox_data \
                   -target=hcloud_volume_attachment.devbox_data \
                   -target=hcloud_ssh_key.default \
                   -target=hcloud_firewall.devbox \
                   -target=local_file.hosts_hetzner

   # Or apply all resources (AWS + Hetzner):
   terraform apply
   ```

4. **Get Server Information**:
   ```bash
   # Get server IP
   terraform output hetzner_server_ip

   # View all outputs
   terraform output
   ```

5. **Connect to Server**:
   ```bash
   ./connect hetzner
   ```

6. **Run Ansible Setup**:
   ```bash
   ./run-playbook.sh hetzner
   ```

## Server Types and Pricing

Common Hetzner server types (as of 2024):

| Type  | vCPU | RAM   | Disk  | Price/month |
|-------|------|-------|-------|-------------|
| cx21  | 2    | 4 GB  | 40 GB | ~€5         |
| cx31  | 2    | 8 GB  | 80 GB | ~€10        |
| cx41  | 4    | 16 GB | 160 GB| ~€20        |
| cpx21 | 3    | 4 GB  | 80 GB | ~€7         |
| cpx31 | 4    | 8 GB  | 160 GB| ~€13        |

## Locations

- `nbg1` - Nuremberg, Germany
- `fsn1` - Falkenstein, Germany
- `hel1` - Helsinki, Finland
- `ash` - Ashburn, Virginia, USA
- `hil` - Hillsboro, Oregon, USA

## Managing the Server

### Start/Stop
Use the Hetzner Cloud Console or CLI:
```bash
# Using hcloud CLI (install: brew install hcloud)
hcloud server list
hcloud server stop devbox
hcloud server start devbox
```

### Update IP After Restart
If the IP changes, Terraform will automatically update `hosts-hetzner`:
```bash
terraform refresh
```

### Destroy Infrastructure
To remove the server but keep the volume:
```bash
terraform destroy -target=hcloud_volume_attachment.devbox_data
terraform destroy -target=hcloud_server.devbox
```

To destroy everything including the volume:
```bash
terraform destroy -target=hcloud_server.devbox \
                  -target=hcloud_volume.devbox_data \
                  -target=hcloud_volume_attachment.devbox_data \
                  -target=hcloud_ssh_key.default \
                  -target=hcloud_firewall.devbox
```

## Volume Management

The volume is automatically created, formatted (ext4), and mounted at `/data` during server provisioning. The Terraform user_data script:
1. Waits for the volume to be attached (appears as `/dev/sdb`)
2. Formats the volume if it doesn't already have a filesystem
3. Creates the `/data` mount point
4. Adds the volume to `/etc/fstab` for persistence across reboots
5. Mounts the volume at `/data`

If there are any issues with mounting, check the logs:
```bash
ssh root@$(terraform output -raw hetzner_server_ip) "cat /var/log/volume-mount.log"
ssh root@$(terraform output -raw hetzner_server_ip) "cat /var/log/volume-mount-error.log"
```

The volume device path:
- Direct path: `/dev/sdb` (first attached volume)
- By-id path: `/dev/disk/by-id/scsi-0HC_Volume_<volume-id>`

Get the volume device from Terraform:
```bash
terraform output hetzner_volume_device
```

## Comparison with AWS Setup

| Feature           | AWS (main.tf)     | Hetzner (hetzner.tf) |
|-------------------|-------------------|----------------------|
| Provider          | AWS               | Hetzner Cloud        |
| Instance          | EC2               | Cloud Server         |
| Storage           | EBS Volume        | Volume               |
| Networking        | VPC, Subnet, IGW  | Built-in             |
| Security          | Security Group    | Firewall             |
| Cost (approx)     | ~$50-150/month    | ~$5-20/month         |
| Notifications     | Lambda + SNS      | Not implemented      |

## Troubleshooting

### Can't connect to server
1. Check security group allows your IP:
   ```bash
   terraform show | grep -A 10 hcloud_firewall
   ```

2. Verify SSH key is correct:
   ```bash
   ssh-add -l
   cat ~/.ssh/aws.pub
   ```

3. Check server status in Hetzner Console

### Volume not mounting
1. Check volume is attached and mounted:
   ```bash
   ssh root@$(terraform output -raw hetzner_server_ip) "lsblk"
   ssh root@$(terraform output -raw hetzner_server_ip) "df -h /data"
   ```

2. Check mounting logs:
   ```bash
   ssh root@$(terraform output -raw hetzner_server_ip) "cat /var/log/volume-mount.log"
   ssh root@$(terraform output -raw hetzner_server_ip) "cat /var/log/volume-mount-error.log"
   ```

3. Manual mount if needed:
   ```bash
   ssh root@$(terraform output -raw hetzner_server_ip)
   # Then on the server:
   mkfs.ext4 /dev/sdb  # Only if new volume
   mkdir -p /data
   echo "/dev/sdb /data ext4 defaults,nofail 0 2" >> /etc/fstab
   mount -a
   ```

### Terraform errors
1. Make sure API token is set:
   ```bash
   echo $TF_VAR_hetzner_token
   ```

2. Re-initialize Terraform:
   ```bash
   terraform init -upgrade
   ```

## Mixed AWS + Hetzner Setup

You can run both AWS and Hetzner infrastructure simultaneously:

```bash
# Apply both
terraform apply

# Target specific provider
terraform apply -target=aws_instance.devbox          # AWS only
terraform apply -target=hcloud_server.devbox         # Hetzner only

# Destroy specific provider
terraform destroy -target=aws_instance.devbox        # AWS only
terraform destroy -target=hcloud_server.devbox       # Hetzner only
```

The hosts files are kept separate:
- `hosts-ec2` for AWS
- `hosts-hetzner` for Hetzner

## Next Steps

After provisioning:
1. Connect: `./connect hetzner`
2. Run Ansible: `./run-playbook.sh hetzner`
3. Your volume will be mounted at `/data`
4. All tools (conda, nvim, docker, etc.) will be installed

Enjoy your Hetzner dev box!
