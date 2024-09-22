import argparse
import requests
import os
import nacl.encoding
import nacl.public
import nacl.utils

def trigger_github_action(repo_owner, repo_name, workflow_id, token, inputs):
    url = f"https://api.github.com/repos/{repo_owner}/{repo_name}/actions/workflows/{workflow_id}/dispatches"
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
    }
    data = {
        "ref": "main",
        "inputs": inputs
    }
    response = requests.post(url, headers=headers, json=data)
    response.raise_for_status()


def update_github_secret(repo_owner, repo_name, secret_name, secret_value, token):
    public_key_url = f"https://api.github.com/repos/{repo_owner}/{repo_name}/actions/secrets/public-key"
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
    }
    public_key_response = requests.get(public_key_url, headers=headers)
    public_key_response.raise_for_status()
    public_key_data = public_key_response.json()
    
    public_key = nacl.public.PublicKey(public_key_data['key'].encode(), encoder=nacl.encoding.Base64Encoder)
    sealed_box = nacl.public.SealedBox(public_key)
    encrypted = sealed_box.encrypt(secret_value.encode())
    
    update_secret_url = f"https://api.github.com/repos/{repo_owner}/{repo_name}/actions/secrets/{secret_name}"
    update_secret_data = {
        "encrypted_value": nacl.encoding.Base64Encoder.encode(encrypted).decode(),
        "key_id": public_key_data['key_id']
    }
    update_secret_response = requests.put(update_secret_url, headers=headers, json=update_secret_data)
    update_secret_response.raise_for_status()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Trigger Equinix Metal server instance and update SSH password.")
    parser.add_argument('--ssh_password', type=str, help='SSH password to use', required=True)
    parser.add_argument('--new_host', type=str, help='New host name', required=True)
    parser.add_argument('--new_username', type=str, help='New username', required=True)
    parser.add_argument('--new_domain', type=str, help='New domain', required=True)
    parser.add_argument('--new_forwarder', type=str, help='New forwarder IP', required=True)
    parser.add_argument('--freeipa_server_fqdn', type=str, help='FreeIPA server FQDN', required=True)
    parser.add_argument('--freeipa_server_domain', type=str, help='FreeIPA server domain', required=True)
    args = parser.parse_args()
    
    repo_owner = "tosin2013"
    repo_name = "baremetal-playbooks"
    workflow_id = "equinix-metal-baremetal-blank-server.yml"
    token = os.getenv("GITHUB_TOKEN")
    
    inputs = {
        "NEW_HOST": args.new_host,
        "NEW_USERNAME": args.new_username,
        "NEW_DOMAIN": args.new_domain,
        "NEW_FORWARDER": args.new_forwarder,
        "FREEIPA_SERVER_FQDN": args.freeipa_server_fqdn,
        "FREEIPA_SERVER_DOMAIN": args.freeipa_server_domain
    }
    
    ssh_password = args.ssh_password
    update_github_secret(repo_owner, repo_name, "SSH_PASSWORD", ssh_password, token)
    
    trigger_github_action(repo_owner, repo_name, workflow_id, token, inputs)
    print("Pipeline has been triggered successfully.")
