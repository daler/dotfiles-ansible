region = "us-east-1"
ssh_key_file = "~/.ssh/aws"
instance_type = "m7i.xlarge"   # NOTE: main.tf expects at least nvme storage

# Volume expected to have been created already, and assigned tag Name=$volume_name (e.g., Name=devboxdata)
volume_name = "devboxdata" 

# How often to check if the instance is running and send an email
notification_rate = "rate(6 hours)"
