#!/bin/sh
set -eu

: "${DSH_WEB_PORT:=3080}"
: "${DSH_PUBLIC_URL:=http://localhost:${DSH_PORT:-${DSH_WEB_PORT}}/}"

if [ -z "${DSH_WEB_HOST:-}" ]; then
  DSH_WEB_HOST="$(hostname -i 2>/dev/null | awk '{print $1}')"
fi

if [ -z "${DSH_WEB_HOST:-}" ]; then
  echo "docker-entrypoint: cannot determine a container address; set DSH_WEB_HOST to a concrete local address" >&2
  exit 1
fi

for dir in "${DSH_HOME:-/home/dsh/.dsh}" "${DSH_AGENTS_HOME:-/home/dsh/.agents}"; do
  mkdir -p "$dir"
  if [ ! -w "$dir" ]; then
    echo "docker-entrypoint: $dir is not writable by uid $(id -u); chown the mounted directory to that uid (the image runs as 1000:1000)" >&2
    exit 1
  fi
done

extra=""

if [ -n "${DSH_TRUSTED_HOSTS:-}" ]; then
  for trusted in $(printf '%s' "$DSH_TRUSTED_HOSTS" | tr ',' ' '); do
    [ -n "$trusted" ] || continue
    extra="$extra --trusted-host $trusted"
  done
fi

if [ -n "${DSH_TLS_CERT:-}" ] || [ -n "${DSH_TLS_KEY:-}" ]; then
  if [ -z "${DSH_TLS_CERT:-}" ] || [ -z "${DSH_TLS_KEY:-}" ]; then
    echo "docker-entrypoint: DSH_TLS_CERT and DSH_TLS_KEY must be set together" >&2
    exit 1
  fi
fi

set -- web --no-open --host "$DSH_WEB_HOST" --port "$DSH_WEB_PORT" --public-url "$DSH_PUBLIC_URL" $extra "$@"

if [ -n "${DSH_TLS_CERT:-}" ]; then
  set -- "$@" --tls-cert "$DSH_TLS_CERT" --tls-key "$DSH_TLS_KEY"
fi

exec dsh "$@"
