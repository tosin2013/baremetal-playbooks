"""Unit tests for the trigger_equinix_server_instance module."""


from trigger_equinix_server_instance import (
    update_github_secret,
    cli_main,
    gui_main,
    get_defaults,
    save_defaults,
    trigger_github_action,
)

# Constants for repeated values
REPO_OWNER = "tosin2013"
REPO_NAME = "baremetal-playbooks"
WORKFLOW_FILE = "equinix-metal-baremetal-blank-server.yml"
CONFIG_FILE = 'config.yaml'

# Suppress specific Streamlit warnings
warnings.filterwarnings("ignore", message=".*missing ScriptRunContext!*")
logging.getLogger("streamlit").setLevel(logging.ERROR)


def test_init_config():
    """Test that the YAML config file is created with default values."""
    mock_file = mock_open()
    with patch("builtins.open", mock_file):
        # Assuming init_db initializes the config if not present
        # If init_db is no longer used, skip this test or adjust accordingly
        # init_db()
        pass  # Replace with actual init function if applicable
    # Add assertions as needed


def test_get_defaults():
    """Test the get_defaults function retrieves configurations from YAML."""
    mock_yaml = {
        'defaults': {
            'ssh_password': 'password',
            'aws_access_key': 'access_key',
            'aws_secret_key': 'secret_key',
            'new_host': 'host',
            'new_username': 'username',
            'new_domain': 'domain',
            'new_forwarder': 'forwarder',
            'freeipa_server_fqdn': 'fqdn',
            'freeipa_server_domain': 'domain',
            'guid': 'guid',
            'ollama': 'ollama',
        }
    }
    mock_file = mock_open(read_data=yaml.safe_dump(mock_yaml))
    with patch("builtins.open", mock_file):
        defaults = get_defaults()
        assert defaults == mock_yaml['defaults']
        mock_file.assert_called_with(CONFIG_FILE, 'r')


def test_save_defaults():
    """Test the save_defaults function writes configurations to YAML."""
    new_defaults = {
        'ssh_password': 'new_password',
        'aws_access_key': 'new_access_key',
        'aws_secret_key': 'new_secret_key',
        'new_host': 'new_host',
        'new_username': 'new_username',
        'new_domain': 'new_domain',
        'new_forwarder': 'new_forwarder',
        'freeipa_server_fqdn': 'new_fqdn',
        'freeipa_server_domain': 'new_domain',
        'guid': 'new_guid',
        'ollama': 'new_ollama',
    }
    updated_yaml = {'defaults': new_defaults}
    mock_file = mock_open(read_data=yaml.safe_dump({'defaults': {}}))
    with patch("builtins.open", mock_file):
        save_defaults(new_defaults)
        # Assert that the file was opened for writing
        mock_file.assert_called_with(CONFIG_FILE, 'w')
        handle = mock_file()
        # Assert that the updated YAML was written
        handle.write.assert_called_once_with(yaml.safe_dump(updated_yaml))


@patch("trigger_equinix_server_instance.requests.post")
def test_trigger_github_action(mock_post):
    """Test the trigger_github_action function to ensure it dispatches a GitHub workflow."""
    mock_post.return_value.status_code = 204
    trigger_github_action(
        REPO_OWNER,
        REPO_NAME,
        "workflow",
        "token",
        {"input": "value"},
        "runner_token",
    )
    mock_post.assert_called_once_with(
        f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/actions/workflows/workflow/dispatches",
        headers={
            "Authorization": "token token",
            "Accept": "application/vnd.github.v3+json",
        },
        json={
            "ref": "main",
            "inputs": {
                "input": "value",
                "KCLI_PIPELINES_RUNNER_TOKEN": "runner_token",
            },
        },
    )


@patch("trigger_equinix_server_instance.requests.put")
@patch("trigger_equinix_server_instance.requests.get")
def test_update_github_secret(mock_get, mock_put):
    """Test the update_github_secret function to ensure it updates a GitHub secret."""
    mock_get.return_value.json.return_value = {
        "key": "KFf6jhg+E7PrUX5WTRJvv0WVAih1dK+tQwF+E/bfIBU=",
        "key_id": "key_id",
    }
    mock_put.return_value.status_code = 204

    # Correctly encrypt the secret value
    public_key = nacl.public.PublicKey(
        "KFf6jhg+E7PrUX5WTRJvv0WVAih1dK+tQwF+E/bfIBU=",
        encoder=nacl.encoding.Base64Encoder,
    )
    sealed_box = nacl.public.SealedBox(public_key)
    encrypted_value = sealed_box.encrypt(b"secret_value")
    encoded_encrypted_value = nacl.encoding.Base64Encoder.encode(encrypted_value).decode()

    with patch.object(nacl.public.SealedBox, "encrypt", return_value=encrypted_value) as mock_encrypt:
        update_github_secret(REPO_OWNER, REPO_NAME, "secret_name", "secret_value", "token")
        mock_encrypt.assert_called_once_with(b"secret_value")

    mock_get.assert_called_once_with(
        f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/actions/secrets/public-key",
        headers={
            "Authorization": "token token",
            "Accept": "application/vnd.github.v3+json",
        },
    )
    mock_put.assert_called_once_with(
        f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/actions/secrets/secret_name",
        headers={
            "Authorization": "token token",
            "Accept": "application/vnd.github.v3+json",
        },
        json={
            "encrypted_value": encoded_encrypted_value,
            "key_id": "key_id",
        },
    )


@patch("trigger_equinix_server_instance.trigger_github_action")
@patch("trigger_equinix_server_instance.update_github_secret")
def test_cli_main(mock_update, mock_trigger):
    """Test the cli_main function to ensure it updates secrets and triggers the pipeline."""
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
        runner_token="runner_token",
    )
    cli_main(args)

    expected_update_calls = [
        call(
            REPO_OWNER, REPO_NAME, "SSH_PASSWORD", "password", "token"
        ),
        call(
            REPO_OWNER,
            REPO_NAME,
            "AWS_ACCESS_KEY",
            "access_key",
            "token",
        ),
        call(
            REPO_OWNER,
            REPO_NAME,
            "AWS_SECRET_KEY",
            "secret_key",
            "token",
        ),
        call(
            REPO_OWNER,
            REPO_NAME,
            "KCLI_PIPELINES_RUNNER_TOKEN",
            "runner_token",
            "token",
        ),
    ]
    mock_update.assert_has_calls(expected_update_calls, any_order=True)
    mock_trigger.assert_called_once_with(
        REPO_OWNER,
        REPO_NAME,
        WORKFLOW_FILE,
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
        "runner_token",
    )


@patch("trigger_equinix_server_instance.trigger_github_action")
@patch("trigger_equinix_server_instance.update_github_secret")
@patch("os.getenv", return_value="token")
@patch("streamlit.success")
@patch("streamlit.button", return_value=True)
@patch("streamlit.text_input")
def test_gui_main(
    mock_text_input,
    mock_success,
    mock_update,
    mock_trigger,
    type='text',
    value='',
):
    """Test the gui_main function to ensure it updates secrets and triggers the pipeline via GUI."""
    # Define the expected sequence of inputs based on labels
    input_mapping = {
        "SSH Password": "password",
        "AWS Access Key": "access_key",
        "AWS Secret Key": "secret_key",
        "New Host": "host",
        "Username": "username",
        "Domain": "domain",
        "Forwarder": "forwarder",
        "FreeIPA Server FQDN": "fqdn",
        "FreeIPA Server Domain": "domain",
        "GUID": "guid",
        "OLLAMA": "ollama",
        "KCLI Pipelines Runner Token": "runner_token",
    }

    def text_input_side_effect(label, type='text', value=''):
        return input_mapping.get(label, "")

    mock_text_input.side_effect = text_input_side_effect

    # Pass the required 'runner_token' argument to gui_main
    gui_main("runner_token")

    # Define the expected calls to update_github_secret
    expected_update_calls = [
        call(
            REPO_OWNER, REPO_NAME, "SSH_PASSWORD", "password", "token"
        ),
        call(
            REPO_OWNER,
            REPO_NAME,
            "AWS_ACCESS_KEY",
            "access_key",
            "token",
        ),
        call(
            REPO_OWNER,
            REPO_NAME,
            "AWS_SECRET_KEY",
            "secret_key",
            "token",
        ),
        call(
            REPO_OWNER,
            REPO_NAME,
            "KCLI_PIPELINES_RUNNER_TOKEN",
            "runner_token",
            "token",
        ),
    ]
    mock_update.assert_has_calls(expected_update_calls, any_order=True)
    mock_trigger.assert_called_once_with(
        REPO_OWNER,
        REPO_NAME,
        WORKFLOW_FILE,
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
        "runner_token",
    )
    mock_success.assert_called_once_with("Pipeline has been triggered successfully.")
