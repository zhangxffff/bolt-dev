#!/bin/bash

HOME_DIR="/home/${USER}"

# Provision/update in the BACKGROUND so sshd and the autossh tunnel come up
# immediately — you can SSH in while it runs, and a hung or failed run never
# blocks login. Everything here is idempotent — dotfiles setup.sh has its own
# per-tool skip/update logic, and the repo-local extras are self-guarding — so
# it just re-runs every boot (keeping dotfiles current); no marker file needed.
echo "Provisioning/updating toolchain in the background; SSH is available now."
WS="${DEV_WORKSPACE:-Workspace}"
(
    # dotfiles: clone if missing, else pull to latest (non-destructive — a
    # diverged/dirty checkout is left as-is so local work is never nuked); then
    # run its setup.sh (installs/updates the ~/.local toolchain + links configs).
    # $WS expands here (root); ~ is left for the user login shell to expand.
    su - "$USER" -s /bin/bash -c "
        set -e
        mkdir -p ~/$WS
        if [ -d ~/$WS/dotfiles/.git ]; then
            git -C ~/$WS/dotfiles checkout main || echo 'dotfiles: checkout main failed; using current branch'
            git -C ~/$WS/dotfiles pull --ff-only || echo 'dotfiles: pull skipped (local changes or diverged); using existing checkout'
        else
            git clone https://github.com/zhangxffff/dotfiles.git ~/$WS/dotfiles
        fi
        ~/$WS/dotfiles/setup.sh
    "

    # Python virtualenv (conan/pydot) — not in dotfiles. Create+seed only if
    # missing, so it is idempotent and never triggers uv's replace prompt.
    su - "$USER" -s /bin/bash -c '
        set -e
        export PATH="$HOME/.local/bin:$PATH"
        [ -d ~/.venv ] || { uv venv && uv pip install pip conan pydot; }
    '

    # conan default profile — detect only if absent (no overwrite, no log noise).
    su - "$USER" -s /usr/bin/fish -lc "conan profile detect 2>/dev/null; or true"

    echo "Provisioning/update complete."
) &

# Persist SSH host keys across rebuilds
HOST_KEY_DIR="${HOME_DIR}/.ssh_host_keys"
if [ -d "$HOST_KEY_DIR" ] && [ -f "$HOST_KEY_DIR/ssh_host_ed25519_key" ]; then
    cp "$HOST_KEY_DIR"/ssh_host_* /etc/ssh/
else
    mkdir -p "$HOST_KEY_DIR"
    ssh-keygen -A
    cp /etc/ssh/ssh_host_* "$HOST_KEY_DIR/"
fi

# Start reverse SSH tunnel only if configured. Runs as the dev user so it picks
# up the host's identity from $HOME_DIR/.ssh (seeded by the init-ssh service).
if [ -n "$REVERSE_PROXY_HOST" ] && [ -n "$REVERSE_PROXY_PORT" ]; then
    su - "$USER" -s /bin/bash -c "autossh -M 0 -f -N \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -R ${REVERSE_PROXY_PORT}:localhost:22 \
        root@${REVERSE_PROXY_HOST}"
else
    echo "REVERSE_PROXY_HOST/PORT not set; skipping autossh reverse tunnel."
fi

# Start sshd in foreground
exec /usr/sbin/sshd -D -e
