# syntax=docker/dockerfile:1

FROM node:24-bookworm-slim AS build

ARG PNPM_VERSION=11.28.5
ENV PNPM_HOME=/pnpm
ENV PATH="${PNPM_HOME}:${PATH}"
ENV NODE_OPTIONS=--max-old-space-size=4096

RUN npm install --global "pnpm@${PNPM_VERSION}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      git \
      pkg-config \
      python3 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .

RUN --mount=type=cache,id=dsh-pnpm-store,target=/pnpm/store \
    pnpm install --frozen-lockfile --store-dir /pnpm/store

RUN pnpm run build:artifacts

FROM node:24-bookworm-slim AS runtime

ARG PNPM_VERSION=11.28.5
ENV PNPM_HOME=/pnpm
ENV PATH="${PNPM_HOME}:${PATH}"

RUN npm install --global "pnpm@${PNPM_VERSION}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      openssh-client \
      procps \
      tini \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 1000 dsh \
 && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash dsh

COPY --from=build /app /app
COPY deploy/docker/dsh /usr/local/bin/dsh
COPY deploy/docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY deploy/docker/healthcheck.mjs /usr/local/bin/dsh-healthcheck.mjs

RUN chmod 0755 /usr/local/bin/dsh /usr/local/bin/docker-entrypoint.sh \
 && mkdir -p /home/dsh/.dsh /home/dsh/.agents /workspace \
 && chown -R dsh:dsh /home/dsh /workspace

ENV HOME=/home/dsh \
    DSH_HOME=/home/dsh/.dsh \
    DSH_AGENTS_HOME=/home/dsh/.agents \
    DSH_WEB_PORT=3080

USER dsh
WORKDIR /workspace

EXPOSE 3080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["node", "/usr/local/bin/dsh-healthcheck.mjs"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
