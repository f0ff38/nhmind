FROM node:20-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates bash \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @acurast/cli@latest

WORKDIR /workspace

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
