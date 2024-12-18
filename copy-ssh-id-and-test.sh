#!/bin/bash

# manage-ssh-key.sh
# Usage: ./manage-ssh-key.sh username host

set -euo pipefail
IFS=$'\n\t'

# Function to display usage
usage() {
    echo "Usage: $0 username host"
    echo "Example: $0 lab-user 192.168.100.10"
    exit 1
}

# Function for logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Check for required arguments
if [ "$#" -ne 2 ]; then
    usage
fi

USERNAME="$1"
HOST="$2"

# Ensure SSH_PASSWORD is set
if [ -z "${SSH_PASSWORD:-}" ]; then
    log "Error: SSH_PASSWORD environment variable is not set."
    exit 1
fi

# Path to SSH keys
SSH_DIR="$HOME/.ssh"
PRIVATE_KEY="$SSH_DIR/id_rsa"
PUBLIC_KEY="$SSH_DIR/id_rsa.pub"

# Generate SSH key pair if not exists
if [ ! -f "$PUBLIC_KEY" ]; then
    log "SSH public key not found. Generating a new RSA SSH key pair..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    ssh-keygen -t rsa -b 4096 -N "" -f "$PRIVATE_KEY" >/dev/null 2>&1
    log "SSH key pair generated."
else
    log "SSH public key already exists."
fi

# Extract key type and key data from the public key
KEY_TYPE=$(awk '{print $1}' "$PUBLIC_KEY")
KEY_DATA=$(awk '{print $2}' "$PUBLIC_KEY")

# Function to remove existing instances of the SSH key on the remote host
remove_existing_key() {
    log "Ensuring .ssh directory and authorized_keys file exist on remote host..."

    # Create .ssh directory if it doesn't exist
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "${USERNAME}@${HOST}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

    # Create authorized_keys file if it doesn't exist
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "${USERNAME}@${HOST}" "touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

    log "Backing up existing authorized_keys on remote host..."
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "${USERNAME}@${HOST}" "cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak || true"

    log "Checking if the SSH key exists on remote host..."
    KEY_EXISTS=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "${USERNAME}@${HOST}" "grep '^${KEY_TYPE} ${KEY_DATA}' ~/.ssh/authorized_keys" || true)

    if [ -n "$KEY_EXISTS" ]; then
        log "SSH key exists on remote host. Removing it..."
        # Use sed to delete the specific SSH key based on key type and key data
        REMOVE_KEY_CMD="sed -i '/^${KEY_TYPE} ${KEY_DATA}/d' ~/.ssh/authorized_keys"
        if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "${USERNAME}@${HOST}" "$REMOVE_KEY_CMD"; then
            log "Existing SSH key removed from remote host."
        else
            log "Error: Failed to remove existing SSH key from remote host."
            exit 1
        fi
    else
        log "SSH key does not exist on remote host. No removal needed."
    fi
}

# Function to copy SSH key using sshpass and ssh-copy-id
copy_ssh_key() {
    log "Copying SSH key to remote host..."
    if sshpass -p "$SSH_PASSWORD" ssh-copy-id -i "$PUBLIC_KEY" -o StrictHostKeyChecking=no "${USERNAME}@${HOST}"; then
        log "SSH key successfully copied."
    else
        log "Error: Failed to copy SSH key to remote host."
        exit 1
    fi
}

# Function to test SSH connection
test_ssh_connection() {
    log "Testing SSH connection..."
    if ssh -i "$PRIVATE_KEY" -o BatchMode=yes -o ConnectTimeout=5 "${USERNAME}@${HOST}" 'echo "SSH connection successful."'; then
        log "SSH connection to ${HOST} as ${USERNAME} is successful."
    else
        log "Error: SSH connection to ${HOST} as ${USERNAME} failed."
        exit 1
    fi
}

# Main Logic
remove_existing_key
copy_ssh_key
test_ssh_connection