# ARG must be declared before FROM
ARG EE_BASE_IMAGE=quay.io/ansible/creator-base:latest
FROM $EE_BASE_IMAGE

# ARG must be declared after FROM
ARG CONTAINER_NAME
ENV CONTAINER_NAME $CONTAINER_NAME

# Labels
LABEL org.opencontainers.image.source https://github.com/ansible/baremetal-playbooks
LABEL org.opencontainers.image.authors "Ansible DevTools"
LABEL org.opencontainers.image.vendor "Red Hat"
LABEL org.opencontainers.image.licenses "GPL-3.0"
LABEL ansible-execution-environment=true

USER root
WORKDIR /tmp

# Copy necessary files
COPY _build/requirements.txt requirements.txt
COPY _build/requirements.yml requirements.yml
COPY _build/devtools-publish /usr/local/bin/devtools-publish
COPY _build/shells /etc/shells
COPY _build/.bashrc /home/runner/.bashrc

# Install dependencies and set up environment
RUN microdnf install --assumeyes ncurses && \
    microdnf clean all && \
    pip3 install --progress-bar=off -r requirements.txt && \
    mkdir -p ~/.ansible/roles /usr/share/ansible/roles /etc/ansible/roles /usr/share/ansible/collections && \
    rm -rf $(pip3 cache dir) && \
    microdnf install -y sshpass openssl wget unzip jq && \
    wget https://releases.hashicorp.com/vault/1.17.2/vault_1.17.2_linux_amd64.zip -O vault_1.17.2_linux_amd64.zip  && \
    unzip vault_1.17.2_linux_amd64.zip   && \
    mv vault /usr/local/bin/vault && \
    rm vault_1.17.2_linux_amd64.zip   && \
    wget https://releases.hashicorp.com/hcp/0.4.0/hcp_0.4.0_linux_amd64.zip -O hcp_0.4.0_linux_amd64.zip  && \
    unzip hcp_0.4.0_linux_amd64.zip   && \
    mv hcp /usr/local/bin/hcp && \
    rm hcp_0.4.0_linux_amd64.zip   && \
    curl -OL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
    mv yq_linux_amd64 yq && chmod +x yq && mv yq /usr/local/bin &&  \
    git config --system --add safe.directory / && \
    printf "export CONTAINER_NAME=$CONTAINER_NAME\n" >> /home/runner/.bashrc && \
    ansible-galaxy collection install ansible.builtin

# Ensure directories are writable by root group
RUN for dir in \
      /home/runner \
      /home/runner/.ansible \
      /home/runner/.ansible/tmp \
      /runner \
      /home/runner \
      /runner/env \
      /runner/inventory \
      /runner/project \
      /runner/artifacts ; \
    do mkdir -m 0775 -p $dir ; chmod -R g+rwx $dir ; chgrp -R root $dir ; done && \
    for file in \
      /home/runner/.ansible/galaxy_token \
      /etc/passwd \
      /etc/group ; \
    do touch $file ; chmod g+rw $file ; chgrp root $file ; done


# Add some helpful CLI commands to check versions
RUN set -ex \
    && ansible --version \
    && ansible-lint --version \
    && ansible-runner --version \
    && molecule --version \
    && molecule drivers \
    && podman --version \
    && python3 --version \
    && git --version \
    && ansible-galaxy role list \
    && ansible-galaxy collection list \
    && rpm -qa \
    && uname -a

# Add entrypoint script
ADD _build/entrypoint.sh /bin/entrypoint
RUN chmod +x /bin/entrypoint
ENTRYPOINT ["entrypoint"]
