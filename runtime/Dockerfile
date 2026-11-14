# syntax=docker/dockerfile:1.7
ARG OLLAMA_VERSION=0.40.15
FROM ollama/ollama:${OLLAMA_VERSION}

ARG OLLAMA_MODEL=qwen3:4b
ENV OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_MODEL=${OLLAMA_MODEL} \
    OLLAMA_KEEP_ALIVE=24h \
    OLLAMA_MAX_LOADED_MODELS=1 \
    OLLAMA_NUM_PARALLEL=1

# Bake the model into the image so an EC2 inference node does not need to
# download model weights when it starts.
RUN sh -eux -c '\
    ollama serve >/tmp/ollama-build.log 2>&1 & \
    server_pid=$!; \
    trap "kill ${server_pid} 2>/dev/null || true" EXIT; \
    attempts=0; \
    until ollama list >/dev/null 2>&1; do \
      attempts=$((attempts + 1)); \
      if [ "${attempts}" -ge 120 ]; then \
        cat /tmp/ollama-build.log; \
        exit 1; \
      fi; \
      sleep 1; \
    done; \
    ollama pull "${OLLAMA_MODEL}"; \
    kill "${server_pid}"; \
    wait "${server_pid}" || true; \
    trap - EXIT; \
    rm -f /tmp/ollama-build.log'

EXPOSE 11434

HEALTHCHECK --interval=15s --timeout=10s --start-period=30s --retries=6 \
  CMD ["ollama", "list"]

ENTRYPOINT ["/bin/ollama"]
CMD ["serve"]
