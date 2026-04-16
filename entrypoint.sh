#!/bin/bash

# Start reverse SSH tunnel if configured
if [ -n "$REVERSE_PROXY_HOST" ] && [ -n "$REVERSE_PROXY_PORT" ]; then
    autossh -M 0 -f -N \
        -o "StrictHostKeyChecking=no" \
        -o "ServerAliveInterval=30" \
        -o "ServerAliveCountMax=3" \
        -R "${REVERSE_PROXY_PORT}:localhost:22" \
        "${REVERSE_PROXY_USER:-root}@${REVERSE_PROXY_HOST}"
fi

# Start sshd in foreground
exec /usr/sbin/sshd -D -e
