# How to Run the `trigger-equinix-server-instance.py` Script

To trigger an Equinix Metal server instance and update the SSH password, you can use the `trigger-equinix-server-instance.py` script. This script requires several arguments to be passed to it. Below is an example command:

```bash
python trigger-equinix-server-instance.py \
    --ssh_password "your_ssh_password" \
    --aws_access_key "your_aws_access_key" \
    --aws_secret_key "your_aws_secret_key" \
    --new_host "new_host_name" \
    --new_username "new_username" \
    --new_domain "new_domain" \
    --new_forwarder "new_forwarder_ip" \
    --freeipa_server_fqdn "freeipa_server_fqdn" \
    --freeipa_server_domain "freeipa_server_domain" \
    --guid "your_guid" \
    --ollama "true"
```

### Required Arguments:
- `--ssh_password`: The SSH password to use.
- `--aws_access_key`: The AWS Access Key.
- `--aws_secret_key`: The AWS Secret Key.
- `--new_host`: The new host name.
- `--new_username`: The new username.
- `--new_domain`: The new domain.
- `--new_forwarder`: The new forwarder IP.
- `--freeipa_server_fqdn`: The FreeIPA server FQDN.
- `--freeipa_server_domain`: The FreeIPA server domain.
- `--guid`: The GUID.
- `--ollama`: The OLLAMA value.

Make sure to replace the placeholders with actual values when running the script.

### GitHub Token Permissions
Ensure that the GitHub token used has the `repo` scope to access repository secrets.
