#!/usr/bin/env bash
# install.sh — Bootstrap hermes-local-web-extract via Docker Compose.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#
# This script:
#   1. Checks for Docker and docker compose.
#   2. Creates .env from .env.example if .env does not exist.
#   3. Builds and starts the service with docker compose.
#   4. Verifies the health endpoint.
#   5. Prints usage examples.

set -euo pipefail

REPO_URL="https://github.com/gopalasubramanium/hermes-local-web-extract.git"
SERVICE_HOST="${LOCAL_EXTRACT_HOST:-localhost}"
SERVICE_PORT="${LOCAL_EXTRACT_PORT:-8090}"
BASE_URL="http://${SERVICE_HOST}:${SERVICE_PORT}"
MAX_HEALTH_RETRIES=12
HEALTH_RETRY_SLEEP=5

# ──────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*" >&2; }
error()   { echo "[ERROR] $*" >&2; exit 1; }

check_command() {
    command -v "$1" >/dev/null 2>&1 || error "$1 is required but not installed."
}

# ──────────────────────────────────────────────────────────
# Preflight checks
# ──────────────────────────────────────────────────────────

info "Checking prerequisites..."
check_command docker

# Prefer 'docker compose' (v2) over 'docker-compose' (v1)
if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    error "Neither 'docker compose' nor 'docker-compose' found. Install Docker Compose."
fi

success "Docker and Compose found ($COMPOSE)."

# ──────────────────────────────────────────────────────────
# Environment file
# ──────────────────────────────────────────────────────────

if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        info "Creating .env from .env.example..."
        cp .env.example .env
        success ".env created. Review it before re-running if you need custom settings."
    else
        warn ".env.example not found. Proceeding without .env."
    fi
else
    info ".env already exists — not overwriting."
fi

# ──────────────────────────────────────────────────────────
# Build and start
# ──────────────────────────────────────────────────────────

info "Building Docker image..."
$COMPOSE build

info "Starting service..."
$COMPOSE up -d

# ──────────────────────────────────────────────────────────
# Health check
# ──────────────────────────────────────────────────────────

info "Waiting for service to become healthy..."
retry=0
while [ $retry -lt $MAX_HEALTH_RETRIES ]; do
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/healthz" 2>/dev/null || echo "000")
    if [ "$http_status" = "200" ]; then
        success "Service is healthy at ${BASE_URL}"
        break
    fi
    retry=$((retry + 1))
    info "Health check attempt ${retry}/${MAX_HEALTH_RETRIES} (status=${http_status}). Retrying in ${HEALTH_RETRY_SLEEP}s..."
    sleep $HEALTH_RETRY_SLEEP
done

if [ $retry -eq $MAX_HEALTH_RETRIES ]; then
    warn "Service did not become healthy within expected time."
    warn "Check logs with: $COMPOSE logs hermes-local-web-extract"
fi

# ──────────────────────────────────────────────────────────
# Usage examples
# ──────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  hermes-local-web-extract is running at ${BASE_URL}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Health:   curl ${BASE_URL}/healthz"
echo ""
echo "  Native extract:"
echo "    curl -s ${BASE_URL}/extract \\"
echo "      -H 'content-type: application/json' \\"
echo "      -d '{\"url\":\"https://example.com\",\"formats\":[\"markdown\",\"text\",\"metadata\"]}' | jq"
echo ""
echo "  Firecrawl-compatible:"
echo "    curl -s ${BASE_URL}/v1/scrape \\"
echo "      -H 'content-type: application/json' \\"
echo "      -d '{\"url\":\"https://example.com\",\"formats\":[\"markdown\"]}' | jq"
echo ""
echo "  Stop:     $COMPOSE down"
echo "  Logs:     $COMPOSE logs -f hermes-local-web-extract"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
