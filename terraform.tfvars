region = "us-east-1"
ssh_key_file = "~/.ssh/aws"
instance_type = "m7i.xlarge"   # NOTE: main.tf expects at least nvme storage
volume_name = "devboxdata"     # Volume expected to have been created and assigned tag Name=$volume_name
