#!/bin/bash

# Check if the file argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <env_file> [--login]"
  exit 1
fi

# Check if Vault CLI is installed
if ! command -v vault &> /dev/null; then
  echo "Vault CLI is not installed. Installing..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install vault
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt-get update && sudo apt-get install -y vault
  elif [[ -f /etc/redhat-release ]]; then
    sudo yum install -y vault
  else
    echo "Unsupported OS. Please install Vault CLI manually."
    exit 1
  fi
fi

# Check if the --login flag is provided
if [ "$2" == "--login" ]; then
  echo "Logging into Vault..."
  vault login
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
