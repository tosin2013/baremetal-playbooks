"""
Module to trigger Equinix Metal server instance and update SSH password.
"""

import argparse
import os
import sqlite3
from contextlib import closing

import requests
import nacl.encoding
import nacl.public
import nacl.utils
import streamlit as st


def init_db():
    """Initialize the SQLite database."""
    conn = sqlite3.connect('defaults.db')
    cursor = conn.cursor()
    cursor.execute(
        """CREATE TABLE IF NOT EXISTS defaults (
            id INTEGER PRIMARY KEY,
            ssh_password TEXT,
            aws_access_key TEXT,
            aws_secret_key TEXT,
            new_host TEXT,
            new_username TEXT,
            new_domain TEXT,
            new_forwarder TEXT,
            freeipa_server_fqdn TEXT,
            freeipa_server_domain TEXT,
            guid TEXT,
            ollama TEXT
        )"""
    )
    conn.commit()
    conn.close()


def get_defaults():
    """Retrieve the latest defaults from the database."""
    with closing(sqlite3.connect("defaults.db")) as conn:
        with closing(conn.cursor()) as cursor:
            cursor.execute("SELECT * FROM defaults ORDER BY id DESC LIMIT 1")
            row = cursor.fetchone()
            if row:
                return {
                    "ssh_password": row[1] if row[1] else "",
                    "aws_access_key": row[2] if row[2] else "",
                    "aws_secret_key": row[3] if row[3] else "",
                    "new_host": row[4] if row[4] else "",
                    "new_username": row[5] if row[5] else "",
                    "new_domain": row[6] if row[6] else "",
                    "new_forwarder": row[7] if row[7] else "",
                    "freeipa_server_fqdn": row[8] if row[8] else "",
                    "freeipa_server_domain": row[9] if row[9] else "",
                    "guid": row[10] if row[10] else "",
                    "ollama": row[11] if row[11] else "",
                }
            return {}


def save_defaults(defaults):
    """Save the provided defaults to the database."""
    print(f"Saving defaults: {defaults}")  # Add this line for debugging
    with closing(sqlite3.connect("defaults.db")) as conn:
        with closing(conn.cursor()) as cursor:
            cursor.execute(
                """INSERT INTO defaults (
            ssh_password, aws_access_key, aws_secret_key, new_host, new_username, new_domain, new_forwarder,
            freeipa_server_fqdn, freeipa_server_domain, guid, ollama
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                defaults,
            )
        conn.commit()


def trigger_github_action(repo_owner, repo_name, workflow_id, token, inputs, kcli_pipelines_runner_token):
    """Trigger a GitHub action with the provided inputs."""
    url = (
        f"https://api.github.com/repos/{repo_owner}/{repo_name}/"
        f"actions/workflows/{workflow_id}/dispatches"
    )
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
    }
    inputs["KCLI_PIPELINES_RUNNER_TOKEN"] = kcli_pipelines_runner_token
    data = {"ref": "main", "inputs": inputs}
    response = requests.post(url, headers=headers, json=data)
    if response.status_code == 204:
        print("GitHub Action triggered successfully.")
    else:
        print(f"Failed to trigger GitHub Action. Status code: {response.status_code}")
        print(f"Response: {response.text}")
    response.raise_for_status()


def update_github_secret(repo_owner, repo_name, secret_name, secret_value, token):
    """Update a GitHub secret with the provided value."""
    public_key_url = (
        f"https://api.github.com/repos/{repo_owner}/{repo_name}/"
        f"actions/secrets/public-key"
    )
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
    }
    public_key_response = requests.get(public_key_url, headers=headers)
    public_key_response.raise_for_status()
    public_key_data = public_key_response.json()

    public_key = nacl.public.PublicKey(
        public_key_data["key"].encode(), encoder=nacl.encoding.Base64Encoder
    )
    sealed_box = nacl.public.SealedBox(public_key)
    encrypted = sealed_box.encrypt(secret_value.encode())

    update_secret_url = (
        f"https://api.github.com/repos/{repo_owner}/{repo_name}/"
        f"actions/secrets/{secret_name}"
    )
    update_secret_data = {
        "encrypted_value": nacl.encoding.Base64Encoder.encode(encrypted).decode(),
        "key_id": public_key_data["key_id"],
    }
    update_secret_response = requests.put(
        update_secret_url, headers=headers, json=update_secret_data
    )
    update_secret_response.raise_for_status()


def cli_main(args):
    """Main function for CLI execution."""
    repo_owner = "tosin2013"
    repo_name = "baremetal-playbooks"
    workflow_id = "equinix-metal-baremetal-blank-server.yml"
    token = args.kcli_pipelines_github_token
    runner_token = args.runner_token

    inputs = {
        "NEW_HOST": args.new_host,
        "NEW_USERNAME": args.new_username,
        "NEW_DOMAIN": args.new_domain,
        "NEW_FORWARDER": args.new_forwarder,
        "FREEIPA_SERVER_FQDN": args.freeipa_server_fqdn,
        "FREEIPA_SERVER_DOMAIN": args.freeipa_server_domain,
        "GUID": args.guid,
        "OLLAMA": args.ollama,
    }

    ssh_password = args.ssh_password
    aws_access_key = args.aws_access_key
    aws_secret_key = args.aws_secret_key

    update_github_secret(repo_owner, repo_name, "SSH_PASSWORD", ssh_password, token)
    update_github_secret(repo_owner, repo_name, "AWS_ACCESS_KEY", aws_access_key, token)
    update_github_secret(repo_owner, repo_name, "AWS_SECRET_KEY", aws_secret_key, token)
    kcli_pipelines_runner_token = args.runner_token
    update_github_secret(repo_owner, repo_name, "KCLI_PIPELINES_RUNNER_TOKEN", kcli_pipelines_runner_token, token)

    trigger_github_action(repo_owner, repo_name, workflow_id, token, inputs, runner_token)
    print("Pipeline has been triggered successfully.")


def gui_main(runner_token):
    """Main function for GUI execution using Streamlit."""
    st.title("Equinix Metal Server Instance Trigger")

    defaults = get_defaults()
    if defaults:
        ssh_password = st.text_input("SSH Password", type="password", value=defaults[1])
        aws_access_key = st.text_input(
            "AWS Access Key", type="password", value=defaults[2]
        )
        aws_secret_key = st.text_input(
            "AWS Secret Key", type="password", value=defaults[3]
        )
        new_host = st.text_input("New Host Name", value=defaults[4])
        new_username = st.text_input("New Username", value=defaults[5])
        new_domain = st.text_input("New Domain", value=defaults[6])
        new_forwarder = st.text_input("New Forwarder IP", value=defaults[7])
        freeipa_server_fqdn = st.text_input("FreeIPA Server FQDN", value=defaults[8])
        freeipa_server_domain = st.text_input(
            "FreeIPA Server Domain", value=defaults[9]
        )
        guid = st.text_input("GUID", value=defaults[10])
        ollama = st.text_input("OLLAMA", value=defaults[11])
    else:
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
        token = os.getenv("KCLI_PIPELINES_GITHUB_TOKEN")
        kcli_pipelines_runner_token = st.text_input(
            "KCLI Pipelines Runner Token",
            type="password",
            value=runner_token,
        )

        inputs = {
            "NEW_HOST": new_host,
            "NEW_USERNAME": new_username,
            "NEW_DOMAIN": new_domain,
            "NEW_FORWARDER": new_forwarder,
            "FREEIPA_SERVER_FQDN": freeipa_server_fqdn,
            "FREEIPA_SERVER_DOMAIN": freeipa_server_domain,
            "GUID": guid,
            "OLLAMA": ollama,
        }

        print(f"Updating SSH_PASSWORD: {ssh_password}")  # Add this line for debugging
        update_github_secret(repo_owner, repo_name, "SSH_PASSWORD", ssh_password, token)
        print(f"Updating AWS_ACCESS_KEY: {aws_access_key}")  # Add this line for debugging
        update_github_secret(
            repo_owner, repo_name, "AWS_ACCESS_KEY", aws_access_key, token
        )
        print(f"Updating AWS_SECRET_KEY: {aws_secret_key}")  # Add this line for debugging
        update_github_secret(
            repo_owner, repo_name, "AWS_SECRET_KEY", aws_secret_key, token
        )
        print(f"Updating KCLI_PIPELINES_RUNNER_TOKEN: {kcli_pipelines_runner_token}")  # Add this line for debugging
        update_github_secret(
            repo_owner,
            repo_name,
            "KCLI_PIPELINES_RUNNER_TOKEN",
            kcli_pipelines_runner_token,
            token,
        )

        save_defaults(
            (
                ssh_password,
                aws_access_key,
                aws_secret_key,
                new_host,
                new_username,
                new_domain,
                new_forwarder,
                freeipa_server_fqdn,
                freeipa_server_domain,
                guid,
                ollama,
            )
        )

        trigger_github_action(repo_owner, repo_name, workflow_id, token, inputs, kcli_pipelines_runner_token)
        st.success("Pipeline has been triggered successfully.")

    # Add the "Save Variables" button
    if st.button("Save Variables"):
        save_defaults(
            (
                ssh_password,
                aws_access_key,
                aws_secret_key,
                new_host,
                new_username,
                new_domain,
                new_forwarder,
                freeipa_server_fqdn,
                freeipa_server_domain,
                guid,
                ollama,
            )
        )
        st.success("Variables have been saved successfully.")


def main():
    """Main entry point of the application."""
    init_db()
    parser = argparse.ArgumentParser(
        description="Trigger Equinix Metal server instance and update SSH password."
    )
    parser.add_argument(
        "--ssh_password", type=str, help="SSH password to use", required=False
    )
    parser.add_argument(
        "--aws_access_key", type=str, help="AWS Access Key", required=False
    )
    parser.add_argument(
        "--aws_secret_key", type=str, help="AWS Secret Key", required=False
    )
    parser.add_argument("--new_host", type=str, help="New host name", required=False)
    parser.add_argument("--new_username", type=str, help="New username", required=False)
    parser.add_argument("--new_domain", type=str, help="New domain", required=False)
    parser.add_argument(
        "--new_forwarder", type=str, help="New forwarder IP", required=False
    )
    parser.add_argument(
        "--freeipa_server_fqdn", type=str, help="FreeIPA server FQDN", required=False
    )
    parser.add_argument(
        "--freeipa_server_domain",
        type=str,
        help="FreeIPA server domain",
        required=False,
    )
    parser.add_argument("--guid", type=str, help="GUID", required=False)
    parser.add_argument("--ollama", type=str, help="OLLAMA", required=False)
    parser.add_argument(
        "--kcli_pipelines_github_token",
        type=str,
        help="GitHub Token for KCLI Pipelines",
        required=True,
    )
    parser.add_argument(
        "--runner_token", type=str, help="Runner Token", required=True
    )
    parser.add_argument("--gui", action="store_true", help="Start the Streamlit GUI")
    args = parser.parse_args()

    if args.gui:
        gui_main(args.runner_token)
    else:
        cli_main(args)


if __name__ == "__main__":
    main()
