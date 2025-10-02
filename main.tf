terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}
variable "region" { type = string }
variable "ssh_key_file" { type = string }
variable "instance_type" { type = string }
variable "volume_name" { type = string }
variable "EC2_LOGIN_KEY" { type = string }

provider "aws" {
  region = var.region
}

# Will be copied to the instance so you can ssh in
resource "aws_key_pair" "ssh_key" {
  key_name   = "ssh-key"
  public_key = file("${var.EC2_LOGIN_KEY}.pub")
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical's AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}


# Create VPC, public subnet, and gateway so we can ssh in
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true  # so we can ssh in
  tags = {
    Name = "public"
  }
}

# In order for networking to work, need a gateway, a route table that points to
# that gateway, and assign that route table to the public subnet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.main.id
}

# Security group for SSH
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "devbox" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.ssh_key.key_name

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
  associate_public_ip_address = true

  # Auto mount volume
  user_data = <<-EOF
              #!/bin/bash
              # Wait for the EBS volume to be attached
              while [ ! -e /dev/nvme1n1 ]; do sleep 1; done

              # Create filesystem if it doesn't exist
              if ! file -s /dev/nvme1n1 | grep -q filesystem; then
                mkfs -t ext4 /dev/nvme1n1
              fi

              # Create mount point and add to fstab
              mkdir -p /data
              if ! grep -q nvme1n1 /etc/fstab; then
                echo '/dev/nvme1n1 /data ext4 defaults,nofail 0 2' >> /etc/fstab
              fi
              mount -a
              EOF
  tags = {
    Name = "example-instance"
  }
}

# Assumes you've already created this volume.
# The volume is purposefully not configured here, because `terraform destroy`
# would delete it and the goal is to keep it persistent
data "aws_ebs_volume" "devboxdata" {
  filter {
    name   = "tag:Name"
    values = [var.volume_name]
  }
  most_recent = true
}

resource "aws_volume_attachment" "ebs_attachment" {
  device_name = "/dev/sdf"
  volume_id   = data.aws_ebs_volume.devboxdata.id
  instance_id = aws_instance.devbox.id
}

# Output the public IP so we can connect
output "instance_public_ip" {
  value = aws_instance.devbox.public_ip
}

resource "local_file" "instance_id" {
  content = "${aws_instance.devbox.id}"
  file_permission = "0600"
  filename = "${path.module}/.instance_id"
}

resource "local_file" "hosts" {
  content = "[ec2]\n${aws_instance.devbox.public_ip}\n"
  file_permission = "0600"
  filename = "${path.module}/hosts"
}

# vim: ft=hcl
