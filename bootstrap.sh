#!/bin/bash
# Usage: ./bootstrap.sh [OPTIONS]
# Options:
#   --push-ssh-key             Push SSH keys to the target servers.
#   --push-pipeline-vars       Update and push pipeline variables.
#   --trigger-github-pipelines Trigger GitHub pipelines.
#   --copy-image               Download specific images on the target host.
#   --copy-files               Copy necessary files to the target host.
#   --ipa-server               Configure FreeIPA server settings.
#   --ocp-ai-svc               Configure OCP AI Service settings.
#   --load-from-vault          Load environment variables from HCP Vault.
#   --debug-pipeline-vars      Debug the pipeline variables YAML file.
#   --help                     Display usage information.

export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -x

# Function to load environment variables
function load_env_vars {
  if [ "$1" == "--load-from-vault" ]; then
    if command -v hcp &> /dev/null; then
      echo "Loading environment variables from HCP Vault..."
      hcp profile init --vault-secrets
      for var in SSH_PUBLIC_KEY SSH_PRIVATE_KEY GITHUB_TOKEN KCLI_PIPELINES_GITHUB_TOKEN OCP_AI_SVC_PIPELINES_GITHUB_TOKEN GUID OLLAMA; do
        if [ -z "${!var}" ]; then
          value=$(hcp vault-secrets secrets open ${var} --format=json --app=qubinode-env-files | jq -r .static_version.value || exit 1)
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
  else
    if [ -f .env ]; then
      source .env
    else
      echo "ERROR: .env file not found."
      exit 1
    fi
  fi
}

# Function to check required environment variables
function check_env_vars {
  for var in SSH_PUBLIC_KEY SSH_PRIVATE_KEY GITHUB_TOKEN KCLI_PIPELINES_GITHUB_TOKEN OCP_AI_SVC_PIPELINES_GITHUB_TOKEN GUID OLLAMA; do
    if [ -z "${!var}" ]; then
      echo "ERROR: Environment variable $var is not set."
      exit 1
    fi
  done
}

# Function to reformat SSH private key
function reformat_key {
  local key="$1"
  local key_file="$2"

  rm -f "$key_file"

  key_content=$(echo "$key" | sed 's/-----BEGIN OPENSSH PRIVATE KEY-----//;s/-----END OPENSSH PRIVATE KEY-----//')

  echo "-----BEGIN OPENSSH PRIVATE KEY-----" > "$key_file"
  echo "$key_content" | tr -d ' ' | fold -w 64 >> "$key_file"
  echo "-----END OPENSSH PRIVATE KEY-----" >> "$key_file"

  echo "Formatted key saved to $key_file:"
  cat "$key_file"
}

# Function to validate SSH key file
function validate_key_file {
  local key_file="$1"
  if ! ssh-keygen -lf "$key_file" > /dev/null 2>&1; then
    echo "ERROR: The private key in $key_file is invalid."
    exit 1
  fi
}

# Function to display usage
function usage {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --push-ssh-key             Push SSH keys to the target servers."
    echo "  --push-pipeline-vars       Update and push pipeline variables."
    echo "  --trigger-github-pipelines Trigger GitHub pipelines."
    echo "  --copy-image               Download specific images on the target host."
    echo "  --copy-files               Copy necessary files to the target host."
    echo "  --ipa-server               Configure FreeIPA server settings."
    echo "  --ocp-ai-svc               Configure OCP AI Service settings."
    echo "  --load-from-vault          Load environment variables from HCP Vault."
    echo "  --debug-pipeline-vars      Debug the pipeline variables YAML file."
    echo "  --help                     Display usage information."
    echo ""
    echo "Examples:"
    echo "  End-to-End Setup:"
    echo "    $0 --push-ssh-key --push-pipeline-vars --trigger-github-pipelines"
    echo "  Download Images:"
    echo "    $0 --copy-image"
    echo "  Copy Files:"
    echo "    $0 --copy-files"
    echo "  Configure FreeIPA Server:"
    echo "    $0 --ipa-server"
    echo "  Configure OCP AI Service:"
    echo "    $0 --ocp-ai-svc"
    echo "  Load Environment Variables from Vault:"
    echo "    $0 --load-from-vault"
    echo "  Debug Pipeline Variables:"
    echo "    $0 --debug-pipeline-vars"
    exit 1
}

# Function to debug pipeline variables
function debug_pipeline_vars {
  echo "Debugging pipeline-variables.yaml:"
  cat "$PIPELINES_VARS"
  exit 1
}

# Function to copy files to target host
function copy_dir_files {
  TARGET_HOST="${NEW_USERNAME}@${NEW_HOST}"
  TARGET_DIR="/tmp/baremetal-playbooks"

  ssh "$TARGET_HOST" "mkdir -p $TARGET_DIR" || {
    echo "ERROR: Failed to create directory $TARGET_DIR on $TARGET_HOST"
    exit 1
  }

  scp files/* "$TARGET_HOST:$TARGET_DIR" || {
    echo "ERROR: Failed to copy files to $TARGET_HOST:$TARGET_DIR"
    exit 1
  }
}

# Function to update individual YAML variables
function update_yaml_variable {
  local file="$1"
  local key="$2"
  local value="$3"

  # Escape double quotes and backslashes in the value to prevent YAML syntax issues
  local safe_value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')

  ${YQ_COMMAND} e -i ".${key} = \"${safe_value}\"" "$file" || {
    echo "ERROR: Failed to update ${key} in ${file}"
    exit 1
  }
}

# Function to update pipeline-variables.yaml
function update_pipeline_variables_yaml {
  echo "Updating pipeline-variables.yaml with environment variables..."

  declare -A vars_to_update=(
    ["rhsm_username"]="rhsm_username"
    ["rhsm_password"]="rhsm_password"
    ["rhsm_org"]="rhsm_org"
    ["rhsm_activationkey"]="rhsm_activationkey"
    ["admin_user_password"]="admin_user_password"
    ["offline_token"]="offline_token"
    ["openshift_pull_secret"]="openshift_pull_secret"
    ["automation_hub_offline_token"]="automation_hub_offline_token"
    ["freeipa_server_admin_password"]="freeipa_server_admin_password"
    ["GITHUB_TOKEN"]="GITHUB_TOKEN"
    ["KCLI_PIPELINES_GITHUB_TOKEN"]="KCLI_PIPELINES_GITHUB_TOKEN"
    ["OCP_AI_SVC_PIPELINES_GITHUB_TOKEN"]="OCP_AI_SVC_PIPELINES_GITHUB_TOKEN"
    ["pool_id"]="pool_id"
    ["aws_access_key"]="aws_access_key"
    ["aws_secret_key"]="aws_secret_key"
    ["SSH_PUBLIC_KEY"]="SSH_PUBLIC_KEY"
    ["SSH_PRIVATE_KEY"]="SSH_PRIVATE_KEY"
    ["xrdp_remote_user"]="xrdp_remote_user"
    ["xrdp_remote_user_password"]="xrdp_remote_user_password"
  )

  for yaml_key in "${!vars_to_update[@]}"; do
    env_var="${vars_to_update[$yaml_key]}"
    env_value="${!env_var}"

    if [ -z "${env_value:-}" ]; then
      echo "WARNING: Environment variable ${env_var} is not set. Skipping update for ${yaml_key}."
      continue
    fi

    update_yaml_variable "$PIPELINES_VARS" "$yaml_key" "$env_value"
  done

  # Validate YAML syntax after updates
  if ! ${YQ_COMMAND} e . "$PIPELINES_VARS" > /dev/null 2>&1; then
    echo "ERROR: Invalid YAML syntax in $PIPELINES_VARS after updates."
    exit 1
  fi

  echo "pipeline-variables.yaml updated successfully."

  # Secure the YAML file
  chmod 600 "$PIPELINES_VARS" || {
    echo "ERROR: Failed to set permissions on $PIPELINES_VARS"
    exit 1
  }
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

# Load environment variables and update pipeline-variables.yaml if using Vault
if [ "$USE_VAULT" == "true" ]; then
  load_env_vars --load-from-vault
  update_pipeline_variables_yaml
else
  load_env_vars
fi

# Check if environment variables are loaded
check_env_vars

# Define the path to the original hosts file
ORIGINAL_HOSTS_FILE="hosts"

# Update the hosts file
echo "$NEW_USERNAME" || exit $?
sed -i "/^\[github_servers\]/!b;n;c$NEW_HOST ansible_user=$NEW_USERNAME" "$ORIGINAL_HOSTS_FILE"

# Reformat and validate the private key
SSH_PRIVATE_KEY_FILE="formatted_private_key.pem"
reformat_key "$SSH_PRIVATE_KEY" "$SSH_PRIVATE_KEY_FILE"
validate_key_file "$SSH_PRIVATE_KEY_FILE"

# Use yq to update secrets.yml
echo "$SSH_PUBLIC_KEY" || exit 1
${YQ_COMMAND} e -i ".ssh_public_key = \"$(echo "$SSH_PUBLIC_KEY")\"" "$SECRETS_FILE"
${YQ_COMMAND} e -i ".ssh_private_key = \"$(cat "$SSH_PRIVATE_KEY_FILE")\"" "$SECRETS_FILE"

# Use yq to update github-actions-vars.yml
${YQ_COMMAND} e -i ".github_token = \"$GITHUB_TOKEN\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".ssh_password = \"$SSH_PASSWORD\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.domain = \"$NEW_DOMAIN\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.zone_name = \"$NEW_DOMAIN\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.guid = \"$GUID\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.forwarder = \"$NEW_FORWARDER\"" "$GITHUB_ACTIONS_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.ollama = \"$OLLAMA\"" "$GITHUB_ACTIONS_VARS_FILE"
cat "$GITHUB_ACTIONS_VARS_FILE"

# Use yq to update freeipa-vars.yml
${YQ_COMMAND} e -i ".github_token = \"$KCLI_PIPELINES_GITHUB_TOKEN\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".freeipa_server_fqdn = \"$FREEIPA_SERVER_FQDN\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".freeipa_server_domain = \"$FREEIPA_SERVER_DOMAIN\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".freeipa_server_admin_password = \"$FREEIPA_SERVER_ADMIN_PASSWORD\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$FREEIPA_VARS_FILE"
cat "$FREEIPA_VARS_FILE"

# Use yq to update ocp-ai-svc-vars.yml
${YQ_COMMAND} e -i ".github_token = \"$OCP_AI_SVC_PIPELINES_GITHUB_TOKEN\"" "$OCP_AI_SVC_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$OCP_AI_SVC_VARS_FILE"
cat "$OCP_AI_SVC_VARS_FILE"

# Argument Parsing and Execution
for arg in "$@"; do
    case $arg in
        --push-ssh-key)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/push-ssh-key.yaml -e "@$SECRETS_FILE"
        ;;
        --push-pipeline-vars)
        debug_pipeline_vars
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/push-pipeline-variables.yaml -e "variables_file=$PIPELINES_VARS" -vvv || exit $?
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
        --debug-pipeline-vars)
        # This flag will be handled in the --push-pipeline-vars case
        ;;
        *)
        usage
        ;;
    esac
    shift
done
