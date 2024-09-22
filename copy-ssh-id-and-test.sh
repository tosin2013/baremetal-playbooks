#!/bin/bash 
# Define the remote hosts variables pass them as arguments 
# to the script
# Example: ./copy-ssh-id-and-test.sh root@example.com
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -x
if [ -z $1 ] || [ -z $2 ]; then
    echo "Please provide the remote host and username"
    echo "Example: ./copy-ssh-id-and-test.sh admin@example.com username"
    exit 1
fi

# Generate a ssh keypair for the user if it doesn't exist

if [ ! -f ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi

# Copy the ssh key to the remote host
if [ -z "$SSH_PASSWORD" ]; then
    echo "SSH_PASSWORD environment variable is not set"
    exit 1
fi

sshpass -p "$SSH_PASSWORD" ssh-copy-id -i ~/.ssh/id_rsa.pub -o StrictHostKeyChecking=no $2@$1
