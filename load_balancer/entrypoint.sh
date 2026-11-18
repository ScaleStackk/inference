#!/bin/sh
set -eu

template=/usr/local/etc/haproxy/haproxy.cfg.template
generated=/tmp/questacase-haproxy/haproxy.cfg
nodes=${INFERENCE_NODES:-}
max_connections=${INFERENCE_MAX_CONNECTIONS:-1}
tls_ca_file=${INFERENCE_TLS_CA_FILE:-/etc/ssl/certs/ca-certificates.crt}
servers=/tmp/questacase-haproxy/servers.cfg

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
: >"${servers}"

old_ifs=${IFS}
IFS=,
index=0
backend_scheme=
tls_host=
for raw_node in ${nodes}; do
  IFS=${old_ifs}
  node=$(printf '%s' "${raw_node}" | tr -d '[:space:]')
  scheme=http
  case "${node}" in
    https://*)
      scheme=https
      node=${node#https://}
      node=${node%/}
      ;;
    http://*)
      node=${node#http://}
      node=${node%/}
      ;;
  esac

  if printf '%s' "${node}" | grep -Eq '[/@?#]'; then
    echo "Invalid inference node ${raw_node}; use a base origin without a path, query or credentials" >&2
    exit 1
  fi
  if ! printf '%s' "${node}" | grep -Eq '^[A-Za-z0-9._-]+(:[0-9]+)?$'; then
    echo "Invalid inference node ${raw_node}; expected host:port or an http(s) base origin" >&2
    exit 1
  fi

  if [ -z "${backend_scheme}" ]; then
    backend_scheme=${scheme}
  elif [ "${backend_scheme}" != "${scheme}" ]; then
    echo "Do not mix HTTP and HTTPS inference nodes in one load-balancer backend" >&2
    exit 1
  fi

  host=${node%%:*}
  if [ "${node}" = "${host}" ]; then
    if [ "${scheme}" = "https" ]; then
      port=443
    else
      port=80
    fi
  else
    port=${node##*:}
  fi

  index=$((index + 1))
  if [ "${scheme}" = "https" ]; then
    if [ "${index}" -gt 1 ]; then
      echo "HTTPS mode currently accepts one origin because its Host header is rewritten for that origin" >&2
      exit 1
    fi
    if [ ! -r "${tls_ca_file}" ]; then
      echo "HTTPS inference requires a readable CA bundle at ${tls_ca_file}" >&2
      exit 1
    fi
    tls_host=${host}
    printf '    server inference_%s %s:%s ssl verify required ca-file %s sni str(%s) check check-sni %s inter 5s fall 3 rise 2 maxconn %s\n' \
      "${index}" "${host}" "${port}" "${tls_ca_file}" "${host}" "${host}" "${max_connections}" >>"${servers}"
  else
    printf '    server inference_%s %s:%s check inter 5s fall 3 rise 2 maxconn %s\n' \
      "${index}" "${host}" "${port}" "${max_connections}" >>"${servers}"
  fi
  IFS=,
done
IFS=${old_ifs}

if [ "${index}" -eq 0 ]; then
  echo "INFERENCE_NODES did not contain any nodes" >&2
  exit 1
fi

if [ "${backend_scheme}" = "https" ]; then
  cat >>"${generated}" <<EOF
    option httpchk
    http-check send meth GET uri /api/tags ver HTTP/1.1 hdr Host ${tls_host}
    http-check expect status 200
    http-request set-header Host ${tls_host}
EOF
else
  cat >>"${generated}" <<'EOF'
    option httpchk
    http-check send meth GET uri /api/tags ver HTTP/1.1 hdr Host localhost
    http-check expect status 200
EOF
fi
cat "${servers}" >>"${generated}"

haproxy -c -f "${generated}"
exec haproxy -W -db -f "${generated}"
