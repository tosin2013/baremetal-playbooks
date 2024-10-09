import pytest
import sqlite3
import os
from unittest.mock import patch, MagicMock, call
update_github_secret,
cli_main,
gui_main,
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


# Test trigger_github_action function
@patch("requests.post")
def test_trigger_github_action(mock_post):
    mock_post.return_value.status_code = 204
    trigger_github_action("owner", "repo", "workflow", "token", {"input": "value"})
    mock_post.assert_called_once_with(
        "https://api.github.com/repos/owner/repo/actions/workflows/workflow/dispatches",
        headers={
            "Authorization": "token token",
            "Accept": "application/vnd.github.v3+json",
        },
        json={"ref": "main", "inputs": {"input": "value"}},
    )


# Test update_github_secret function
@patch("requests.get")
@patch("requests.put")
def test_update_github_secret(mock_put, mock_get):
    mock_get.return_value.json.return_value = {
        "key": "a" * 32,  # This is a valid 32-byte key
        "key_id": "key_id",
    }
    # Ensure the key is correctly formatted before passing it to the `nacl.public.PublicKey` constructor
    mock_get.return_value.json.return_value["key"] = "a" * 32
    mock_put.return_value.status_code = 204
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
        json={"encrypted_value": "encrypted_value", "key_id": "key_id"},
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
    )
    cli_main(args)
    mock_update.assert_any_call(
        "tosin2013", "baremetal-playbooks", "SSH_PASSWORD", "password", "token"
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
    ]
    mock_button.side_effect = [False, True]

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
        gui_main()
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
        "tosin2013",
        "baremetal-playbooks",
        "KCLI_PIPELINES_RUNNER_TOKEN",
        "runner_token",
        "token",
    )
    # Ensure the mock is correctly set up and the calls are verified
    mock_update.assert_has_calls([
        call("tosin2013", "baremetal-playbooks", "SSH_PASSWORD", "password", "token"),
        call("tosin2013", "baremetal-playbooks", "AWS_ACCESS_KEY", "access_key", "token"),
        call("tosin2013", "baremetal-playbooks", "AWS_SECRET_KEY", "secret_key", "token"),
        call("tosin2013", "baremetal-playbooks", "KCLI_PIPELINES_RUNNER_TOKEN", "runner_token", "token"),
    ])
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
    )
    mock_success.assert_called_once_with("Pipeline has been triggered successfully.")
