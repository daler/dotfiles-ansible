#!/bin/bash

[ -z $EC2_PEM ] && echo 'Missing $EC2_PEM (.pem that instance was created with)' && exit 1
ansible-playbook playbook.yaml -i hosts --private-key $EC2_PEM -u ubuntu
