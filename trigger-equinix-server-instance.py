import argparse
import requests
import os
import nacl.encoding
import nacl.public
import nacl.utils
import streamlit as st

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

def main():
    parser = argparse.ArgumentParser(description="Trigger Equinix Metal server instance and update SSH password.")
    parser.add_argument('--ssh_password', type=str, help='SSH password to use', required=False)
    parser.add_argument('--aws_access_key', type=str, help='AWS Access Key', required=False)
    parser.add_argument('--aws_secret_key', type=str, help='AWS Secret Key', required=False)
    parser.add_argument('--new_host', type=str, help='New host name', required=False)
    parser.add_argument('--new_username', type=str, help='New username', required=False)
    parser.add_argument('--new_domain', type=str, help='New domain', required=False)
    parser.add_argument('--new_forwarder', type=str, help='New forwarder IP', required=False)
    parser.add_argument('--freeipa_server_fqdn', type=str, help='FreeIPA server FQDN', required=False)
    parser.add_argument('--freeipa_server_domain', type=str, help='FreeIPA server domain', required=False)
    parser.add_argument('--guid', type=str, help='GUID', required=False)
    parser.add_argument('--ollama', type=str, help='OLLAMA', required=False)
    parser.add_argument('--gui', action='store_true', help='Start the Streamlit GUI')
    args = parser.parse_args()

    if args.gui:
        st.title("Equinix Metal Server Instance Trigger")

        ssh_password = st.text_input("SSH Password", type="password")
        aws_access_key = st.text_input("AWS Access Key", type="password")
        aws_secret_key = st.text_input("AWS Secret Key", type="password")
        new_host = st.text_input("New Host Name")
        new_username = st.text_input("New Username")
        new_domain = st.text_input("New Domain")
        new_forwarder = st.text_input("New Forwarder IP")
        freeipa_server_fqdn = st.text_input("FreeIPA Server FQDN")
        freeipa_server_domain = st.text_input("FreeIPA Server Domain")
        guid = st.text_input("GUID")
        ollama = st.text_input("OLLAMA")

        if st.button("Trigger Pipeline"):
            repo_owner = "tosin2013"
            repo_name = "baremetal-playbooks"
            workflow_id = "equinix-metal-baremetal-blank-server.yml"
            token = os.getenv("GITHUB_TOKEN")

            inputs = {
                "NEW_HOST": new_host,
                "NEW_USERNAME": new_username,
                "NEW_DOMAIN": new_domain,
                "NEW_FORWARDER": new_forwarder,
                "FREEIPA_SERVER_FQDN": freeipa_server_fqdn,
                "FREEIPA_SERVER_DOMAIN": freeipa_server_domain,
                "GUID": guid,
                "OLLAMA": ollama
            }

            update_github_secret(repo_owner, repo_name, "SSH_PASSWORD", ssh_password, token)
            update_github_secret(repo_owner, repo_name, "AWS_ACCESS_KEY", aws_access_key, token)
            update_github_secret(repo_owner, repo_name, "AWS_SECRET_KEY", aws_secret_key, token)

            trigger_github_action(repo_owner, repo_name, workflow_id, token, inputs)
            st.success("Pipeline has been triggered successfully.")
    else:
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
            "FREEIPA_SERVER_DOMAIN": args.freeipa_server_domain,
            "GUID": args.guid,
            "OLLAMA": args.ollama
        }

        ssh_password = args.ssh_password
        aws_access_key = args.aws_access_key
        aws_secret_key = args.aws_secret_key

        update_github_secret(repo_owner, repo_name, "SSH_PASSWORD", ssh_password, token)
        update_github_secret(repo_owner, repo_name, "AWS_ACCESS_KEY", aws_access_key, token)
        update_github_secret(repo_owner, repo_name, "AWS_SECRET_KEY", aws_secret_key, token)

        trigger_github_action(repo_owner, repo_name, workflow_id, token, inputs)
        print("Pipeline has been triggered successfully.")

if __name__ == "__main__":
    main()
