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

#export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -euo pipefail

# Function to log messages
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

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
# Function to load environment variables
function load_env_vars {
  # Load environment variables from HCP Vault
  if [ "$1" == "--load-from-vault" ]; then
    if command -v hcp &> /dev/null; then
      echo "Loading environment variables from HCP Vault..."

      # Check if required environment variables are set
      if [ -z "${HCP_CLIENT_ID:-}" ] || [ -z "${HCP_CLIENT_SECRET:-}" ]; then
        echo "ERROR: HCP_CLIENT_ID or HCP_CLIENT_SECRET is not set."
        exit 1
      fi

      # Retrieve API token
      HCP_API_TOKEN=$(curl -s --fail https://auth.idp.hashicorp.com/oauth/token \
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
        secrets=$(curl -s --fail \
          --location "https://api.cloud.hashicorp.com/secrets/2023-06-13/organizations/$HCP_ORG_ID/projects/$HCP_PROJECT_ID/apps/$APP_NAME/open" \
          --request GET \
          --header "Authorization: Bearer $HCP_API_TOKEN")

        secret_value=$(echo "$secrets" | jq -r --arg var "$var" '.secrets[] | select(.name == $var) | .version.value')

        if [ -z "$secret_value" ]; then
          echo "WARNING: Secret $var not found in HCP Vault."
        else
          echo "Exporting $var from HCP Vault."
          echo "export $var=\"$secret_value\"" >> .env
          export $var="$secret_value"  # Also export to current shell
        fi

        # Step through each variable, show value, and wait for the user to press Enter
        # if [ -n "$secret_value" ]; then
        #   echo "Retrieved $var: $secret_value"
        #  read -p "Press Enter to continue..."
        # else
        #  echo "WARNING: Secret $var not found in HCP Vault."
        # fi
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
      while IFS='=' read -r key value || [ -n "$key" ]; do
        echo "Loaded $key: $value"
        read -p "Press Enter to continue..."
      done < .env
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

    local ansiblesafe_binary
    local ansiblesafe_url="https://github.com/tosin2013/ansiblesafe/releases/download/v0.0.12/ansiblesafe-v0.0.14-linux-amd64.tar.gz"

    if ! command -v ansiblesafe &>/dev/null; then
        log_message "Downloading ansiblesafe..."
        
        if ! curl -OL "$ansiblesafe_url"; then
            log_message "Failed to download ansiblesafe"
            exit 1
        fi
        
        if ! tar -zxvf "ansiblesafe-v0.0.14-linux-amd64.tar.gz"; then
            log_message "Failed to extract ansiblesafe"
            exit 1
        fi
        
        chmod +x ansiblesafe-linux-amd64

        # Check if /usr/local/bin is writable and accessible
        if [ -w /usr/local/bin ]; then
            log_message "Moving ansiblesafe to /usr/local/bin"
            mv ansiblesafe-linux-amd64 /usr/local/bin/ansiblesafe
            ansiblesafe_binary="/usr/local/bin/ansiblesafe"
        else
            log_message "/usr/local/bin is not accessible. Creating ~/.bin directory..."
            mkdir -p ~/.bin
            mv ansiblesafe-linux-amd64 ~/.bin/ansiblesafe
            ansiblesafe_binary="$HOME/.bin/ansiblesafe"
            export PATH="$HOME/.bin:$PATH"  # Add ~/.bin to PATH
        fi
    else
        # If ansiblesafe is already installed, get its location
        ansiblesafe_binary=$(command -v ansiblesafe)
    fi

    log_message "Using ansiblesafe binary at $ansiblesafe_binary"

    # Download and set up the ansible_vault_setup.sh script if not present
    if [ ! -f "ansible_vault_setup.sh" ]; then
        log_message "Downloading ansible_vault_setup.sh..."
        if ! curl -OL https://gist.githubusercontent.com/tosin2013/022841d90216df8617244ab6d6aceaf8/raw/92400b9e459351d204feb67b985c08df6477d7fa/ansible_vault_setup.sh; then
            log_message "Failed to download ansible_vault_setup.sh"
            exit 1
        fi
        chmod +x ansible_vault_setup.sh
    fi

    # Export required environment variables
    export HCP_CLIENT_ID="${HCP_CLIENT_ID}"
    export HCP_CLIENT_SECRET="${HCP_CLIENT_SECRET}"
    export HCP_ORG_ID=$(hcp profile display --format=json | jq -r .OrganizationID)
    export HCP_PROJECT_ID=$(hcp profile display --format=json | jq -r .ProjectID)
    export APP_NAME="${APP_NAME}"

    # Display pipeline variables file
    ls -lath vars/pipeline-variables.yaml
    pwd

    # Use ansiblesafe to decrypt the file
    if "$ansiblesafe_binary" -o 5 --file="vars/pipeline-variables.yaml"; then
        echo "$SSH_PASSWORD" > ~/.vault_password
        rm -f ~/.vault_password
    else
        log_message "Failed to configure Ansible Vault"
        exit 1
    fi

    # Display the pipeline variables YAML file content
    cat vars/pipeline-variables.yaml
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
    AWS_ACCESS_KEY
    AWS_SECRET_KEY
    KCLI_PIPELINES_RUNNER_TOKEN
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
  cat $key_file
  if ! ssh-keygen -lf "$key_file" > /dev/null 2>&1; then
    echo "ERROR: The private key in $key_file is invalid."
    exit 1
  fi
  echo "SSH private key in $key_file is valid."
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

load_env_vars --load-from-vault

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
echo $SSH_PUBLIC_KEY || exit 1
${YQ_COMMAND} e -i ".ssh_public_key = \"$(echo $SSH_PUBLIC_KEY)\"" "$SECRETS_FILE"
${YQ_COMMAND} e -i ".ssh_private_key = \"$(cat $SSH_PRIVATE_KEY_FILE)\"" "$SECRETS_FILE"

echo "Updated secrets.yml successfully."

# Use yq to update github-actions-vars.yml
echo "Updating github-actions-vars.yml..."
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

echo "Updated github-actions-vars.yml:"
cat "$GITHUB_ACTIONS_VARS_FILE"

# Use yq to update freeipa-vars.yml
echo "Updating freeipa-vars.yml..."
${YQ_COMMAND} e -i ".github_token = \"$KCLI_PIPELINES_GITHUB_TOKEN\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".freeipa_server_fqdn = \"$FREEIPA_SERVER_FQDN\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".freeipa_server_domain = \"$FREEIPA_SERVER_DOMAIN\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".freeipa_server_admin_password = \"$FREEIPA_SERVER_ADMIN_PASSWORD\"" "$FREEIPA_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$FREEIPA_VARS_FILE"


echo "Updated freeipa-vars.yml:"
cat "$FREEIPA_VARS_FILE"

# Use yq to update ocp-ai-svc-vars.yml
echo "Updating ocp-ai-svc-vars.yml..."
${YQ_COMMAND} e -i ".github_token = \"$OCP_AI_SVC_PIPELINES_GITHUB_TOKEN\"" "$OCP_AI_SVC_VARS_FILE"
${YQ_COMMAND} e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$OCP_AI_SVC_VARS_FILE"

echo "Updated ocp-ai-svc-vars.yml:"
cat "$OCP_AI_SVC_VARS_FILE"

# Update pipeline-variables.yaml with AWS credentials
echo "Updating pipeline-variables.yaml with AWS_ACCESS_KEY and AWS_SECRET_KEY..."
update_yaml_variable "$PIPELINES_VARS" "aws_access_key" "$AWS_ACCESS_KEY"
update_yaml_variable "$PIPELINES_VARS" "aws_secret_key" "$AWS_SECRET_KEY"

echo "Updated pipeline-variables.yaml with KCLI_PIPELINES_RUNNER_TOKEN credentials."
update_yaml_variable "$PIPELINES_VARS" "kcli_pipelines_runner_token" "$KCLI_PIPELINES_RUNNER_TOKEN"

echo "Updated pipeline-variables.yaml successfully:"
cat "$PIPELINES_VARS"


# Argument Parsing and Execution
for arg in "$@"; do
    case $arg in
        --push-ssh-key)
        run_ansible_playbook "playbooks/push-ssh-key.yaml" "$SECRETS_FILE" ""
        ;;
        --push-pipeline-vars)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/push-pipeline-variables.yaml -e "variables_file=$PIPELINES_VARS"
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
        --load-from-vault)
        load_env_vars --load-from-vault
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
