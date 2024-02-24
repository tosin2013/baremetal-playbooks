# Baremetal Lab GitHub Actions Workflows

This is a container (execution environment) aimed towards being used
for the development and testing of the Ansible content. We should also mention
that this container must not be used in production by Ansible users.

It includes:

- [ansible-core]
- [ansible-lint]
- [molecule]

Among its main consumers, we can mention [ansible-navigator] and
[vscode-ansible] extension.

[ansible-core]: https://github.com/ansible/ansible
[ansible-lint]: https://github.com/ansible/ansible-lint
[ansible-navigator]: https://github.com/ansible/ansible-navigator
[molecule]: https://github.com/ansible-community/molecule
[vscode-ansible]: https://github.com/ansible/vscode-ansible

## Contributing

We use [taskfile](https://taskfile.dev/) as build tool, so you should run
`task -l` to list available. If you run just `task`, it will run the default
set of build tasks. If these are passing, you are ready to open a pull request
with your changes.

## Prerequesites
```
curl -OL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
mv yq_linux_amd64 yq
chmod +x yq
$ sudo mv yq /usr/local/bin
```

## Playbooks

This code selection consists of a series of commands written in Markdown format. These commands are used to execute various Ansible playbooks for different purposes. Here's a breakdown of the commands:

1. `./copy-ssh-id-and-test.sh admin@example.com`: This command is used to copy the SSH key and test the connection to the specified host.

2. `ansible-playbook -i hosts  playbooks/push-ssh-key.yaml  -e "@secrets.yml"`: This command executes the Ansible playbook `push-ssh-key.yaml` using the inventory file `hosts` and the variables defined in `secrets.yml`.

3. `ansible-playbook -i hosts  playbooks/push-pipeline-variables.yaml  -e "variables_file=/projects/baremetal-playbooks/pipeline-variables.yaml"`: This command executes the Ansible playbook `push-pipeline-variables.yaml` using the inventory file `hosts` and passing the `variables_file` parameter with the specified value.

4. `ansible-playbook -i hosts  playbooks/trigger-github-pipelines.yaml  -e "@github-actions-vars.yml"`: This command executes the Ansible playbook `trigger-github-pipelines.yaml` using the inventory file `hosts` and the variables defined in `github-actions-vars.yml`.

5. `ansible-playbook -i hosts  playbooks/trigger-github-pipelines.yaml  -e "@kcli-openshift4-baremetal-vars.yml"`: This command executes the Ansible playbook `trigger-github-pipelines.yaml` using the inventory file `hosts` and the variables defined in `kcli-openshift4-baremetal-vars.yml`.

6. `ansible-playbook -i hosts  playbooks/trigger-github-pipelines.yaml  -e "@freeipa-vars.yml"`: This command executes the Ansible playbook `trigger-github-pipelines.yaml` using the inventory file `hosts` and the variables defined in `freeipa-vars.yml`.

7. `ansible-playbook -i hosts  playbooks/populate-hostnames-on-freeipa.yaml  -e "@freeipa-vars.yml"`: This command executes the Ansible playbook `populate-hostnames-on-freeipa.yaml` using the inventory file `hosts` and the variables defined in `freeipa-vars.yml`.


# ansible-galaxy collection install community.general
`ansible-playbook -i hosts  playbooks/populate-hostnames-on-freeipa.yaml  -e "@freeipa-vars.yml"`