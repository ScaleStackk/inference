#!/bin/sh
set -eu

template=/usr/local/etc/haproxy/haproxy.cfg.template
generated=/tmp/questacase-haproxy/haproxy.cfg
nodes=${INFERENCE_NODES:-}
max_connections=${INFERENCE_MAX_CONNECTIONS:-1}

if [ -z "${nodes}" ]; then
  echo "INFERENCE_NODES is required, for example 10.0.2.10:11434,10.0.3.10:11434" >&2
  exit 1
fi

case "${max_connections}" in
  ''|*[!0-9]*|0)
    echo "INFERENCE_MAX_CONNECTIONS must be a positive integer" >&2
    exit 1
    ;;
esac

cp "${template}" "${generated}"

old_ifs=${IFS}
IFS=,
index=0
for raw_node in ${nodes}; do
  IFS=${old_ifs}
  node=$(printf '%s' "${raw_node}" | tr -d '[:space:]')
  if ! printf '%s' "${node}" | grep -Eq '^[A-Za-z0-9._-]+:[0-9]+$'; then
    echo "Invalid inference node ${raw_node}; expected private-host-or-ip:port" >&2
    exit 1
  fi
  index=$((index + 1))
  printf '    server inference_%s %s check inter 5s fall 3 rise 2 maxconn %s\n' \
    "${index}" "${node}" "${max_connections}" >>"${generated}"
  IFS=,
done
IFS=${old_ifs}

if [ "${index}" -eq 0 ]; then
  echo "INFERENCE_NODES did not contain any nodes" >&2
  exit 1
fi

haproxy -c -f "${generated}"
exec haproxy -W -db -f "${generated}"
