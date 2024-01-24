#!/bin/bash
# Usage: ./bootstrap.sh [--push-ssh-key] [--push-pipeline-vars] [--trigger-github-pipelines]
set -x 
# Load environment variables from .env file
if [ -f .env ]; then
  source .env
else
  echo "ERROR: .env file not found."
  exit 1
fi

function usage {
    echo "Usage: $0 [--push-ssh-key] [--push-pipeline-vars] [--trigger-github-pipelines] [--copy-image] [--ipa-server]"
    echo "End-to-End: $0 --push-ssh-key --push-pipeline-vars --trigger-github-pipelines"
    echo "Download Image: $0 --copy-image"
    exit 1
}

function copy_dir_files {
  # Define the target host and directory
  TARGET_HOST="${NEW_USERNAME}@${NEW_HOST}"
  TARGET_DIR="/tmp/baremetal-playbooks"

  # Copy files using SSH
  ssh $TARGET_HOST "mkdir -p $TARGET_DIR"
  scp files/* $TARGET_HOST:$TARGET_DIR
}

if [ $# -eq 0 ]; then
    usage
fi

# Define the path to the original hosts file
ORIGINAL_HOSTS_FILE="hosts"

# Use sed to update line two of the [github_servers] group in the hosts file
sed -i "/^\[github_servers\]/!b;n;c$NEW_HOST ansible_user=$NEW_USERNAME" "$ORIGINAL_HOSTS_FILE"

# Define the path to the secrets file
SECRETS_FILE="vars/secrets.yml"
PIPELINES_VARS="/projects/baremetal-playbooks/vars/pipeline-variables.yaml"
GITHUB_ACTIONS_VARS_FILE="vars/github-actions-vars.yml"
FREEIPA_VARS_FILE="vars/freeipa-vars.yml"

# Use yq to update ssh_public_key and ssh_private_key values in secrets.yml
./yq e -i ".ssh_public_key = \"$SSH_PUBLIC_KEY\"" "$SECRETS_FILE"
./yq e -i ".ssh_private_key = \"$SSH_PRIVATE_KEY\"" "$SECRETS_FILE"

cat $SECRETS_FILE

# Use yq to update github_token, ssh_password, and json_body variables in github-actions-vars.yml
./yq e -i ".github_token = \"$GITHUB_TOKEN\"" "$GITHUB_ACTIONS_VARS_FILE"
./yq e -i ".ssh_password = \"$SSH_PASSWORD\"" "$GITHUB_ACTIONS_VARS_FILE"
./yq e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$GITHUB_ACTIONS_VARS_FILE"
./yq e -i ".json_body.inputs.domain = \"$NEW_DOMAIN\"" "$GITHUB_ACTIONS_VARS_FILE"
./yq e -i ".json_body.inputs.forwarder = \"$NEW_FORWARDER\"" "$GITHUB_ACTIONS_VARS_FILE"

cat $GITHUB_ACTIONS_VARS_FILE



# Use yq to update github_token in freeipa-vars.yml
./yq e -i ".github_token = \"$KCLI_PIPELINES_GITHUB_TOKEN\"" "$FREEIPA_VARS_FILE"
./yq e -i ".freeipa_server_fqdn = \"$FREEIPA_SERVER_FQDN\""  "$FREEIPA_VARS_FILE"
./yq e -i ".freeipa_server_domain = \"$FREEIPA_SERVER_DOMAIN\""  "$FREEIPA_VARS_FILE"
./yq e -i  ".freeipa_server_admin_password =\"$FREEIPA_SERVER_ADMIN_PASSWORD\"" "$FREEIPA_VARS_FILE"
./yq e -i ".json_body.inputs.hostname = \"$NEW_HOST\"" "$FREEIPA_VARS_FILE"
cat $FREEIPA_VARS_FILE

for arg in "$@"
do
    case $arg in
        --push-ssh-key)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/push-ssh-key.yaml -e "@$SECRETS_FILE"
        shift
        ;;
        --push-pipeline-vars)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/push-pipeline-variables.yaml -e "variables_file=$PIPELINES_VARS"
        shift
        ;;
        --trigger-github-pipelines)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/trigger-github-pipelines.yaml -e "@$GITHUB_ACTIONS_VARS_FILE"
        shift
        ;;
        --copy-image)
        ssh ${NEW_USERNAME}@${NEW_HOST} " sudo kcli download image rhel8"
        shift
        ;;
        --copy-files)
        copy_dir_files
        shift
        ;;
        --ipa-server)
        ansible-playbook -i "$ORIGINAL_HOSTS_FILE" playbooks/trigger-github-pipelines.yaml -e "@$FREEIPA_VARS_FILE"
        shift
        ;;
        *)
        usage
        ;;
    esac
done