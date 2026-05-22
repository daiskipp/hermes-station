#!/bin/bash
# Inject GBRAIN MCP token and model settings into Hermes config.yaml.
# Called from docker-compose command before gateway/webui starts.

HERMES_HOME="${HERMES_HOME:-/opt/data}"
TOKEN_FILE="/opt/gbrain-data/mcp-token.txt"
CONFIG="$HERMES_HOME/config.yaml"
MODEL="${HERMES_MODEL:-}"

if [ -f "$CONFIG" ]; then
    TOKEN=""
    if [ -f "$TOKEN_FILE" ]; then
        TOKEN=$(cat "$TOKEN_FILE" | tr -d '\n')
    fi

    source /opt/hermes/.venv/bin/activate
    python3 -c "
import yaml, os

config_path = '$CONFIG'
token = '$TOKEN'
model = '$MODEL'

with open(config_path) as f:
    c = yaml.safe_load(f) or {}

# Inject model if HERMES_MODEL env is set
if model:
    if 'model' not in c:
        c['model'] = {}
    c['model']['default'] = model
    c['model']['provider'] = 'custom'
    c['model']['base_url'] = os.environ.get('OLLAMA_BASE_URL', 'http://host.docker.internal:11434') + '/v1'
    if 'agent' not in c:
        c['agent'] = {}
    c['agent']['reasoning_effort'] = 'none'
    print(f'[setup] Model set to {model}')

# Inject GBRAIN MCP token if available
if token:
    c['mcp_servers'] = {
        'gbrain': {
            'url': 'http://gbrain:3131/mcp',
            'headers': {'Authorization': f'Bearer {token}'},
            'timeout': 120,
            'tools': {
                'include': [
                    'get_page', 'put_page', 'list_pages',
                    'search', 'query',
                    'add_tag', 'get_tags',
                    'get_stats', 'get_health',
                ]
            }
        }
    }
    print('[setup] GBRAIN MCP token injected (9 tools filtered from 66)')

# Inject Honcho self-hosted config if HONCHO_BASE_URL is set
honcho_url = os.environ.get('HONCHO_BASE_URL', '').strip()
if honcho_url:
    if 'memory' not in c:
        c['memory'] = {}
    c['memory']['provider'] = 'honcho'
    print(f'[setup] Honcho provider set (base_url from env: {honcho_url})')

with open(config_path, 'w') as f:
    yaml.dump(c, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
"
else
    echo "[setup] WARNING: config.yaml not found"
fi
