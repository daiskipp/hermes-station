FROM oven/bun:1.2-debian

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl git tini && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/gbrain

# Copy source and install dependencies
COPY vendor/gbrain/package.json vendor/gbrain/bun.lock ./
RUN bun install --frozen-lockfile

COPY vendor/gbrain/ .

# Make gbrain CLI available
RUN bun link

COPY config/gbrain/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV GBRAIN_HOME=/opt/data

VOLUME ["/opt/data"]
EXPOSE 3131

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
