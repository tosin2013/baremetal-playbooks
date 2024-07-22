#!/bin/bash

# Check if the file argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <env_file>"
  exit 1
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

  # Push the key-value pair to Vault
  vault kv put "secret/env/$key" value="$value"
done < "$1"
