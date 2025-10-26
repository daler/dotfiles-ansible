region = "us-east-1"
ssh_key_file = "~/.ssh/aws"

# About $0.20 an hour on demand.
# NOTE: main.tf expects at least nvme storage support.
instance_type = "m7i.xlarge"

# Volume expected to have been created already, and assigned tag Name=$volume_name (e.g., Name=devboxdata)
volume_name = "devboxdata"

# How often to check if the instance is running and send an email
notification_rate = "rate(6 hours)"
