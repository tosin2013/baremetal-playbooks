#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
  source .env
else
  echo "ERROR: .env file not found."
  exit 1
fi

# Define the path to the original hosts file
ORIGINAL_HOSTS_FILE="hosts"

# Define the path to the generated hosts file with overridden values
MODIFIED_HOSTS_FILE="modified_hosts"

# Create the modified hosts file with overridden values
awk -v new_host="$NEW_HOST" -v new_username="$NEW_USERNAME" \
  '{sub(/server.example.com/, new_host); sub(/admin/, new_username); print}' \
  "$ORIGINAL_HOSTS_FILE" > "$MODIFIED_HOSTS_FILE"

# Define the path to the secrets file
SECRETS_FILE="secrets.yml"

# Use yq to update ssh_public_key and ssh_private_key values in secrets.yml
yq e -i ".ssh_public_key = \"$SSH_PUBLIC_KEY\"" "$SECRETS_FILE"
yq e -i ".ssh_private_key = \"$SSH_PRIVATE_KEY\"" "$SECRETS_FILE"

# Run Ansible playbook using the modified hosts file and secrets file
ansible-playbook -i "$MODIFIED_HOSTS_FILE" playbooks/push-ssh-key.yaml -e "@$SECRETS_FILE"

# Clean up the modified hosts file (optional)
rm "$MODIFIED_HOSTS_FILE"
