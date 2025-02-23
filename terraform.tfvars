ami = "ami-04b4f1a9cf54c11d0"  # Ubuntu 24.04, but get the latest by inspecting the AWS console
region = "us-east-1"
ssh_key_file = "~/.ssh/aws"
instance_type = "m7i.xlarge"   # NOTE: main.tf expects at least nvme storage
volume_name = "devboxdata"     # Volume expected to have been created and assigned tag Name=$volume_name
