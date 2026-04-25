#!/bin/bash

HOME_DIR="/home/${USER}"
INIT_MARKER="${HOME_DIR}/.initialized"

# First-time home directory setup (runs as root, installs as user)
if [ ! -f "$INIT_MARKER" ]; then
    echo "First boot: initializing home directory..."

    # uv + venv + pip packages
    su - "$USER" -s /bin/bash -c '
        curl -LsSf https://astral.sh/uv/install.sh | sh
        . ~/.local/bin/env
        cd ~ && uv venv && uv pip install pip conan pydot
    '

    # fnm + node + npm global packages
    su - "$USER" -s /bin/bash -c 'curl -fsSL https://fnm.vercel.app/install | bash'
    su - "$USER" -s /usr/bin/fish -lc "fnm install 25 && npm i -g @openai/codex && npm i -g opencode-ai"

    # fish config
    su - "$USER" -s /bin/bash -c "cat /tmp/fish.config >> ~/.config/fish/config.fish"

    # conan profile
    su - "$USER" -s /usr/bin/fish -lc "conan profile detect"

    # claude cli
    su - "$USER" -s /usr/bin/fish -lc "curl -fsSL https://claude.ai/install.sh | bash"

    # bun
    su - "$USER" -s /usr/bin/fish -lc "curl -fsSL https://bun.com/install | bash"

    touch "$INIT_MARKER"
    echo "Home directory initialized."
fi

# Persist SSH host keys across rebuilds
HOST_KEY_DIR="${HOME_DIR}/.ssh_host_keys"
if [ -d "$HOST_KEY_DIR" ] && [ -f "$HOST_KEY_DIR/ssh_host_ed25519_key" ]; then
    cp "$HOST_KEY_DIR"/ssh_host_* /etc/ssh/
else
    mkdir -p "$HOST_KEY_DIR"
    ssh-keygen -A
    cp /etc/ssh/ssh_host_* "$HOST_KEY_DIR/"
fi

# Start reverse SSH tunnel if configured. Runs as the dev user so it picks up
# the host's identity from $HOME_DIR/.ssh (seeded by the init-ssh service).
if [ -n "$REVERSE_PROXY_HOST" ] && [ -n "$REVERSE_PROXY_PORT" ]; then
    su - "$USER" -s /bin/bash -c "autossh -M 0 -f -N \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -R ${REVERSE_PROXY_PORT}:localhost:22 \
        ${REVERSE_PROXY_USER:-root}@${REVERSE_PROXY_HOST}"
fi

# Start sshd in foreground
exec /usr/sbin/sshd -D -e
