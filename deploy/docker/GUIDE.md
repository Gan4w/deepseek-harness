# Docker deployment

English | [中文](GUIDE.zh.md)

This directory builds and runs the Web UI in a container. Configuration, credentials, sessions, plugins, and skills survive container replacement because they live in mounted volumes, not in the image.

Prerequisites: Docker Engine with Compose v2.24 or newer, and a connection to the npm registry for the first build.

## Quick start

```sh
cd deploy/docker
cp .env.example .env
# Set DEEPSEEK_API_KEY in .env, or configure the model in the Web UI after startup.
docker compose up -d --build
docker compose logs -f dsh
```

Open the URL printed by the startup line. It carries a per-process `?token=` credential that the server exchanges for a signed session cookie, so keep it private. The cookie signing secret is stored in the persistent volume, so browser sessions survive container restarts; the token itself changes and the new one appears in the logs.

The first build installs the pnpm workspace and compiles every artifact. Expect a long build, several GB of image size, and network access to the npm registry.

## Persistent data

| Mount | Default | Contents |
|---|---|---|
| `/home/dsh/.dsh` | named volume `deepseek-harness-dsh-home` | `cordis.patch.yml`, `profiles/<name>/cordis.patch.yml` and `package.json`, installed plugins under `profiles/<name>/node_modules`, `.credentials.yaml`, `.env`, `sessions/`, `storages/`, `attachments/`, `skills/`, `logs/` |
| `/home/dsh/.agents` | named volume `deepseek-harness-dsh-agents` | Shared `AGENTS.md` and `skills/` used across harness installations |
| `/workspace` | host directory `deploy/docker/workspace` | Project files the agent reads and edits; the process working directory and default workspace root |

`docker compose down` keeps both named volumes. `docker compose down -v` deletes them, including configuration, credentials, sessions, and plugins. Do not override `DSH_HOME` or `DSH_AGENTS_HOME` unless you also mount the new paths.

The directory picker's home is the container `$HOME`, `/home/dsh`; anything created there lives only in the container layer and disappears when the container is recreated. Set `HOME=/workspace` in the environment to make the workspace the picker home; `DSH_HOME` and `DSH_AGENTS_HOME` keep their mounted paths.

To use host directories instead of named volumes, set `DSH_HOME_VOLUME` and `DSH_AGENTS_VOLUME` in `.env` to bind paths:

```sh
mkdir -p data/dsh-home data/agents
echo 'DSH_HOME_VOLUME=./data/dsh-home' >> .env
echo 'DSH_AGENTS_VOLUME=./data/agents' >> .env
sudo chown -R 1000:1000 data
```

The container runs as uid/gid `1000`. On Linux, make a bind-mounted directory writable by that identity (`sudo chown -R 1000:1000 data`); otherwise startup fails with a clear error instead of writing root-owned files.

## Configuration

The layered configuration files are persisted with the home volume:

- `$DSH_HOME/cordis.patch.yml` applies to every profile.
- `$DSH_HOME/profiles/web/cordis.patch.yml` is the profile layer written by the Settings UI.
- `$DSH_HOME/.env` is the user environment layer. `DSH_HOME`, `DSH_AGENTS_HOME`, and `XDG_*` cannot be set there; provider keys and proxy variables can.

With the default named volumes, inspect or edit them through `docker compose exec dsh` or copy files in and out:

```sh
docker compose cp dsh:/home/dsh/.dsh/profiles/web/cordis.patch.yml ./cordis.patch.yml
docker compose cp ./cordis.patch.yml dsh:/home/dsh/.dsh/profiles/web/cordis.patch.yml
docker compose restart dsh
```

Bind-mounted home directories are directly editable from the host.

## Plugins

Plugins are pnpm packages installed into the active profile, so they persist in `/home/dsh/.dsh/profiles/web`:

```sh
docker compose exec dsh dsh plugin --profile web add <package>
docker compose exec dsh dsh plugin --profile web list
```

To install before the Web process starts, override the entrypoint:

```sh
docker compose run --rm --entrypoint dsh dsh plugin --profile web add <package>
```

The image includes pnpm, Git, and OpenSSH, so registry and Git-hosted plugins work. Restart the container if a plugin requires a process restart.

## Networking and access

`dsh web` refuses wildcard bind addresses, so the entrypoint binds the container's own interface address and Docker publishes the port. The startup URL defaults to `http://localhost:3080/`, which matches the default host mapping.

- Local access: keep `DSH_BIND_ADDRESS=127.0.0.1` (the default) and use the printed URL.
- Changed host port: set `DSH_PORT` to the host port and `DSH_PUBLIC_URL` to the matching URL.
- LAN access: set `DSH_BIND_ADDRESS=0.0.0.0`, add a stable host name to `DSH_TRUSTED_HOSTS`, and set `DSH_PUBLIC_URL` to the URL browsers use.
- Use a host name, not an IP address. A DHCP lease change forces an IP entry to be edited, while the machine name, an mDNS `.local` name, or a DNS record survives it. A port-less entry matches every port; the fence has no wildcard or CIDR form, and an unknown authority returns 403 for every API call, including the workspace directory picker, even when the page itself loaded.
- Tunnel or reverse proxy: point it at the published port, keep the browser `Host` header unchanged, and forward WebSocket `Upgrade` requests. Add the public domain to `DSH_TRUSTED_HOSTS` and set `DSH_PUBLIC_URL` to the public URL. Cookies bind to one authority, so the LAN name and the tunnel domain each need their own launch-token exchange, and a proxy that rewrites `Host` to a loopback name makes `Origin` and `Host` disagree.
- Reverse proxy and TLS: follow [public deployments](../../docs/user/guide/public-deployments.md). Terminate TLS at the proxy or pass `DSH_TLS_CERT`/`DSH_TLS_KEY` to the entrypoint and advertise an `https://` URL.

Anyone who can reach the port and obtain the startup token can control the agent, which can execute commands inside the container. Publish the port only to trusted networks.

## Sandbox

Agent commands default to the `workspace-write` policy, which uses bwrap or Landlock on Linux and confines writes to `/workspace`. Modern kernels provide Landlock; if the host cannot run either backend, command execution fails closed with `SANDBOX_UNAVAILABLE`. When the container itself is the intended isolation boundary, set `DSH_PERMISSION_MODE=danger-full-access` to run commands without the inner sandbox and without approval prompts.

## Upgrade and backup

```sh
docker compose build --pull
docker compose up -d
```

The build replaces `/app` only; named volumes are untouched. To back up state:

```sh
docker run --rm -v deepseek-harness-dsh-home:/data -v "$PWD":/backup alpine tar czf /backup/dsh-home.tgz -C /data .
docker run --rm -v deepseek-harness-dsh-agents:/data -v "$PWD":/backup alpine tar czf /backup/dsh-agents.tgz -C /data .
```

Restore into empty volumes and hand them back to uid `1000`, then start the service:

```sh
docker run --rm -v deepseek-harness-dsh-home:/data -v "$PWD":/backup alpine sh -c 'tar xzf /backup/dsh-home.tgz -C /data && chown -R 1000:1000 /data'
docker run --rm -v deepseek-harness-dsh-agents:/data -v "$PWD":/backup alpine sh -c 'tar xzf /backup/dsh-agents.tgz -C /data && chown -R 1000:1000 /data'
```
