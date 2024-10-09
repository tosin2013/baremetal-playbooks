# Trigger Equinix Metal Server Instance

This script allows you to trigger an Equinix Metal server instance and update SSH passwords. It can be run from the command line or via a Streamlit GUI.

## Prerequisites

- Python 3.x
- Streamlit (if using the GUI)
- `requests` library
- `pynacl` library
- `sqlite3` library

You can install the required Python packages using pip:

```bash
pip install streamlit requests pynacl
```

## Running the Script

### From the Command Line

To run the script from the command line, use the following command:

```bash
python trigger-equinix-server-instance.py \
    --ssh_password YOUR_SSH_PASSWORD \
    --aws_access_key YOUR_AWS_ACCESS_KEY \
    --aws_secret_key YOUR_AWS_SECRET_KEY \
    --new_host NEW_HOST_NAME \
    --new_username NEW_USERNAME \
    --new_domain NEW_DOMAIN \
    --new_forwarder NEW_FORWARDER_IP \
    --freeipa_server_fqdn FREEIPA_SERVER_FQDN \
    --freeipa_server_domain FREEIPA_SERVER_DOMAIN \
    --guid GUID \
    --ollama OLLAMA
```

### KCLI Pipelines Runner Token

The `KCLI_PIPELINES_RUNNER_TOKEN` is a secret token used to authenticate with the KCLI pipelines runner. This token is required to trigger certain pipelines.

### KCLI Pipelines GitHub Token

The `KCLI_PIPELINES_GITHUB_TOKEN` is a GitHub token used to authenticate with the GitHub repository. This token is required to update GitHub secrets and trigger workflows.

### Command Line Example

When running the script from the command line, include the `--kcli_pipelines_runner_token` argument:

```bash
python trigger-equinix-server-instance.py \
    --ssh_password YOUR_SSH_PASSWORD \
    --aws_access_key YOUR_AWS_ACCESS_KEY \
    --aws_secret_key YOUR_AWS_SECRET_KEY \
    --new_host NEW_HOST_NAME \
    --new_username NEW_USERNAME \
    --new_domain NEW_DOMAIN \
    --new_forwarder NEW_FORWARDER_IP \
    --freeipa_server_fqdn FREEIPA_SERVER_FQDN \
    --freeipa_server_domain FREEIPA_SERVER_DOMAIN \
    --guid GUID \
    --ollama OLLAMA \
    --kcli_pipelines_runner_token YOUR_KCLI_PIPELINES_RUNNER_TOKEN \
    --kcli_pipelines_github_token YOUR_KCLI_PIPELINES_GITHUB_TOKEN
```

### GUI Interface

In the Streamlit GUI, you will find a field labeled "KCLI Pipelines Runner Token" where you can input the token.

### Using the Streamlit GUI

To start the Streamlit GUI, use the following command:

```bash
streamlit run trigger-equinix-server-instance.py -- --gui
```

This will open a web browser with a user-friendly interface where you can input the required parameters and trigger the pipeline.

The GUI will load default values from a SQLite database if they are available, so you don't have to type them in every time.

## GUI Interface

The Streamlit GUI provides a simple form for entering the necessary parameters:

- **SSH Password**: The SSH password to use.
- **AWS Access Key**: Your AWS access key.
- **AWS Secret Key**: Your AWS secret key.
- **New Host Name**: The new host name.
- **New Username**: The new username.
- **New Domain**: The new domain.
- **New Forwarder IP**: The new forwarder IP.
- **FreeIPA Server FQDN**: The FreeIPA server FQDN.
- **FreeIPA Server Domain**: The FreeIPA server domain.
- **GUID**: The GUID.
- **OLLAMA**: The OLLAMA.

After filling in the form, click the "Trigger Pipeline" button to start the process.

## Environment Variables

Ensure that the `GITHUB_TOKEN` environment variable is set with your GitHub token:

```bash
export GITHUB_TOKEN=your_github_token
```

## Notes

- The script requires a GitHub token with the necessary permissions to trigger workflows and update secrets.
- The GUI is designed to be user-friendly, making it accessible to non-technical users.
- The GUI now supports a SQLite database to store and retrieve default values, making it more convenient for users.
