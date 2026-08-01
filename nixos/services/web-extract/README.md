# hermes-local-web-extract

**Free, self-hosted, local web extraction backend for Hermes Agent. No paid API key required.**

Extract readable content from web pages and PDFs using a simple HTTP API. Provides a native `/extract` endpoint and a [Firecrawl-compatible](#firecrawl-compatible-endpoint) `/v1/scrape` subset, so it can serve as a drop-in local backend for agents and tools that already speak Firecrawl.

---

## What problem this solves

Hermes Agent and similar tools support web extraction through paid providers (Firecrawl, Tavily, Exa, Parallel). If you want to run extraction locally — without an API key, without sending URLs to a third party, and without a usage bill — this service fills that gap.

Run it locally, point your agent at `http://localhost:8090`, and extract.

## What this does NOT do

- It is **not** a hosted cloud service.
- It is **not** a complete Firecrawl replacement — only a practical subset is implemented. See [Firecrawl compatibility](#firecrawl-compatibility).
- It does **not** crawl multiple pages. Single URL extraction only.
- It does **not** bypass CAPTCHAs, Cloudflare, or anti-bot systems.
- It does **not** do stealth scraping, proxy rotation, or session hijacking.
- It does **not** implement login, authentication, or cookie management.

See [docs/limitations.md](docs/limitations.md) for the full list.

---

## Quick start

```bash
git clone https://github.com/gopalasubramanium/web_extract.git
cd web_extract
cp .env.example .env
docker compose up -d
curl http://localhost:8090/healthz
```

---

## Running the service

### Docker Compose (recommended)

```bash
cp .env.example .env          # Edit as needed
docker compose up -d
docker compose logs -f hermes-local-web-extract
```

### Docker run

```bash
docker build -t hermes-local-web-extract .
docker run -d \
  --name hermes-local-web-extract \
  -p 8090:8090 \
  --env-file .env \
  --read-only \
  --tmpfs /tmp \
  --security-opt no-new-privileges:true \
  hermes-local-web-extract
```

### Native Python (no Docker)

Requires Python 3.12+.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt -e .
cp .env.example .env
uvicorn hermes_local_web_extract.main:app --host 0.0.0.0 --port 8090
```

---

## Native extraction endpoint

```bash
curl -s http://localhost:8090/extract \
  -H "content-type: application/json" \
  -d '{
    "url": "https://example.com",
    "formats": ["markdown", "text", "metadata"]
  }' | jq
```

**Request fields:**

| Field | Default | Description |
|-------|---------|-------------|
| `url` | required | `http://` or `https://` URL |
| `formats` | `["markdown","text","metadata"]` | `markdown`, `text`, `html`, `metadata` |
| `render_js` | `"never"` | `never` / `auto` / `always` (browser profile required for auto/always) |
| `timeout_seconds` | `20` | Per-request timeout (max 60) |
| `include_metadata` | `true` | Include metadata block |
| `include_links` | `false` | Include extracted links |
| `include_images` | `false` | Include extracted image URLs |
| `max_content_chars` | `200000` | Truncate content at this many characters |

**Example response:**

```json
{
  "success": true,
  "url": "https://example.com",
  "final_url": "https://example.com",
  "title": "Example Domain",
  "markdown": "# Example Domain\n\nThis domain is for use in illustrative examples...",
  "text": "Example Domain\n\nThis domain is for use in illustrative examples...",
  "metadata": {
    "title": "Example Domain",
    "content_type": "text/html",
    "status_code": 200,
    "extractor": "trafilatura",
    "elapsed_ms": 312
  },
  "warnings": []
}
```

---

## Firecrawl-compatible endpoint

```bash
curl -s http://localhost:8090/v1/scrape \
  -H "content-type: application/json" \
  -d '{
    "url": "https://example.com",
    "formats": ["markdown"]
  }' | jq
```

Accepts both camelCase (`onlyMainContent`, `waitFor`) and snake_case (`only_main_content`, `wait_for`) variants.

**Example response:**

```json
{
  "success": true,
  "data": {
    "markdown": "# Example Domain\n\n...",
    "html": null,
    "metadata": {
      "title": "Example Domain",
      "sourceURL": "https://example.com",
      "url": "https://example.com",
      "statusCode": 200,
      "contentType": "text/html",
      "extractor": "trafilatura"
    }
  }
}
```

### Firecrawl compatibility

This service implements a **minimal practical subset** of the Firecrawl API. It is **not** a full Firecrawl replacement.

**Supported:**
- `POST /v1/scrape` with `markdown`, `html`, `text` formats
- `GET /v1/health`
- `url`, `formats`, `onlyMainContent`/`only_main_content`, `timeout`, `waitFor`/`wait_for` fields

**Not supported:**
- `/v1/crawl`, `/v1/map`, batch endpoints
- `actions`, `extract` (structured data), `screenshot`
- `rawHtml`, `links` formats
- `includeTags`, `excludeTags`
- API key authentication

See [docs/limitations.md](docs/limitations.md) for the full list.

---

## Hermes integration

See [docs/hermes-integration.md](docs/hermes-integration.md) and [examples/hermes-config-example.yaml](examples/hermes-config-example.yaml).

Short version: if your Hermes version supports a custom Firecrawl base URL, set it to `http://localhost:8090`. If not, use the adapter approach described in the integration docs.

---

## Health endpoints

```bash
curl http://localhost:8090/healthz    # Liveness
curl http://localhost:8090/readyz     # Readiness
curl http://localhost:8090/v1/health  # Firecrawl-compatible
```

---

## Configuration

Copy `.env.example` to `.env` and edit as needed. Key variables:

```bash
LOCAL_EXTRACT_PORT=8090
LOCAL_EXTRACT_LOG_LEVEL=INFO
LOCAL_EXTRACT_ALLOW_PRIVATE_NETWORKS=false  # Keep false unless you know the risk
LOCAL_EXTRACT_TIMEOUT_SECONDS=20
LOCAL_EXTRACT_MAX_BODY_MB=15
LOCAL_EXTRACT_RATE_LIMIT_PER_MINUTE=60
LOCAL_EXTRACT_CACHE_ENABLED=false
LOCAL_EXTRACT_BROWSER_ENABLED=false
```

See [docs/configuration.md](docs/configuration.md) for the full reference.

---

## Security model

- **SSRF protection:** private IPs, loopback, cloud metadata (169.254.169.254), and link-local addresses are blocked by default.
- **Redirect validation:** every redirect target is re-validated before following.
- **No telemetry:** nothing leaves your machine except the outbound fetch.
- **No secrets required:** no API keys, tokens, or credentials.
- **Non-root Docker container:** runs as UID 1001, read-only filesystem, dropped capabilities.
- **Rate limiting:** in-memory per-IP sliding window.

See [docs/security-model.md](docs/security-model.md) for full details.

---

## Browser mode (optional)

JavaScript-heavy pages may need browser rendering. Enable it with:

```bash
# In .env:
LOCAL_EXTRACT_BROWSER_ENABLED=true

# Start with browser profile:
docker compose -f docker-compose.yml -f examples/docker-compose.browser.yml up -d
```

This installs Crawl4AI + Playwright + Chromium. The image is ~1 GB and requires more memory. Not part of the base install.

---

## Supported content types

| Type | Extractor |
|------|-----------|
| `text/html` | trafilatura → readability → fallback |
| `application/pdf` | pypdf |
| `text/plain` | pass-through |

Scanned PDFs (no embedded text) are not supported. Video, audio, binary formats return `UNSUPPORTED_CONTENT_TYPE`.

---

## Roadmap

- Robots.txt best-effort checking (stubbed, not yet enforced)
- Optional API key for shared deployments
- Link and image extraction
- Hermes native backend contribution
- Structured data extraction (JSON-LD)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Run tests with `pytest tests/ -v`. All 71 tests must pass, no internet required.

---

## License

Apache-2.0. See [LICENSE](LICENSE).

Apache-2.0 was chosen because it allows use in proprietary and commercial projects, provides patent protection, and is compatible with the broader open-source ecosystem around Hermes Agent.

---

## Disclaimer

**Users are solely responsible for:**

- Complying with the terms of service of every website they extract content from.
- Respecting copyright. Extracted content may be protected by copyright law.
- Complying with applicable laws (CFAA, GDPR, DMCA, and local equivalents).
- Respecting `robots.txt` and website policies.

This project does not encourage or enable scraping in violation of website terms. The maintainers make no representations about the legality of extracting any particular website's content. When in doubt, do not extract.
