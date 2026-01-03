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
    tmux

RUN GCC_VERSION=12.5.0 &&  \
    wget https://mirrors.aliyun.com/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz -P /tmp && \
    tar -xzvf /tmp/gcc-${GCC_VERSION}.tar.gz -C /tmp && cd $(realpath /tmp/gcc-${GCC_VERSION}) && \
    ./contrib/download_prerequisites && \
    ./configure --prefix=/usr/ --enable-checking=release --enable-languages=c,c++ --disable-multilib && \
    make -j $(nproc) && make install-strip && \
    ldconfig && rm -rf  /tmp/gcc*

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

WORKDIR /home/${USERNAME}

RUN cat <<'EOF' > /home/${USERNAME}/.bashrc
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion;
fi
export PS1="[\u@container \W]\\$ "
. ~/.venv/bin/activate
. ~/.nvm/nvm.sh
export CI_NUM_THREADS=$(nproc)
EOF

RUN bash -lc "conan profile detect"

RUN bash -lc "nvm install 24 && npm i -g @openai/codex && npm install -g @google/gemini-cli"

CMD ["/bin/bash"]
