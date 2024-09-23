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
set -euo pipefail

# Function to display usage information
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

# Function to load environment variables
function load_env_vars {
  # Load environment variables from HCP Vault
  if [ "$1" == "--load-from-vault" ]; then
    if command -v hcp &> /dev/null; then
      echo "Loading environment variables from HCP Vault..."

      # Check if required environment variables are set
      if [ -z "$HCP_CLIENT_ID" ] || [ -z "$HCP_CLIENT_SECRET" ]; then
        echo "ERROR: HCP_CLIENT_ID or HCP_CLIENT_SECRET is not set."
        exit 1
      fi

      # Retrieve organization_id and project_id
      export HCP_ORG_ID=$(hcp profile display --format=json | jq -r .organization_id)
      export HCP_PROJECT_ID=$(hcp profile display --format=json | jq -r .project_id)
      export APP_NAME=$(hcp profile display --format=json | jq -r .vault_secrets.app)

      if [ -z "$HCP_ORG_ID" ] || [ -z "$HCP_PROJECT_ID" ] || [ -z "$APP_NAME" ]; then
        echo "ERROR: Could not retrieve organization_id, project_id, or app name."
        exit 1
      fi

      # Retrieve API token
      HCP_API_TOKEN=$(curl -s https://auth.idp.hashicorp.com/oauth/token \
        --data grant_type=client_credentials \
        --data client_id="$HCP_CLIENT_ID" \
        --data client_secret="$HCP_CLIENT_SECRET" \
        --data audience="https://api.hashicorp.cloud" | jq -r .access_token)

      if [ -z "$HCP_API_TOKEN" ]; then
        echo "ERROR: Failed to retrieve API token."
        exit 1
      fi

      # Loop to fetch and set secrets from HCP Vault Secrets
      for var in SSH_PUBLIC_KEY SSH_PRIVATE_KEY GITHUB_TOKEN KCLI_PIPELINES_GITHUB_TOKEN OCP_AI_SVC_PIPELINES_GITHUB_TOKEN; do
        # Fetch secret value from HCP Vault
        secret_value=$(curl -s \
          --location "https://api.cloud.hashicorp.com/secrets/2023-06-13/organizations/$HCP_ORG_ID/projects/$HCP_PROJECT_ID/apps/$APP_NAME/secrets/$var" \
          --header "Authorization: Bearer $HCP_API_TOKEN" | jq -r '.secrets[0].version.value')

        # Check if secret was fetched and append to .env file
        if [ -n "$secret_value" ]; then
          echo "Exporting $var from HCP Vault."
          echo "$var=$secret_value" >> .env
          export $var="$secret_value"  # Also export to current shell
        else
          echo "WARNING: Secret $var not found in HCP Vault."
        fi
      done

      # Load .env file into the current shell
      source .env
      configure_ansible_vault
    else
      echo "ERROR: HCP CLI is not installed."
      exit 1
    fi
  else
    # Load from local .env file
    if [ -f .env ]; then
      source .env
      configure_ansible_vault
    else
      echo "ERROR: .env file not found."
      exit 1
    fi
  fi
}


configure_ansible_vault() {
    log_message "Configuring Ansible Vault..."
    if ! command -v ansiblesafe &>/dev/null; then
        local ansiblesafe_url="https://github.com/tosin2013/ansiblesafe/releases/download/v0.0.12/ansiblesafe-v0.0.14-linux-amd64.tar.gz"
        if ! curl -OL "$ansiblesafe_url"; then
            log_message "Failed to download ansiblesafe"
            exit 1
        fi
        if ! tar -zxvf "ansiblesafe-v0.0.14-linux-amd64.tar.gz"; then
            log_message "Failed to extract ansiblesafe"
            exit 1
        fi
        chmod +x ansiblesafe-linux-amd64
        mv ansiblesafe-linux-amd64 /usr/local/bin/ansiblesafe
    fi
    if [ ! -f "ansible_vault_setup.sh" ]; then
        if ! curl -OL https://gist.githubusercontent.com/tosin2013/022841d90216df8617244ab6d6aceaf8/raw/92400b9e459351d204feb67b985c08df6477d7fa/ansible_vault_setup.sh; then
            log_message "Failed to download ansible_vault_setup.sh"
            exit 1
        fi
        chmod +x ansible_vault_setup.sh
    fi
    if /usr/local/bin/ansiblesafe -o 5  --file="vars/pipeline-variables.yaml"; then
        echo "$SSH_PASSWORD" > ~/.vault_password
        rm -f ~/.vault_password
    else
        log_message "Failed to configure Ansible Vault"
        exit 1
    fi
}


# Function to check required environment variables
function check_env_vars {
  required_vars=(
    SSH_PUBLIC_KEY
    SSH_PRIVATE_KEY
    GITHUB_TOKEN
    KCLI_PIPELINES_GITHUB_TOKEN
    OCP_AI_SVC_PIPELINES_GITHUB_TOKEN
    GUID
    OLLAMA
  )

  for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
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
  echo "SSH private key in $key_file is valid."
}

# Function to update individual YAML variables
function update_yaml_variable {
  local file="$1"
  local key="$2"
  local value="$3"

  # Escape double quotes and backslashes in the value to prevent YAML syntax issues
  local safe_value
  safe_value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')

  # Check if the value contains multiple lines
  if [[ "$value" == *$'\n'* ]]; then
    # Use block scalar for multi-line strings
    ${YQ_COMMAND} e -i ".${key} |= \"\"\"\n${value}\n\"\"\"" "$file" || {
      echo "ERROR: Failed to update ${key} in ${file}"
      exit 1
    }
  else
    ${YQ_COMMAND} e -i ".${key} = \"${safe_value}\"" "$file" || {
      echo "ERROR: Failed to update ${key} in ${file}"
      exit 1
    }
  fi

  echo "Updated ${key} in ${file}."
}

# Function to update pipeline-variables.yaml
function update_pipeline_variables_yaml {
  echo "Starting update_pipeline_variables_yaml function..."

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

    echo "Updating ${yaml_key} with value from ${env_var}"
    update_yaml_variable "$PIPELINES_VARS" "$yaml_key" "$env_value"
  done

  # Validate YAML syntax after updates
  echo "Validating YAML syntax for $PIPELINES_VARS..."
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

  echo "Finished update_pipeline_variables_yaml function."
}

# Function to debug pipeline variables
function debug_pipeline_vars {
  echo "Debugging pipeline-variables.yaml:"
  cat "$PIPELINES_VARS"
  exit 0
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

  echo "Files copied to $TARGET_HOST:$TARGET_DIR successfully."
}

# Function to reformat SSH private key (reused if necessary)
# Already defined earlier

# Function to validate SSH key file (reused if necessary)
# Already defined earlier

# Function to run Ansible playbooks
function run_ansible_playbook {
  local playbook="$1"
  local vars_file="$2"
  local extra_vars="$3"

  ansible-playbook -i "$ORIGINAL_HOSTS_FILE" "$playbook" -e "@$vars_file" $extra_vars || {
    echo "ERROR: Failed to execute playbook $playbook."
    exit 1
  }

  echo "Executed playbook $playbook successfully."
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
if command -v yq &> /dev/null; then
  echo 'yq is installed.' >&2
  YQ_COMMAND="yq"
elif [ -x "./yq" ]; then
  echo './yq is installed.' >&2
  YQ_COMMAND="./yq"
else
  echo 'Error: yq is not installed.' >&2
  exit 1
fi

# Load environment variables and update pipeline-variables.yaml if using Vault
USE_VAULT="${USE_VAULT:-false}"
if [ "$USE_VAULT" == "true" ]; then
  load_env_vars --load-from-vault
  echo "Environment Variables Loaded from Vault:"
  echo "rhsm_username=${rhsm_username}"
  echo "rhsm_password=${rhsm_password}"
  echo "rhsm_org=${rhsm_org}"
  echo "rhsm_activationkey=${rhsm_activationkey}"
  echo "admin_user_password=${admin_user_password}"
  echo "offline_token=${offline_token}"
  echo "openshift_pull_secret=${openshift_pull_secret}"
  echo "automation_hub_offline_token=${automation_hub_offline_token}"
  echo "freeipa_server_admin_password=${freeipa_server_admin_password}"
  echo "GITHUB_TOKEN=${GITHUB_TOKEN}"
  echo "KCLI_PIPELINES_GITHUB_TOKEN=${KCLI_PIPELINES_GITHUB_TOKEN}"
  echo "OCP_AI_SVC_PIPELINES_GITHUB_TOKEN=${OCP_AI_SVC_PIPELINES_GITHUB_TOKEN}"
  echo "pool_id=${pool_id}"
  echo "aws_access_key=${aws_access_key}"
  echo "aws_secret_key=${aws_secret_key}"
  echo "SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}"
  echo "SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}"
  echo "xrdp_remote_user=${xrdp_remote_user}"
  echo "xrdp_remote_user_password=${xrdp_remote_user_password}"
  update_pipeline_variables_yaml
else
  load_env_vars
fi

# Check if environment variables are loaded
check_env_vars

# Define the path to the original hosts file
ORIGINAL_HOSTS_FILE="hosts"

# Update the hosts file
echo "Updating hosts file with NEW_HOST and NEW_USERNAME..."
echo "$NEW_USERNAME" || exit $?
sed -i "/^\[github_servers\]/!b;n;c$NEW_HOST ansible_user=$NEW_USERNAME" "$ORIGINAL_HOSTS_FILE" || {
  echo "ERROR: Failed to update hosts file."
  exit 1
}

echo "Hosts file updated successfully."

# Reformat and validate the private key
SSH_PRIVATE_KEY_FILE="formatted_private_key.pem"
reformat_key "$SSH_PRIVATE_KEY" "$SSH_PRIVATE_KEY_FILE"
validate_key_file "$SSH_PRIVATE_KEY_FILE"

# Use yq to update secrets.yml
echo "Updating secrets.yml with SSH keys..."
update_yaml_variable "$SECRETS_FILE" "ssh_public_key" "$SSH_PUBLIC_KEY"
update_yaml_variable "$SECRETS_FILE" "ssh_private_key" "$(cat "$SSH_PRIVATE_KEY_FILE")"

echo "Updated secrets.yml successfully."

# Use yq to update github-actions-vars.yml
echo "Updating github-actions-vars.yml..."
update_yaml_variable "$GITHUB_ACTIONS_VARS_FILE" "github_token" "$GITHUB_TOKEN"
update_yaml_variable "$GITHUB_ACTIONS_VARS_FILE" "ssh_password" "$SSH_PASSWORD"
update_yaml_variable "$GITHUB_ACTIONS_VARS_FILE" "json_body.inputs.hostname" "$NEW_HOST"
update_yaml_variable "$GITHUB_ACTIONS_VARS_FILE" "json_body.inputs.domain" "$NEW_DOMAIN"
update_yaml_variable "$GITHUB_ACTIONS_VARS_FILE" "json_body.inputs.zone_name" "$NEW_DOMAIN"
update_yaml_variable "$GITHUB_ACTIONS_VARS_FILE" "json_body.inputs.guid" "$GUID"
update_yaml_variable "$GITHUB_ACTIONS_VARS_FILE" "json_body.inputs.forwarder" "$NEW_FORWARDER"
update_yaml_variable "$GITHUB_ACTIONS_VARS_FILE" "json_body.inputs.ollama" "$OLLAMA"

echo "Updated github-actions-vars.yml:"
cat "$GITHUB_ACTIONS_VARS_FILE"

# Use yq to update freeipa-vars.yml
echo "Updating freeipa-vars.yml..."
update_yaml_variable "$FREEIPA_VARS_FILE" "github_token" "$KCLI_PIPELINES_GITHUB_TOKEN"
update_yaml_variable "$FREEIPA_VARS_FILE" "freeipa_server_fqdn" "$FREEIPA_SERVER_FQDN"
update_yaml_variable "$FREEIPA_VARS_FILE" "freeipa_server_domain" "$FREEIPA_SERVER_DOMAIN"
update_yaml_variable "$FREEIPA_VARS_FILE" "freeipa_server_admin_password" "$FREEIPA_SERVER_ADMIN_PASSWORD"
update_yaml_variable "$FREEIPA_VARS_FILE" "json_body.inputs.hostname" "$NEW_HOST"

echo "Updated freeipa-vars.yml:"
cat "$FREEIPA_VARS_FILE"

# Use yq to update ocp-ai-svc-vars.yml
echo "Updating ocp-ai-svc-vars.yml..."
update_yaml_variable "$OCP_AI_SVC_VARS_FILE" "github_token" "$OCP_AI_SVC_PIPELINES_GITHUB_TOKEN"
update_yaml_variable "$OCP_AI_SVC_VARS_FILE" "json_body.inputs.hostname" "$NEW_HOST"

echo "Updated ocp-ai-svc-vars.yml:"
cat "$OCP_AI_SVC_VARS_FILE"

# Argument Parsing and Execution
for arg in "$@"; do
    case $arg in
        --push-ssh-key)
        run_ansible_playbook "playbooks/push-ssh-key.yaml" "$SECRETS_FILE" ""
        ;;
        --push-pipeline-vars)
        debug_pipeline_vars
        ;;
        --trigger-github-pipelines)
        run_ansible_playbook "playbooks/trigger-github-pipelines.yaml" "$GITHUB_ACTIONS_VARS_FILE" "-vv"
        ;;
        --copy-image)
        echo "Downloading images on target host..."
        ssh "${NEW_USERNAME}@${NEW_HOST}" "sudo kcli download image rhel8" || {
          echo "ERROR: Failed to download rhel8 image."
          exit 1
        }
        ssh "${NEW_USERNAME}@${NEW_HOST}" "sudo kcli download image rhel9" || {
          echo "ERROR: Failed to download rhel9 image."
          exit 1
        }
        echo "Images downloaded successfully."
        ;;
        --copy-files)
        copy_dir_files
        ;;
        --ipa-server)
        run_ansible_playbook "playbooks/trigger-github-pipelines.yaml" "$FREEIPA_VARS_FILE" ""
        ;;
        --ocp-ai-svc)
        run_ansible_playbook "playbooks/trigger-github-pipelines.yaml" "$OCP_AI_SVC_VARS_FILE" ""
        ;;
        --debug-pipeline-vars)
        debug_pipeline_vars
        ;;
        --help)
        usage
        ;;
        *)
        echo "ERROR: Unknown option $arg"
        usage
        ;;
    esac
    shift
done
