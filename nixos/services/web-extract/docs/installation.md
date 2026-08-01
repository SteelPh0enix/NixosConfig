# Installation

## Requirements

- Docker + Docker Compose (recommended), or
- Python 3.12+ with pip/uv

## Option 1: Docker Compose (recommended)

```bash
git clone https://github.com/gopalasubramanium/web_extract.git
cd web_extract
cp .env.example .env
docker compose up -d
curl http://localhost:8090/healthz
```

The service starts on port 8090. To change the port, edit `LOCAL_EXTRACT_PORT` in `.env`.

## Option 2: install.sh

```bash
git clone https://github.com/gopalasubramanium/web_extract.git
cd web_extract
bash install.sh
```

The script checks for Docker, creates `.env` from `.env.example` if missing, builds and starts the service, and verifies the health endpoint.

## Option 3: Native Python

Requires Python 3.12+.

```bash
git clone https://github.com/gopalasubramanium/web_extract.git
cd web_extract
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt -e .
cp .env.example .env
uvicorn hermes_local_web_extract.main:app --host 0.0.0.0 --port 8090
```

Or with uv:

```bash
uv venv --python 3.12
uv pip install -r requirements.txt -e .
cp .env.example .env
uv run uvicorn hermes_local_web_extract.main:app --host 0.0.0.0 --port 8090
```

## Optional: browser profile

For JavaScript-rendered pages, use the browser Docker Compose profile (requires more memory):

```bash
# Set LOCAL_EXTRACT_BROWSER_ENABLED=true in .env first
docker compose -f docker-compose.yml -f examples/docker-compose.browser.yml up -d
```

This profile enables Crawl4AI + Playwright and installs Chromium. The image is significantly larger (~1 GB) and requires at least 2 GB of memory.

## Verify the installation

```bash
# Health check
curl http://localhost:8090/healthz

# Native extract
curl -s http://localhost:8090/extract \
  -H 'content-type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown","text","metadata"]}' | jq

# Firecrawl-compatible extract
curl -s http://localhost:8090/v1/scrape \
  -H 'content-type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}' | jq
```

## Updating

```bash
git pull
docker compose build
docker compose up -d
```
