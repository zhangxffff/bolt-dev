# 你也可以改成 ubuntu:24.04
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ------- 参数（docker-compose 会传入） -------
ARG USERNAME=zhangxffff
ARG UID=1000
ARG GID=1000

# ------- 基础环境安装 -------
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
    less


# ------- 设置 Locale -------
RUN locale-gen en_US.UTF-8 zh_CN.UTF-8 && \
    update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# ------- 创建非 root 用户 + sudo 权限 -------
RUN groupadd --gid ${GID} ${USERNAME} && \
    useradd --uid ${UID} --gid ${GID} -m -s /bin/bash ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# ------- 切换为非 root 用户 -------
USER ${USERNAME}

# set default user
ENV USER=${USERNAME}

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    . /home/${USERNAME}/.local/bin/env && \
    cd /home/${USERNAME} && uv venv && uv pip install pip && uv pip install conan

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

ENV NVM_DIR="/home/${USERNAME}/.nvm"

RUN . "${NVM_DIR}/nvm.sh" && nvm install 24

# ------- 工作目录 -------
WORKDIR /home/${USERNAME}

# ------- 用户体验增强（可选）-------
RUN cat <<'EOF' > /home/${USERNAME}/.bashrc
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion;
fi
export PS1="[\u@container \W]\\$ "
. ~/.venv/bin/activate
. ~/.nvm/nvm.sh
EOF


# ------- 默认执行命令 -------
CMD ["/bin/bash"]
