import pytest
import sqlite3
import os
from unittest.mock import patch, MagicMock, call
import nacl.public
import nacl.encoding
from trigger_equinix_server_instance import (
    update_github_secret,
    cli_main,
    gui_main,
    init_db,
    get_defaults,
    save_defaults,
    trigger_github_action,
)

# Mocking the database connection
@pytest.fixture
def mock_db_connection():
    with patch("sqlite3.connect") as mock_connect:
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value = mock_cursor
        mock_connect.return_value = mock_conn
        yield mock_conn, mock_cursor


# Test init_db function
def test_init_db(mock_db_connection):
    mock_conn, mock_cursor = mock_db_connection
    with patch("trigger_equinix_server_instance.init_db"):
        init_db()
        mock_cursor.execute.assert_called_once_with(
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
        mock_conn.commit.assert_called_once()
        mock_conn.close.assert_called_once()


# Test get_defaults function
def test_get_defaults(mock_db_connection):
    mock_conn, mock_cursor = mock_db_connection
    mock_cursor.fetchone.return_value = (
        1,
        "password",
        "access_key",
        "secret_key",
        "host",
        "username",
        "domain",
        "forwarder",
        "fqdn",
        "domain",
        "guid",
        "ollama",
    )
    result = get_defaults()
    assert result == (
        1,
        "password",
        "access_key",
        "secret_key",
        "host",
        "username",
        "domain",
        "forwarder",
        "fqdn",
        "domain",
        "guid",
        "ollama",
    )


# Test save_defaults function
def test_save_defaults(mock_db_connection):
    mock_conn, mock_cursor = mock_db_connection
    defaults = (
        "password",
        "access_key",
        "secret_key",
        "host",
        "username",
        "domain",
        "forwarder",
        "fqdn",
        "domain",
        "guid",
        "ollama",
    )
    save_defaults(defaults)
    mock_cursor.execute.assert_called_once_with(
        """INSERT INTO defaults (
            ssh_password, aws_access_key, aws_secret_key, new_host, new_username, new_domain, new_forwarder,
            freeipa_server_fqdn, freeipa_server_domain, guid, ollama
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        defaults,
    )
    mock_conn.commit.assert_called_once()
    mock_conn.close.assert_called_once()


# Test trigger_github_action function
@patch("requests.post")
def test_trigger_github_action(mock_post):
    mock_post.return_value.status_code = 204
    trigger_github_action("owner", "repo", "workflow", "token", {"input": "value"}, "runner_token")
    mock_post.assert_called_once_with(
        "https://api.github.com/repos/owner/repo/actions/workflows/workflow/dispatches",
        headers={
            "Authorization": "token token",
            "Accept": "application/vnd.github.v3+json",
        },
        json={"ref": "main", "inputs": {"input": "value", "KCLI_PIPELINES_RUNNER_TOKEN": "runner_token"}},
    )


# Test update_github_secret function
@patch("requests.get")
@patch("requests.put")
def test_update_github_secret(mock_put, mock_get):
    mock_get.return_value.json.return_value = {
        "key": "KFf6jhg+E7PrUX5WTRJvv0WVAih1dK+tQwF+E/bfIBU=",  # This is a valid Public Key
        "key_id": "key_id",
    }
    mock_put.return_value.status_code = 204

    # Correctly encrypt the secret value
    public_key = nacl.public.PublicKey(
        "KFf6jhg+E7PrUX5WTRJvv0WVAih1dK+tQwF+E/bfIBU=".encode(),
        encoder=nacl.encoding.Base64Encoder,
    )
    sealed_box = nacl.public.SealedBox(public_key)
    encrypted_value = sealed_box.encrypt("secret_value".encode())
    encoded_encrypted_value = nacl.encoding.Base64Encoder.encode(encrypted_value)

    with patch("nacl.public.SealedBox.encrypt") as mock_encrypt:
        mock_encrypt.return_value = encrypted_value
        update_github_secret("owner", "repo", "secret_name", "secret_value", "token")

    mock_get.assert_called_once_with(
        "https://api.github.com/repos/owner/repo/actions/secrets/public-key",
        headers={
            "Authorization": "token token",
            "Accept": "application/vnd.github.v3+json",
        },
    )
    mock_put.assert_called_once_with(
        "https://api.github.com/repos/owner/repo/actions/secrets/secret_name",
        headers={
            "Authorization": "token token",
            "Accept": "application/vnd.github.v3+json",
        },
        json={"encrypted_value": encoded_encrypted_value.decode(), "key_id": "key_id"},
    )


# Test cli_main function
@patch("trigger_equinix_server_instance.update_github_secret")
@patch("trigger_equinix_server_instance.trigger_github_action")
def test_cli_main(mock_trigger, mock_update):
    args = MagicMock(
        kcli_pipelines_github_token="token",
        ssh_password="password",
        aws_access_key="access_key",
        aws_secret_key="secret_key",
        new_host="host",
        new_username="username",
        new_domain="domain",
        new_forwarder="forwarder",
        freeipa_server_fqdn="fqdn",
        freeipa_server_domain="domain",
        guid="guid",
        ollama="ollama",
        runner_token="runner_token",  # Ensure runner_token is set
    )
    cli_main(args)
    mock_update.assert_any_call(
        "tosin2013", "baremetal-playbooks", "SSH_PASSWORD", "password", "token"
    )
    mock_update.assert_any_call(
        "tosin2013", "baremetal-playbooks", "KCLI_PIPELINES_RUNNER_TOKEN", "runner_token", "token"
    )
    mock_update.assert_any_call(
        "tosin2013", "baremetal-playbooks", "AWS_ACCESS_KEY", "access_key", "token"
    )
    mock_update.assert_any_call(
        "tosin2013", "baremetal-playbooks", "AWS_SECRET_KEY", "secret_key", "token"
    )
    mock_trigger.assert_called_once_with(
        "tosin2013",
        "baremetal-playbooks",
        "equinix-metal-baremetal-blank-server.yml",
        "token",
        {
            "NEW_HOST": "host",
            "NEW_USERNAME": "username",
            "NEW_DOMAIN": "domain",
            "NEW_FORWARDER": "forwarder",
            "FREEIPA_SERVER_FQDN": "fqdn",
            "FREEIPA_SERVER_DOMAIN": "domain",
            "GUID": "guid",
            "OLLAMA": "ollama",
        },
        "runner_token"
    )


# Test gui_main function
@patch("streamlit.text_input")
@patch("streamlit.button")
@patch("streamlit.success")
@patch("os.getenv")
@patch("trigger_equinix_server_instance.update_github_secret")
@patch("trigger_equinix_server_instance.trigger_github_action")
def test_gui_main(
    mock_trigger, mock_update, mock_getenv, mock_success, mock_button, mock_text_input
):
    mock_getenv.return_value = "token"
    mock_text_input.side_effect = [
        "password",
        "access_key",
        "secret_key",
        "host",
        "username",
        "domain",
        "forwarder",
        "fqdn",
        "domain",
        "guid",
        "ollama",
        "runner_token",  # Ensure runner_token is set
    ]
    mock_button.side_effect = [False, True]

    # Mock the args object
    args = MagicMock(runner_token="runner_token")
    mock_text_input.side_effect = [
        "password",
        "access_key",
        "secret_key",
        "host",
        "username",
        "domain",
        "forwarder",
        "fqdn",
        "domain",
        "guid",
        "ollama",
        "runner_token",  # Ensure runner_token is set
    ]
    mock_text_input.side_effect = [
        "password",
        "access_key",
        "secret_key",
        "host",
        "username",
        "domain",
        "forwarder",
        "fqdn",
        "domain",
        "guid",
        "ollama",
        "runner_token",  # Ensure runner_token is set
    ]

    # Ensure the table is created before accessing it
    with patch("sqlite3.connect") as mock_connect:
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value = mock_cursor
        mock_connect.return_value = mock_conn
        mock_cursor.fetchone.return_value = (
            1,
            "password",
            "access_key",
            "secret_key",
            "host",
            "username",
            "domain",
            "forwarder",
            "fqdn",
            "domain",
            "guid",
            "ollama",
        )
        gui_main(args.runner_token)
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "SSH_PASSWORD", "password", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_ACCESS_KEY", "access_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_SECRET_KEY", "secret_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "KCLI_PIPELINES_RUNNER_TOKEN", "runner_token", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "SSH_PASSWORD", "password", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_ACCESS_KEY", "access_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_SECRET_KEY", "secret_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "KCLI_PIPELINES_RUNNER_TOKEN", "runner_token", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "SSH_PASSWORD", "password", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_ACCESS_KEY", "access_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_SECRET_KEY", "secret_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "KCLI_PIPELINES_RUNNER_TOKEN", "runner_token", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "SSH_PASSWORD", "password", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_ACCESS_KEY", "access_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_SECRET_KEY", "secret_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "KCLI_PIPELINES_RUNNER_TOKEN", "runner_token", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "SSH_PASSWORD", "password", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_ACCESS_KEY", "access_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_SECRET_KEY", "secret_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "KCLI_PIPELINES_RUNNER_TOKEN", "runner_token", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_ACCESS_KEY", "access_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "AWS_SECRET_KEY", "secret_key", "token"
        )
        mock_update.assert_any_call(
            "tosin2013", "baremetal-playbooks", "KCLI_PIPELINES_RUNNER_TOKEN", "runner_token", "token"
        )
    mock_trigger.assert_called_once_with(
        "tosin2013",
        "baremetal-playbooks",
        "equinix-metal-baremetal-blank-server.yml",
        "token",
        {
            "NEW_HOST": "host",
            "NEW_USERNAME": "username",
            "NEW_DOMAIN": "domain",
            "NEW_FORWARDER": "forwarder",
            "FREEIPA_SERVER_FQDN": "fqdn",
            "FREEIPA_SERVER_DOMAIN": "domain",
            "GUID": "guid",
            "OLLAMA": "ollama",
        },
        "runner_token"
    )
    mock_success.assert_called_once_with("Pipeline has been triggered successfully.")
