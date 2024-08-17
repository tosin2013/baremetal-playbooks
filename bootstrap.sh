#!/bin/bash
# Usage: ./bootstrap.sh [--push-ssh-key] [--push-pipeline-vars] [--trigger-github-pipelines]
#export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

function load_env_vars {
  # Load environment variables from .env file or HCP Vault
  if [ "$1" == "--load-from-vault" ]; then
    if command -v hcp &> /dev/null; then
      echo "Loading environment variables from HCP Vault..."
      hcp profile init --vault-secrets
      for var in SSH_PUBLIC_KEY SSH_PRIVATE_KEY GITHUB_TOKEN KCLI_PIPELINES_GITHUB_TOKEN OCP_AI_SVC_PIPELINES_GITHUB_TOKEN; do
        if [ -z "${!var}" ]; then
          value=$(hcp vault-secrets secrets open ${var} --format=json | jq -r .static_version.value || exit 1)
          if [ -n "$value" ]; then
            export ${var}="$value"
          fi
        fi
      done
      source .env
    else
      echo "ERROR: HCP Vault CLI is not installed."
      exit 1
    fi
  elif [ -f .env ]; then
    source .env
  else
    echo "ERROR: .env file not found."
    exit 1
  fi
}

function check_env_vars {
  for var in SSH_PUBLIC_KEY SSH_PRIVATE_KEY GITHUB_TOKEN KCLI_PIPELINES_GITHUB_TOKEN OCP_AI_SVC_PIPELINES_GITHUB_TOKEN; do
    if [ -z "${!var}" ]; then
      echo "ERROR: Environment variable $var is not set."
      exit 1
    fi
  done
}

function reformat_key {
  local key="$1"
  local key_file="$2"

  # Remove any existing file with the same name
  rm -f "$key_file"

  # Use sed to remove the headers and footers
  key_content=$(echo "$key" | sed 's/-----BEGIN OPENSSH PRIVATE KEY-----//;s/-----END OPENSSH PRIVATE KEY-----//')

  # Add header to the key file
  echo "-----BEGIN OPENSSH PRIVATE KEY-----" > "$key_file"

  # Split the key content into lines of 64 characters and append to the file
  echo "$key_content" | tr -d ' ' | fold -w 64 >> "$key_file"

  # Add footer to the key file
  echo "-----END OPENSSH PRIVATE KEY-----" >> "$key_file"

  echo "Formatted key saved to $key_file:"
  cat "$key_file"
}


function validate_key_file {
  local key_file="$1"
  if ! ssh-keygen -lf "$key_file" > /dev/null 2>&1; then
    echo "ERROR: The private key in $key_file is invalid."
    exit 1
  fi
}

function usage {
    echo "Usage: $0 [--push-ssh-key] [--push-pipeline-vars] [--trigger-github-pipelines] [--copy-image] [--copy-files] [--ipa-server] [--ocp-ai-svc] [--load-from-vault]"
    echo "End-to-End: $0 --push-ssh-key --push-pipeline-vars --trigger-github-pipelines"
    echo "Download Image: $0 --copy-image"
    echo "Copy Files: $0 --copy-files"
    echo "FreeIPA Server: $0 --ipa-server"
    echo "OCP AI Service: $0 --ocp-ai-svc"
    echo "Load from Vault: $0 --load-from-vault"
    exit 1
}

function copy_dir_files {
  # Define the target host and directory
  TARGET_HOST="${NEW_USERNAME}@${NEW_HOST}"
  TARGET_DIR="/tmp/baremetal-playbooks"

  # Copy files using SSH
  ssh "$TARGET_HOST" "mkdir -p $TARGET_DIR"
  scp files/* "$TARGET_HOST:$TARGET_DIR"
}

# If no arguments are provided, display usage
if [ $# -eq 0 ]; then
    usage
fi


# Define the path to the secrets file
SECRETS_FILE="vars/secrets.yml"
PIPELINES_VARS="$(pwd)/vars/pipeline-variables.yaml"
GITHUB_ACTIONS_VARS_FILE="vars/github-actions-vars.yml"
FREEIPA_VARS_FILE="vars/freeipa-vars.yml"
OCP_AI_SVC_VARS_FILE="vars/ocp4-ai-svc-universal.yml"

# Check for yq installation
if [ -x "$(command -v yq)" ]; then
  echo 'yq is installed.' >&2
  YQ_COMMAND="yq"
elif [ -x "$(command -v ./yq)" ]; then
  echo './yq is installed.' >&2
  YQ_COMMAND="./yq"
else
  echo 'Error: yq is not installed.' >&2
  exit 1
fi

# Load environment variables
if [ "$USE_VAULT" == "true" ]; then
  load_env_vars --load-from-vault
else
  load_env_vars
fi

# Check if environment variables are loaded
check_env_vars

# Define the path to the original hosts file
ORIGINAL_HOSTS_FILE="hosts"

# Use sed to update line two of the [github_servers] group in the hosts file
echo $NEW_USERNAME || exit $?
sed -i "/^\[github_servers\]/!b;n;c$NEW_HOST ansible_user=$NEW_USERNAME" "$ORIGINAL_HOSTS_FILE"

# Reformat and validate the private key
SSH_PRIVATE_KEY_FILE="formatted_private_key.pem"
reformat_key "$SSH_PRIVATE_KEY" "$SSH_PRIVATE_KEY_FILE"
validate_key_file "$SSH_PRIVATE_KEY_FILE"


# Use yq to update ssh_public_key and ssh_private_key values in secrets.yml
echo $SSH_PUBLIC_KEY || exit 1
${YQ_COMMAND} e -i ".ssh_public_key = \"$(echo $SSH_PUBLIC_KEY)\"" "$SECRETS_FILE"
${YQ_COMMAND} e -i ".ssh_private_key = \"$(cat $SSH_PRIVATE_KEY_FILE)\"" "$SECRETS_FILE"

# Use yq to update github_token, ssh_password, and json_body variables in github-actions-vars.yml
${YQ_COMMAND} e -i ".github_token = \"$GITHUB_TOKEN\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".ssh_password = \"$SSH_PASSWORD\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.domain = \"$NEW_DOMAIN\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.zone_name = \"$NEW_DOMAIN\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.guid = \"$GUID\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.forwarder = \"$NEW_FORWARDER\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.ollama = \"$OLLAMA\"" "$GITHUB_ACTIONS_VARS_FILE"
cat $GITHUB_ACTIONS_VARS_FILE

# Use yq to update github_token in freeipa-vars.yml
${YQ_COMMAND} e -i ".github_token = \"$KCLI_PIPELINES_GITHUB_TOKEN\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".freeipa_server_fqdn = \"$FREEIPA_SERVER_FQDN\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".freeipa_server_domain = \"$FREEIPA_SERVER_DOMAIN\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".freeipa_server_admin_password = \"$FREEIPA_SERVER_ADMIN_PASSWORD\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$FREEIPA_VARS_FILE"

cat $FREEIPA_VARS_FILE

# Use yq to update github_token in ocp-ai-svc-vars.yml
${YQ_COMMAND} e -i ".github_token = \"$OCP_AI_SVC_PIPELINES_GITHUB_TOKEN\"" "$OCP_AI_SVC_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$OCP_AI_SVC_VARS_FILE"

cat $OCP_AI_SVC_VARS_FILE

for arg in "$@"; do
    case $arg in
        --push-ssh-key)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/push-ssh-key.yaml -e "@$SECRETS_FILE"
        ;;
        --push-pipeline-vars)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/push-pipeline-variables.yaml -e "variables_file=$PIPELINES_VARS" || exit $?
        ;;
        --trigger-github-pipelines)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/trigger-github-pipelines.yaml -e "@$GITHUB_ACTIONS_VARS_FILE" -vv || exit $?
        ;;
        --copy-image)
        ssh "${NEW_USERNAME}@${NEW_HOST}" "sudo kcli download image rhel8"
        ssh "${NEW_USERNAME}@${NEW_HOST}" "sudo kcli download image rhel9"
        ;;
        --copy-files)
        copy_dir_files
        ;;
        --ipa-server)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/trigger-github-pipelines.yaml -e "@$FREEIPA_VARS_FILE"
        ;;
        --ocp-ai-svc)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/trigger-github-pipelines.yaml -e "@$OCP_AI_SVC_VARS_FILE"
        ;;
        *)
        usage
        ;;
    esac
    shift
done
