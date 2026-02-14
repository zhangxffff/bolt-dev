ARG BASE_IMAGE=debian:trixie
FROM ${BASE_IMAGE}

ARG USERNAME
ARG UID
ARG GID
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

ENV DEBIAN_FRONTEND=noninteractive

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
    mold \
    ccache \
    ripgrep \
    ninja-build \
    tmux \
    unzip \
    tzdata \
    openssh-server \
    fish \
    openjdk-21-jdk

RUN apt-get install -y gcc-12 g++-12 && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100 && \
    test "$(gcc -dumpversion | cut -d. -f1)" = "12"

# Install GitHub CLI
RUN (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && sudo mkdir -p -m 755 /etc/apt/sources.list.d \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y

RUN groupadd --gid ${GID} ${USERNAME} && \
    useradd --uid ${UID} --gid ${GID} -m -s /bin/bash ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

RUN usermod -aG sudo ${USERNAME}

RUN mv /usr/bin/ld /usr/bin/ld.bak && \
    ln -s /usr/bin/mold /usr/bin/ld

RUN ssh-keygen -A

RUN chsh -s /usr/bin/fish ${USERNAME}

USER ${USERNAME}

# set default user
ENV USER=${USERNAME}

# Setup SSH directory (authorized_keys will be mounted from host at runtime)
RUN mkdir -p /home/${USERNAME}/.ssh && chmod 700 /home/${USERNAME}/.ssh

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    . /home/${USERNAME}/.local/bin/env && \
    cd /home/${USERNAME} && uv venv && uv pip install pip conan pydot

RUN curl -fsSL https://fnm.vercel.app/install | bash

WORKDIR /home/${USERNAME}

COPY config/fish.config /tmp/

RUN cat /tmp/fish.config >> /home/${USERNAME}/.config/fish/config.fish

RUN fish -lc "conan profile detect"

RUN fish -lc "fnm install 25 && npm i -g @openai/codex && npm i -g opencode-ai"

RUN fish -lc "curl -fsSL https://claude.ai/install.sh | bash"

RUN fish -lc "curl -fsSL https://bun.com/install | bash"

# Switch back to root to run sshd (requires root for port 22 and host keys)
USER root

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
