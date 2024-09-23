#!/bin/bash

# Enhanced Script to Copy RSA SSH Key to Remote Host if Not Present
# Usage: ./copy-ssh-id-and-test.sh username host

set -euo pipefail
IFS=$'\n\t'

# Enable debugging if needed
# export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
# set -x

# Function to display usage
usage() {
    echo "Usage: $0 username host"
    echo "Example: $0 admin example.com"
    exit 1
}

# Check for required arguments
if [ "$#" -ne 2 ]; then
    usage
fi

USERNAME="$1"
HOST="$2"

# Path to SSH keys
SSH_DIR="$HOME/.ssh"
PRIVATE_KEY="$SSH_DIR/id_rsa"
PUBLIC_KEY="$SSH_DIR/id_rsa.pub"

# Generate SSH key pair if not exists
if [ ! -f "$PUBLIC_KEY" ]; then
    echo "SSH public key not found. Generating a new RSA SSH key pair..."
    ssh-keygen -t rsa -b 4096 -N "" -f "$PRIVATE_KEY"
fi

# Function to check if the public key is already in authorized_keys on remote host
key_exists_on_remote() {
    ssh -o BatchMode=yes -o ConnectTimeout=5 "${USERNAME}@${HOST}" "grep -F \"$(cat ${PUBLIC_KEY})\" ~/.ssh/authorized_keys" &>/dev/null
}

# Function to copy SSH key using ssh-copy-id
copy_ssh_key() {
    if command -v sshpass >/dev/null 2>&1; then
        if [ -z "${SSH_PASSWORD:-}" ]; then
            echo "SSH_PASSWORD environment variable is not set. Unable to use sshpass."
            exit 1
        fi
        sshpass -p "$SSH_PASSWORD" ssh-copy-id -i "$PUBLIC_KEY" -o StrictHostKeyChecking=no "${USERNAME}@${HOST}"
    else
        # If sshpass is not available, prompt the user to enter the password
        ssh-copy-id -i "$PUBLIC_KEY" -o StrictHostKeyChecking=no "${USERNAME}@${HOST}"
    fi
}

# Main Logic
if key_exists_on_remote; then
    echo "SSH key is already present on the remote host. Skipping ssh-copy-id."
else
    echo "SSH key not found on remote host. Copying SSH key..."
    copy_ssh_key
    echo "SSH key successfully copied."
fi

# Optional: Test SSH connection
if ssh -o BatchMode=yes -o ConnectTimeout=5 "${USERNAME}@${HOST}" 'echo "SSH connection successful."' ; then
    echo "SSH connection to ${HOST} as ${USERNAME} is successful."
else
    echo "SSH connection to ${HOST} as ${USERNAME} failed."
    exit 1
fi
