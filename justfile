# hermes-station task runner

set dotenv-load

# Start core services (Hermes + webui)
up:
    git submodule update --init --recursive
    @just _init-data
    docker compose up -d --build
    @sleep 3
    @just health
    @echo ""
    @echo "========================================="
    @echo "  hermes-station is running (core)"
    @echo "========================================="
    @echo "  Chat UI:   http://localhost:${WEBUI_PORT:-8787}"
    @echo "  Hermes:    http://localhost:${HERMES_DASHBOARD_PORT:-9119}"
    @echo "  Model:     ${OLLAMA_MODEL:-qwen3.6:27b-coding-nvfp4}"
    @echo "========================================="
    @echo "  Run 'just all-up' to also start Postgres, GBRAIN, Honcho, Dashboard"

# Start all services (core + Postgres + GBRAIN + Honcho + Dashboard)
all-up:
    git submodule update --init --recursive
    @just _init-data
    docker compose --profile full up -d --build
    @sleep 3
    @just health
    @echo ""
    @echo "========================================="
    @echo "  hermes-station is running (full)"
    @echo "========================================="
    @echo "  Chat UI:   http://localhost:${WEBUI_PORT:-8787}"
    @echo "  Hermes:    http://localhost:${HERMES_DASHBOARD_PORT:-9119}"
    @echo "  Monitor:   http://localhost:${DASHBOARD_PORT:-8080}"
    @echo "  Model:     ${OLLAMA_MODEL:-qwen3.6:27b-coding-nvfp4}"
    @echo "========================================="

# Health check all running services
health:
    @echo "=== Postgres ==="
    @docker compose exec -T postgres pg_isready -U ${POSTGRES_USER:-agentos} 2>/dev/null && echo "OK" || echo "FAIL"
    @echo "=== Hermes ==="
    @docker compose exec -T hermes bash -c "source /opt/hermes/.venv/bin/activate && hermes status" 2>/dev/null && echo "OK" || echo "FAIL"
    @echo "=== hermes-webui ==="
    @curl -sf http://localhost:${WEBUI_PORT:-8787} > /dev/null 2>&1 && echo "OK" || echo "FAIL"
    @echo "=== GBRAIN ==="
    @docker compose exec -T gbrain curl -sf http://localhost:${GBRAIN_PORT:-3131}/health > /dev/null 2>&1 && echo "OK" || echo "SKIP (not running)"
    @echo "=== Honcho ==="
    @docker compose exec -T honcho /app/.venv/bin/python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=2).read(); print('OK')" 2>/dev/null || echo "SKIP (not running)"
    @echo "=== Dashboard ==="
    @curl -sf http://localhost:${DASHBOARD_PORT:-8080} > /dev/null 2>&1 && echo "OK" || echo "SKIP (not running)"

# Stop all services
down:
    docker compose --profile full down

# Full cleanup: containers, volumes, agent data
[confirm("This will DELETE all agent data in $AGENT_DATA. Continue?")]
clean:
    docker compose --profile full down -v --rmi local --remove-orphans
    rm -rf "${AGENT_DATA:-$HOME/agent-data}/postgres" "${AGENT_DATA:-$HOME/agent-data}/hermes" "${AGENT_DATA:-$HOME/agent-data}/gbrain" "${AGENT_DATA:-$HOME/agent-data}/honcho"
    @echo "Cleaned. Run 'just up' to rebuild."

# View logs (e.g. just logs postgres, just logs -f)
logs *args:
    docker compose logs {{ args }}

# Connect to Postgres CLI
psql:
    docker compose exec postgres psql -U ${POSTGRES_USER:-agentos} -d ${POSTGRES_DB:-agentos}

# Show service status
status:
    docker compose --profile full ps

# Show pinned versions
versions:
    @echo "=== Submodule versions ==="
    @cd vendor/hermes-agent && echo "hermes-agent: $(git describe --tags 2>/dev/null || git rev-parse --short HEAD)"
    @cd vendor/honcho && echo "honcho:       $(git describe --tags 2>/dev/null || git rev-parse --short HEAD)"
    @cd vendor/gbrain && echo "gbrain:       $(git describe --tags 2>/dev/null || git rev-parse --short HEAD)"
    @echo "=== Docker images ==="
    @echo "hermes-webui: $(docker inspect ghcr.io/nesquena/hermes-webui:latest --format '{{{{.RepoDigests}}}}' 2>/dev/null | head -1 || echo 'not pulled')"

# Update all vendor submodules to latest tags and rebuild
update:
    @echo "Fetching latest tags..."
    cd vendor/hermes-agent && git fetch --tags && git checkout $(git describe --tags $(git rev-list --tags --max-count=1))
    cd vendor/honcho && git fetch --tags && git checkout $(git describe --tags $(git rev-list --tags --max-count=1))
    cd vendor/gbrain && git fetch origin && git checkout origin/master
    docker pull ghcr.io/nesquena/hermes-webui:latest
    @echo "Rebuilding..."
    docker compose --profile full up -d --build
    @just versions

# Update a specific service (e.g. just update-service hermes)
update-service service:
    #!/usr/bin/env bash
    case "{{ service }}" in
        hermes)  cd vendor/hermes-agent && git fetch --tags && git checkout $(git describe --tags $(git rev-list --tags --max-count=1)) ;;
        honcho)  cd vendor/honcho && git fetch --tags && git checkout $(git describe --tags $(git rev-list --tags --max-count=1)) ;;
        gbrain)  cd vendor/gbrain && git fetch origin && git checkout origin/master ;;
        webui)   docker pull ghcr.io/nesquena/hermes-webui:latest ;;
        *)       echo "Unknown service: {{ service }}. Use: hermes, honcho, gbrain, webui" && exit 1 ;;
    esac
    docker compose --profile full up -d --build {{ service }}

# Rebuild a specific service without updating
rebuild service:
    docker compose --profile full up -d --build {{ service }}

# Create AGENT_DATA layout (idempotent; called by up / all-up)
_init-data:
    @mkdir -p \
        "${AGENT_DATA:?Set AGENT_DATA in .env}/hermes" \
        "${AGENT_DATA}/gbrain" \
        "${AGENT_DATA}/honcho" \
        "${AGENT_DATA}/postgres" \
        "${AGENT_DATA}/inbox/chatgpt" \
        "${AGENT_DATA}/inbox/claude" \
        "${AGENT_DATA}/inbox/hermes" \
        "${AGENT_DATA}/inbox/manual" \
        "${AGENT_DATA}/backups"

# Snapshot AGENT_DATA to a timestamped tarball under $AGENT_DATA/backups.
# Uses pg_dumpall for Postgres (logical backup) — never tars live PGDATA.
backup:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${AGENT_DATA:?Set AGENT_DATA in .env}"
    ts="$(date +%Y%m%d-%H%M%S)"
    out="${AGENT_DATA}/backups/hermes-station-${ts}.tar.gz"
    mkdir -p "${AGENT_DATA}/backups"

    stage="$(mktemp -d)"
    trap 'rm -rf "$stage"' EXIT

    pg_running=0
    if docker compose ps --status=running --services 2>/dev/null | grep -qx postgres; then
        pg_running=1
        echo "Dumping Postgres via pg_dumpall..."
        mkdir -p "${stage}/_postgres-dump"
        docker compose exec -T postgres pg_dumpall -U "${POSTGRES_USER:-agentos}" \
            > "${stage}/_postgres-dump/dumpall.sql"
    else
        echo "Postgres is not running — skipping SQL dump."
        echo "  (live PGDATA is excluded from the archive either way; restart Postgres and re-run for DB backup)"
    fi

    echo "Creating backup: ${out}"
    # Always exclude live PGDATA (./postgres) and our own backups dir.
    # PGDATA bytes are version-locked and unsafe to copy from a running cluster.
    if [ "$pg_running" = "1" ]; then
        tar -czf "${out}" \
            -C "${AGENT_DATA}" --exclude='./backups' --exclude='./postgres' . \
            -C "${stage}" .
    else
        tar -czf "${out}" \
            -C "${AGENT_DATA}" --exclude='./backups' --exclude='./postgres' .
    fi
    echo "Done: $(du -h "${out}" | cut -f1)  ${out}"
    [ "$pg_running" = "1" ] && echo "  contains: _postgres-dump/dumpall.sql"

# Restore AGENT_DATA from a backup tarball (just restore path/to/backup.tar.gz).
# Replays _postgres-dump/dumpall.sql via a freshly-initialized Postgres if present.
restore archive:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${AGENT_DATA:?Set AGENT_DATA in .env}"
    if [ ! -f "{{ archive }}" ]; then echo "Not found: {{ archive }}"; exit 1; fi
    echo "WARNING: this will overwrite files under ${AGENT_DATA} (backups/ preserved)."
    echo "         The live Postgres data dir (${AGENT_DATA}/postgres) will be wiped."
    read -r -p "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

    docker compose --profile full down 2>/dev/null || true
    rm -rf "${AGENT_DATA}/postgres" "${AGENT_DATA}/_postgres-dump"
    tar -C "${AGENT_DATA}" -xzf "{{ archive }}"

    if [ -f "${AGENT_DATA}/_postgres-dump/dumpall.sql" ]; then
        echo "Found SQL dump — starting Postgres to replay..."
        docker compose --profile full up -d postgres
        for i in $(seq 1 30); do
            docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-agentos}" >/dev/null 2>&1 && break
            sleep 1
        done
        docker compose exec -T postgres psql -U "${POSTGRES_USER:-agentos}" -d postgres \
            < "${AGENT_DATA}/_postgres-dump/dumpall.sql"
        rm -rf "${AGENT_DATA}/_postgres-dump"
        echo "Postgres restored from dump."
    else
        echo "No SQL dump in archive — Postgres will start empty on next 'just all-up'."
    fi
    echo "Restored from {{ archive }}. Run 'just up' or 'just all-up' to start."
