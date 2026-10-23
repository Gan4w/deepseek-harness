# syntax=docker/dockerfile:1

FROM node:24-bookworm-slim AS build

ARG PNPM_VERSION=11.28.5
ARG APT_MIRROR=deb.debian.org
ARG DSH_CLIENT_COMMIT_HASH
ENV DSH_CLIENT_COMMIT_HASH=${DSH_CLIENT_COMMIT_HASH}
ENV PNPM_HOME=/pnpm
ENV PATH="${PNPM_HOME}:${PATH}"
ENV NODE_OPTIONS=--max-old-space-size=4096

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do \
      if [ -f "$f" ]; then sed -i "s|deb.debian.org|${APT_MIRROR}|g" "$f"; fi; \
    done \
 && npm install --global "pnpm@${PNPM_VERSION}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      git \
      pkg-config \
      python3

WORKDIR /app

COPY . .

RUN --mount=type=cache,id=dsh-pnpm-store,target=/pnpm/store \
    pnpm install --frozen-lockfile --store-dir /pnpm/store

RUN pnpm run build:artifacts

RUN CI=true pnpm prune --prod --ignore-scripts \
 && for manifest in packages/*/*/package.json vendor/*/package.json apps/*/package.json native/system/package.json native/system/packages/*/package.json; do \
      [ -f "$manifest" ] || continue; \
      name=$(node -p "require('/app/$manifest').name"); \
      [ -n "$name" ] || continue; \
      target="node_modules/$name"; \
      mkdir -p "$(dirname "$target")"; \
      rm -rf "$target"; \
      ln -s "/app/$(dirname "$manifest")" "$target"; \
    done \
 && rm -rf docs snapshots benchmarks website python scripts .agents deploy \
      apps/desktop apps/desktop-host apps/plugin-market-generator \
 && rm -f AGENTS.md BENCHMARK.md BRAND_GUIDELINES.md BRAND_GUIDELINES.zh.md BRAND_GUIDELINES.i18n.yaml \
      CLAUDE.md CONTRIBUTING.md CONTRIBUTING.zh.md CONTRIBUTING.i18n.yaml README.md README.zh.md README.i18n.yaml \
      SAFETY.md SAFETY.zh.md SAFETY.i18n.yaml Makefile lefthook.yml pytest.ini \
      tsconfig.json tsconfig.base.json tsconfig.base.client.json tsconfig.client.json tsconfig.host.json \
      tsconfig.node.base.json tsdown.config.ts vitest.bench.config.ts vitest.config.ts vitest.e2e.config.ts \
      vitest.expected.config.ts vitest.shared.ts vitest.snapshot.config.ts vitest.web-stress.config.ts \
      vitest.web.config.ts vitest.web.perf.config.ts \
 && find packages apps vendor -type d \( -name src -o -name tests -o -name test -o -name fixtures -o -name __tests__ \) -prune -exec rm -rf {} + \
 && find packages apps vendor -type f \( -name '*.map' -o -name '*.tsbuildinfo' -o -name '*.md' \) -delete

FROM node:24-bookworm-slim AS runtime

ARG PNPM_VERSION=11.28.5
ARG APT_MIRROR=deb.debian.org
ENV PNPM_HOME=/pnpm
ENV PATH="${PNPM_HOME}:${PATH}"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do \
      if [ -f "$f" ]; then sed -i "s|deb.debian.org|${APT_MIRROR}|g" "$f"; fi; \
    done \
 && npm install --global "pnpm@${PNPM_VERSION}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      openssh-client \
      procps \
      tini

COPY --from=build /app /app
COPY deploy/docker/dsh /usr/local/bin/dsh
COPY deploy/docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY deploy/docker/healthcheck.mjs /usr/local/bin/dsh-healthcheck.mjs

RUN chmod 0755 /usr/local/bin/dsh /usr/local/bin/docker-entrypoint.sh \
 && chmod -R a+rX /app \
 && mkdir -p /home/dsh/.dsh /home/dsh/.agents /workspace \
 && chown -R 1000:1000 /home/dsh /workspace

ENV HOME=/home/dsh \
    DSH_HOME=/home/dsh/.dsh \
    DSH_AGENTS_HOME=/home/dsh/.agents \
    DSH_WEB_PORT=3080

USER 1000:1000
WORKDIR /workspace

EXPOSE 3080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["node", "/usr/local/bin/dsh-healthcheck.mjs"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
