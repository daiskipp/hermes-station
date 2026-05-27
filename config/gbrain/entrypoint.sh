#!/bin/bash
set -e

GBRAIN_HOME="${GBRAIN_HOME:-/opt/data}"
GBRAIN_PORT="${GBRAIN_PORT:-3131}"
TOKEN_FILE="${GBRAIN_HOME}/mcp-token.txt"
mkdir -p "$GBRAIN_HOME"

# Initialize brain on first run (PGLite, no external DB needed)
if [ ! -f "$GBRAIN_HOME/config.json" ]; then
    echo "First run: initializing GBRAIN with PGLite..."
    gbrain init --pglite --non-interactive 2>/dev/null || true
fi

# Configure Ollama as embedding provider if OLLAMA_BASE_URL is set
if [ -n "$OLLAMA_BASE_URL" ]; then
    gbrain config set embedding_provider ollama 2>/dev/null || true
    gbrain config set ollama_base_url "$OLLAMA_BASE_URL" 2>/dev/null || true
fi

# Start GBRAIN in background, then register OAuth client and write token
echo "Starting GBRAIN HTTP MCP server on port ${GBRAIN_PORT}..."
gbrain serve --http --port "${GBRAIN_PORT}" --bind 0.0.0.0 --enable-dcr --token-ttl 31536000 &
GBRAIN_PID=$!

# Wait for server to be ready
echo "Waiting for GBRAIN to be ready..."
for i in $(seq 1 30); do
    if curl -sf "http://localhost:${GBRAIN_PORT}/health" > /dev/null 2>&1; then
        echo "GBRAIN is ready."
        break
    fi
    sleep 1
done

# Register OAuth client and get bearer token (for Hermes MCP access)
echo "Registering OAuth client for Hermes..."
CLIENT_RESP=$(curl -s -X POST "http://localhost:${GBRAIN_PORT}/register" \
    -H "Content-Type: application/json" \
    -d '{"client_name":"hermes","grant_types":["client_credentials"],"redirect_uris":["http://localhost"],"scope":"read write","token_endpoint_auth_method":"client_secret_post"}' 2>&1)

CLIENT_ID=$(echo "$CLIENT_RESP" | grep -o '"client_id":"[^"]*"' | cut -d'"' -f4)
CLIENT_SECRET=$(echo "$CLIENT_RESP" | grep -o '"client_secret":"[^"]*"' | cut -d'"' -f4)

if [ -n "$CLIENT_ID" ] && [ -n "$CLIENT_SECRET" ]; then
    TOKEN_RESP=$(curl -s -X POST "http://localhost:${GBRAIN_PORT}/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=read%20write" 2>&1)

    TOKEN=$(echo "$TOKEN_RESP" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$TOKEN" ]; then
        echo "$TOKEN" > "$TOKEN_FILE"
        # Also save client credentials for token refresh
        echo "${CLIENT_ID}" > "${GBRAIN_HOME}/mcp-client-id.txt"
        echo "${CLIENT_SECRET}" > "${GBRAIN_HOME}/mcp-client-secret.txt"
        echo "MCP bearer token written to ${TOKEN_FILE}"
    else
        echo "WARNING: Failed to get bearer token. Response: $TOKEN_RESP"
    fi
else
    echo "WARNING: Failed to register OAuth client. Response: $CLIENT_RESP"
fi

# Wait for GBRAIN process
wait $GBRAIN_PID
