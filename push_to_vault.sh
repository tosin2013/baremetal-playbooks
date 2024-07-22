#!/bin/bash

# Check if the file argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <env_file> [--login]"
  exit 1
fi

# Check if HCP Vault CLI is installed

# Check if the --login flag is provided
if [ "$2" == "--login" ]; then
  echo "Logging into HCP Vault..."
  hcp vault-secrets login
fi

# Read the env file line by line
while IFS= read -r line; do
  # Skip comments and empty lines
  if [[ "$line" =~ ^# ]] || [[ "$line" =~ ^$ ]]; then
    continue
  fi

  # Extract the key and value
  key=$(echo "$line" | cut -d'=' -f1)
  value=$(echo "$line" | cut -d'=' -f2-)

  # Push the key-value pair to HCP Vault
  hcp vault-secrets secrets put "secret/env/$key" value="$value"
done < "$1"
