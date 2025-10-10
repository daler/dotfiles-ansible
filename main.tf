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
variable "notification_rate" { type = string }

# These are expected to be environment variables with the TF_VAR_ prefix, e.g.,
# TF_VAR_EC2_LOGIN_KEY and TF_VAR_NOTIFICATION_EMAIL
variable "EC2_LOGIN_KEY" { type = string }
variable "NOTIFICATION_EMAIL" { type = string }

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

# ===== NOTIFICATION SYSTEM =====

# SNS Topic for notifications
resource "aws_sns_topic" "instance_alert" {
  name = "instance-uptime-alert"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.instance_alert.arn
  protocol  = "email"
  endpoint  = var.NOTIFICATION_EMAIL
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-instance-check-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "check_instance" {
  filename      = "lambda_function.zip"
  function_name = "check-instance-uptime"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30
  source_code_hash = filebase64sha256("lambda_function.zip")

  environment {
    variables = {
      INSTANCE_ID   = aws_instance.devbox.id
      SNS_TOPIC_ARN = aws_sns_topic.instance_alert.arn
    }
  }
}

# EventBridge Rule - Every 6 hours
resource "aws_cloudwatch_event_rule" "every_6_hours" {
  name                = "check-instance-every-6-hours"
  description         = "Trigger every 6 hours"
  schedule_expression = var.notification_rate
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.every_6_hours.name
  target_id = "CheckInstanceLambda"
  arn       = aws_lambda_function.check_instance.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.check_instance.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_6_hours.arn
}

# ===== OUTPUTS =====

# Output the public IP so we can connect
output "instance_public_ip" {
  value = aws_instance.devbox.public_ip
}

output "instance_id" {
  value = aws_instance.devbox.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.instance_alert.arn
}

resource "local_file" "instance_id" {
  content         = aws_instance.devbox.id
  file_permission = "0600"
  filename        = "${path.module}/.instance_id"
}

resource "local_file" "hosts" {
  content         = "[ec2]\n${aws_instance.devbox.public_ip}\n"
  file_permission = "0600"
  filename        = "${path.module}/hosts"
}

# vim: ft=hcl
