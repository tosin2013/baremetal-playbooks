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
    mkdir -p ~/.ansible/roles /usr/share/ansible/roles /etc/ansible/roles && \
    rm -rf $(pip3 cache dir) && \
    microdnf install -y sshpass openssl wget tar && \
    wget https://github.com/hashicorp/vault/archive/refs/tags/v1.17.2.tar.gz -O vault.tar.gz && \
    tar -xvzf vault.tar.gz  && \
    mv vault /usr/local/bin/vault && \
    rm vault.tar.gz && \
    git config --system --add safe.directory / && \
    printf "export CONTAINER_NAME=$CONTAINER_NAME\n" >> /home/runner/.bashrc

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

COPY collections/ /usr/share/ansible/collections

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