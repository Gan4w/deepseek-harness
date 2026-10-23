# Docker 部署

[English](GUIDE.md) | 中文

本目录用于在容器中构建并运行 Web UI。配置、凭据、会话、插件和技能都保存在挂载卷中，而不是镜像里，因此替换容器不会丢失数据。

前提条件：Docker Engine 与 Compose v2.24 或更新版本，且首次构建时可访问 npm registry。

## 快速开始

```sh
cd deploy/docker
cp .env.example .env
# Set DEEPSEEK_API_KEY in .env, or configure the model in the Web UI after startup.
docker compose up -d --build
docker compose logs -f dsh
```

打开启动日志中打印的 URL。该 URL 携带仅在当前进程有效的 `?token=` 凭据，服务端会将其换取签名的会话 cookie，因此不要泄露。cookie 签名密钥保存在持久卷中，所以容器重启后浏览器会话仍然有效；token 本身会变化，新 token 会出现在日志里。

首次构建会安装 pnpm workspace 并编译全部产物。构建时间较长，镜像体积会达到数 GB，并且需要访问 npm registry。

## 持久化数据

| 挂载点 | 默认值 | 内容 |
|---|---|---|
| `/home/dsh/.dsh` | 命名卷 `deepseek-harness-dsh-home` | `cordis.patch.yml`、`profiles/<name>/cordis.patch.yml` 和 `package.json`、`profiles/<name>/node_modules` 下已安装的插件、`.credentials.yaml`、`.env`、`sessions/`、`storages/`、`attachments/`、`skills/`、`logs/` |
| `/home/dsh/.agents` | 命名卷 `deepseek-harness-dsh-agents` | 跨 harness 安装共享的 `AGENTS.md` 与 `skills/` |
| `/workspace` | 宿主机目录 `deploy/docker/workspace` | agent 读取和编辑的项目文件；进程工作目录和默认 workspace 根目录 |

`docker compose down` 会保留两个命名卷。`docker compose down -v` 会删除它们，包括配置、凭据、会话和插件。除非同时挂载了新路径，否则不要覆盖 `DSH_HOME` 或 `DSH_AGENTS_HOME`。

目录选择器的“主目录”是容器的 `$HOME`，即 `/home/dsh`；在那里创建的内容只存在于容器可写层，容器重建后就会消失。在环境中设置 `HOME=/workspace` 可把工作区作为选择器主目录；`DSH_HOME` 和 `DSH_AGENTS_HOME` 仍使用各自的挂载路径。

要用宿主机目录代替命名卷，请在 `.env` 中把 `DSH_HOME_VOLUME` 和 `DSH_AGENTS_VOLUME` 设置为绑定路径：

```sh
mkdir -p data/dsh-home data/agents
echo 'DSH_HOME_VOLUME=./data/dsh-home' >> .env
echo 'DSH_AGENTS_VOLUME=./data/agents' >> .env
sudo chown -R 1000:1000 data
```

容器以 uid/gid `1000` 运行。在 Linux 上，请让绑定挂载目录对该身份可写（`sudo chown -R 1000:1000 data`）；否则启动会明确报错，而不是写出 root 拥有的文件。

## 配置

分层配置文件随 home 卷一起持久化：

- `$DSH_HOME/cordis.patch.yml` 对所有 profile 生效。
- `$DSH_HOME/profiles/web/cordis.patch.yml` 是设置界面写入的 profile 层。
- `$DSH_HOME/.env` 是用户环境层。`DSH_HOME`、`DSH_AGENTS_HOME` 和 `XDG_*` 不能在这里设置；提供商密钥和代理变量可以。

使用默认命名卷时，可通过 `docker compose exec dsh` 查看或编辑，也可以来回复制文件：

```sh
docker compose cp dsh:/home/dsh/.dsh/profiles/web/cordis.patch.yml ./cordis.patch.yml
docker compose cp ./cordis.patch.yml dsh:/home/dsh/.dsh/profiles/web/cordis.patch.yml
docker compose restart dsh
```

绑定挂载的 home 目录可以直接在宿主机上编辑。

## 插件

插件是安装到当前 profile 的 pnpm 包，因此会持久化在 `/home/dsh/.dsh/profiles/web`：

```sh
docker compose exec dsh dsh plugin --profile web add <package>
docker compose exec dsh dsh plugin --profile web list
```

要在 Web 进程启动前安装，请覆盖 entrypoint：

```sh
docker compose run --rm --entrypoint dsh dsh plugin --profile web add <package>
```

镜像包含 pnpm、Git 和 OpenSSH，因此 registry 插件和 Git 托管插件都可用。如果插件要求重启进程，请重启容器。

## 网络与访问

`dsh web` 拒绝通配符绑定地址，因此 entrypoint 绑定容器自身的接口地址，再由 Docker 发布端口。启动 URL 默认是 `http://localhost:3080/`，与默认的宿主机端口映射一致。

- 本机访问：保持 `DSH_BIND_ADDRESS=127.0.0.1`（默认值），使用打印出的 URL。
- 修改宿主机端口：把 `DSH_PORT` 设为宿主机端口，并把 `DSH_PUBLIC_URL` 设为对应的 URL。
- 局域网访问：设置 `DSH_BIND_ADDRESS=0.0.0.0`，把稳定的主机名加入 `DSH_TRUSTED_HOSTS`，并把 `DSH_PUBLIC_URL` 设为浏览器使用的 URL。
- 使用主机名而不是 IP 地址。DHCP 续租会改变 IP 并迫使修改信任配置，而计算机名、mDNS `.local` 名或 DNS 记录不受影响。不带端口的条目匹配任意端口；信任栅栏不支持通配符或网段，未知 authority 的每个 API 调用都会返回 403，包括工作区目录选择器，即使页面本身已经打开。
- 隧道或反向代理：指向已发布的端口，原样保留浏览器 `Host` 头，并转发 WebSocket `Upgrade` 请求。把公网域名加入 `DSH_TRUSTED_HOSTS`，并把 `DSH_PUBLIC_URL` 设为公网 URL。Cookie 绑定单个 authority，因此局域网主机名和隧道域名各自需要一次启动令牌交换；把 `Host` 改写成 loopback 名的代理会让 `Origin` 与 `Host` 不一致。
- 反向代理与 TLS：遵循[公开部署指南](../../docs/user/guide/public-deployments.zh.md)。在代理处终止 TLS，或把 `DSH_TLS_CERT`/`DSH_TLS_KEY` 传给 entrypoint，并公布 `https://` URL。

任何能访问该端口并取得启动 token 的人都能控制 agent，而 agent 可以在容器内执行命令。请只把端口发布到可信网络。

## 沙箱

Agent 命令默认使用 `workspace-write` 策略，在 Linux 上通过 bwrap 或 Landlock 把写入限制在 `/workspace`。现代内核提供 Landlock；如果宿主机两个后端都无法运行，命令执行会以 `SANDBOX_UNAVAILABLE` 失败关闭。当容器本身就是预期的隔离边界时，设置 `DSH_PERMISSION_MODE=danger-full-access`，即可在不启用内部沙箱、也不弹出审批提示的情况下运行命令。

## 升级与备份

```sh
docker compose build --pull
docker compose up -d
```

构建只替换 `/app`；命名卷不受影响。备份状态：

```sh
docker run --rm -v deepseek-harness-dsh-home:/data -v "$PWD":/backup alpine tar czf /backup/dsh-home.tgz -C /data .
docker run --rm -v deepseek-harness-dsh-agents:/data -v "$PWD":/backup alpine tar czf /backup/dsh-agents.tgz -C /data .
```

恢复到空卷并把所有权交还给 uid `1000`，然后启动服务：

```sh
docker run --rm -v deepseek-harness-dsh-home:/data -v "$PWD":/backup alpine sh -c 'tar xzf /backup/dsh-home.tgz -C /data && chown -R 1000:1000 /data'
docker run --rm -v deepseek-harness-dsh-agents:/data -v "$PWD":/backup alpine sh -c 'tar xzf /backup/dsh-agents.tgz -C /data && chown -R 1000:1000 /data'
```
