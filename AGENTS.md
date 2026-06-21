# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) and other agents when working with code in this repository. `CLAUDE.md` is a symlink to this file.

## What this repo is

This is **not an application codebase** — it is the build/runtime definition for a single long-lived containerized remote development environment named `bolt-dev`. The container runs an SSH server so a developer (or editors like Zed/VS Code Remote) can SSH in and do C++/Node/Python work inside it. There is no test suite or app to build here; "building" means building the dev-environment image, and "running" means bringing the container up.

## Commands

```bash
# Build and start the environment (runs init-perms → init-ssh → dev)
docker compose up -d --build

# Rebuild from scratch (image only; the `home` volume persists)
docker compose build --no-cache dev && docker compose up -d

# View logs / sshd output
docker compose logs -f dev

# Get a shell inside the running container (as the dev user)
docker compose exec --user "$DEV_USERNAME" dev fish

# Tear down (KEEPS the home volume and all its data)
docker compose down

# Tear down AND destroy all developer state (uv venv, node, configs, history)
docker compose down -v
```

Access the environment: there are **no published host ports**. Reach it via the Cloudflare tunnel (configure an `ssh://dev:22` public hostname and connect with `cloudflared access ssh`) or the optional autossh reverse tunnel. Local fallback from the Docker host: `docker compose exec --user "$DEV_USERNAME" dev fish`. (Password is `DEV_PASSWORD` from `.env`; key-based auth works if your host `~/.ssh` keys were seeded.)

## Configuration

All deployment parameters live in `.env` (gitignored — never commit it; `.env.*` is gitignored too). These files hold secrets (`DEV_PASSWORD`, the tunnel token), so **do not read or print their contents** — edit blind by key name and validate with `docker compose config --quiet` (which doesn't echo resolved values). Variables consumed by `docker-compose.yml` / `Dockerfile`:

- `BASE_IMAGE` (default base is `debian:trixie`), `UID`/`GID`, `DEV_USERNAME`, `DEV_PASSWORD` — identity of the in-container dev user; UID/GID should match the host user so the bind-mounted volume permissions line up.
- `DEV_WORKSPACE` — workspace dir name under the dev user's home (default `Workspace`); passed into the `dev` container and used by `entrypoint.sh` for the dotfiles clone (`~/$DEV_WORKSPACE/dotfiles`).
- `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` — baked into the image at build time and passed at runtime; required when building behind a corporate proxy.
- `CLOUDFLARE_TUNNEL_TOKEN` — Cloudflare tunnel token (from the Zero Trust dashboard). **This single variable is the entire tunnel config**: set it and the `cloudflared` sidecar connects (container reads it as `TUNNEL_TOKEN`). The sidecar is always defined, but its `restart` policy is **derived from the token** (`restart: ${CLOUDFLARE_TUNNEL_TOKEN:+unless-stopped}`): with a token → `unless-stopped` (survives reboots); empty → resolves to Docker's default `no`, so cloudflared starts, fails (no token), and **exits once — no restart loop**. `dev` doesn't depend on cloudflared, so a failed/exited cloudflared never affects the rest of the stack.
- `REVERSE_PROXY_HOST` / `REVERSE_PROXY_PORT` — optional autossh reverse-SSH tunnel exposing the container's port 22 on a remote jump host. **`entrypoint.sh` skips autossh entirely unless both are set**; it logs in to the jump host as `root` (whose key is seeded from the host's `~/.ssh`) and requests `-R PORT:localhost:22`. The jump host must allow that port (its `sshd_config` `GatewayPorts` setting and firewall) and not already have it bound by a stale forward. Independent of the Cloudflare tunnel — either, both, or neither may be configured.

## Architecture

The environment is assembled in three layers; understanding the split between them matters because they have different rebuild/persistence semantics:

1. **Image build (`Dockerfile`)** — installs system-level, rarely-changing toolchain via apt: `gcc-12`/`g++-12` (pinned via `update-alternatives`, build asserts version 12), `mold` (symlinked over `/usr/bin/ld` so it is the default linker), `cmake`/`ninja`/`ccache`, `ripgrep`, `tmux`, `openjdk-21`, `gh`, `fish`, `openssh-server`, `autossh`. Creates the dev user with passwordless sudo and sets `fish` as their login shell. **Changing tools here requires an image rebuild.**

2. **Per-boot provisioning (`entrypoint.sh`)** — runs **in the background on every boot** so `sshd` and the autossh tunnel come up immediately (you can SSH in while it runs; a hung/failed run never blocks login). It clones the **dotfiles repo** (`github.com/zhangxffff/dotfiles`) into `~/$DEV_WORKSPACE/dotfiles` (default `~/Workspace/dotfiles`), or if already present checks out **main** and `git pull --ff-only`s it to **latest** (each step is guarded: a failed checkout/pull is logged and the existing checkout is used, so a dirty/diverged tree is left as-is), then runs its `setup.sh` — which installs/updates the user toolchain in `~/.local` (uv, node/fnm, claude, codex, pi, opencode, nvim, lazygit, fzf, zellij, tree-sitter, rust) and links the managed fish/nvim configs. (fish itself is not installed by dotfiles — the login shell is the apt `fish` from the `Dockerfile`.) It then adds what dotfiles doesn't cover, each **made idempotent** so re-running every boot is safe: a `~/.venv` (created only if missing) and `conan profile detect` (only if absent). There is **no `~/.initialized` marker** — `setup.sh` and the extras are self-skipping, which is also what keeps dotfiles current on every restart. (fish/shell config is owned entirely by dotfiles; there is no repo-local fish snippet.)

3. **Persistent state (`home` named volume)** — mounted at `/home/$DEV_USERNAME`. This is the single source of durable developer state and survives image rebuilds and `docker compose up`. Everything from layer 2, plus shell history, SSH known_hosts additions, and SSH host keys (`~/.ssh_host_keys`, re-copied into `/etc/ssh` on each boot so client fingerprints stay stable across rebuilds) lives here.

### Startup orchestration

`docker compose up` runs two short-lived init containers before `dev`:
- `init-perms` — `chown $UID:$GID /home` (the volume root only, not recursive) so the dev user owns their home dir on a fresh volume and can write into it; everything beneath is created by the user as themselves.
- `init-ssh` — seeds `~/.ssh` from the host's `~/.ssh` (mounted read-only at `/host-ssh`): copies `authorized_keys`, `id_ed25519[.pub]` fresh each boot, seeds `known_hosts` only once (preserving container-local additions), and fixes permissions.

The `dev` container itself runs as **root** (and `privileged: true`) so `sshd` can bind port 22 and read host keys; the actual development user is assumed only after SSH login (or via `su - $USER` in the entrypoint, which is how provisioning steps drop privileges).

The box can be exposed outside the local network by **two independent, individually-gated mechanisms** — use either, both, or neither:
- **`cloudflared`** sidecar service runs alongside `dev` on the default compose network and reaches it by service name (e.g. `dev:22` for SSH). It runs a token-based Cloudflare Tunnel (`CLOUDFLARE_TUNNEL_TOKEN`, the only knob); public-hostname → service routing is configured remotely in the Cloudflare Zero Trust dashboard. The distroless image uses cloudflared's native entrypoint (no shell), so the token is passed straight through as `TUNNEL_TOKEN`.
- **autossh reverse-SSH tunnel** started by `entrypoint.sh` inside the `dev` container, exposing port 22 on a remote jump host. Gated on `REVERSE_PROXY_HOST`/`REVERSE_PROXY_PORT` — skipped when either is unset.

### Multi-instance / `-p`

No service pins a `container_name`, so the compose project name (set by `-p`, default = the `bolt-dev` directory name) fully isolates instances: `docker compose -p nas up -d` gets its own containers (`nas-dev-1`, …), its own `nas_home` volume, and its own `nas_default` network. **The home volume is per-project**, so `-p nas` is a *fresh* environment, not a second view of the default one — provisioning runs from scratch into `nas_home`. The shared bits across instances: the `.env` build args / dev settings (same user identity) and the `bolt-dev` image tag (built once, reused).

Per-instance Cloudflare token: `CLOUDFLARE_TUNNEL_TOKEN` comes from the shared `.env`, so every instance uses the same token by default. For a different instance, override it per run via the shell: `CLOUDFLARE_TUNNEL_TOKEN=<other> docker compose -p nas up -d`. Don't reuse one token across live instances — that points two connectors at one Cloudflare tunnel. An instance with a blank token just has cloudflared exit once (restart `no`); the rest of that instance runs fine.

### Shell environment

The fish shell config (locale, `~/.venv` activation, `CI_NUM_THREADS`, Zed session handling, and the `~/.local/*/current/bin` PATH wiring) is owned entirely by the **dotfiles** repo (`conf.d/zz-dotfiles.fish`, linked by `setup.sh`). This repo no longer ships its own fish snippet — a second venv activation in a repo-local `config.fish` would restore a stale PATH snapshot and drop the dotfiles tool dirs from `PATH`.
