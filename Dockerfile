ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

ARG USERNAME=user
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

ENV UID=1001
ENV GID=1001
ENV HTTP_PROXY=${HTTP_PROXY}
ENV HTTPS_PROXY=${HTTPS_PROXY}
ENV NO_PROXY=${NO_PROXY}

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo \
    locales \
    ca-certificates \
    bash-completion \
    build-essential \
    git \
    vim \
    curl \
    wget \
    less \
    cmake \
    mold


RUN locale-gen en_US.UTF-8 zh_CN.UTF-8 && \
    update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN groupadd --gid ${GID} ${USERNAME} && \
    useradd --uid ${UID} --gid ${GID} -m -s /bin/bash ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

RUN usermod -aG sudo ${USERNAME}

RUN mv /usr/bin/ld /usr/bin/ld.bak && \
    ln -s /usr/bin/mold /usr/bin/ld

USER ${USERNAME}

# set default user
ENV USER=${USERNAME}

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    . /home/${USERNAME}/.local/bin/env && \
    cd /home/${USERNAME} && uv venv && uv pip install pip conan pydot

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

ENV NVM_DIR="/home/${USERNAME}/.nvm"

RUN . "${NVM_DIR}/nvm.sh" && nvm install 24

WORKDIR /home/${USERNAME}

RUN cat <<'EOF' > /home/${USERNAME}/.bashrc
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion;
fi
export PS1="[\u@container \W]\\$ "
. ~/.venv/bin/activate
. ~/.nvm/nvm.sh
EOF

RUN . ~/.venv/bin/activate && conan profile detect

CMD ["/bin/bash"]
