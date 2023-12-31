#!/bin/bash 
# Define the remote hosts variables pass them as arguments 
# to the script
# Example: ./copy-ssh-id-and-test.sh root@example.com
if [ -z $1 ]; then
    echo "Please provide the remote host"
    echo "Example: ./copy-ssh-id-and-test.sh admin@example.com"
    exit 1
fi

# Generate a ssh keypair for the user if it doesn't exist

if [ ! -f ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi

# Copy the ssh key to the remote host
ssh-copy-id -i ~/.ssh/id_rsa.pub $1