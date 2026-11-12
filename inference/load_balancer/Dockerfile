# syntax=docker/dockerfile:1.7
FROM haproxy:3.4.7-alpine3.24

COPY --chown=haproxy:haproxy haproxy.cfg.template /usr/local/etc/haproxy/haproxy.cfg.template
COPY --chown=haproxy:haproxy entrypoint.sh /usr/local/bin/questacase-haproxy-entrypoint

USER root
RUN chmod 0555 /usr/local/bin/questacase-haproxy-entrypoint \
    && mkdir -p /tmp/questacase-haproxy \
    && chown haproxy:haproxy /tmp/questacase-haproxy
USER haproxy

EXPOSE 11434 8404
ENTRYPOINT ["/usr/local/bin/questacase-haproxy-entrypoint"]
