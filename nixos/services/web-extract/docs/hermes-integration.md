# Hermes Integration

This document explains how to use hermes-local-web-extract with Hermes Agent.

## Background

Hermes Agent currently supports web extraction through paid providers such as Firecrawl, Tavily, Exa, and Parallel. This service provides a free, self-hosted alternative that exposes:

1. A **native `/extract` endpoint** — the preferred way to call this service.
2. A **Firecrawl-compatible `/v1/scrape` endpoint** — a minimal subset for compatibility.

## Integration approach depends on your Hermes version

Hermes evolves, and the available integration points may differ between versions. This documentation covers three approaches in order of preference.

---

## Approach 1: Firecrawl base URL override (if your Hermes version supports it)

Some versions of Hermes allow overriding the base URL for a provider. If your Hermes configuration supports setting a custom Firecrawl base URL, point it to this service:

```yaml
# Conceptual example — actual config keys depend on your Hermes version
web_extract:
  provider: firecrawl
  firecrawl_base_url: http://localhost:8090
  # No API key required for hermes-local-web-extract
  firecrawl_api_key: "local"
```

Hermes will then call `POST http://localhost:8090/v1/scrape` instead of the Firecrawl cloud. This works because this service implements the Firecrawl `/v1/scrape` subset.

**Important:** Not all Hermes versions support a custom base URL. Check your Hermes documentation or source.

---

## Approach 2: Local adapter (if Hermes does not support base URL override)

If Hermes does not support overriding the Firecrawl base URL, you can write a small adapter that calls `/extract` directly and returns results in the format Hermes expects.

### Example Python adapter

```python
import httpx

EXTRACT_BASE = "http://localhost:8090"

async def local_extract(url: str, formats: list[str] = None) -> dict:
    """Call hermes-local-web-extract and return content."""
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{EXTRACT_BASE}/extract",
            json={
                "url": url,
                "formats": formats or ["markdown", "text", "metadata"],
            },
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

# Usage
result = await local_extract("https://example.com/article")
markdown = result["markdown"]
metadata = result["metadata"]
```

Register this adapter as a custom extraction backend in your Hermes configuration.

---

## Approach 3: Contribute a local_extract backend to Hermes

The cleanest long-term integration is to contribute a `local_extract` provider to Hermes that calls `POST /extract` on this service. This would make it a first-class provider in Hermes, configurable like Firecrawl or Tavily.

If you build this, please consider contributing it to both the Hermes project and this repository as a reference integration.

---

## If your Hermes version does not support custom extract endpoints

If your version of Hermes has no extensibility point for web extraction, you have two options:

1. **Use the Firecrawl-compatible endpoint with a reverse proxy.** If Hermes hard-codes `api.firecrawl.dev`, run a local reverse proxy (Nginx, Caddy, Traefik) that intercepts calls to that domain and forwards them to `localhost:8090`. This is a last resort and may break on TLS without certificate manipulation.

2. **Patch Hermes locally.** Fork or patch the Hermes source to support a configurable extraction base URL, then use this service.

3. **Wait or request the feature.** Open an issue or PR on the Hermes project requesting support for a self-hosted extraction backend.

---

## Example: hermes-config-example.yaml

See `examples/hermes-config-example.yaml` for a conceptual configuration example.

---

## Tested behaviour

The Firecrawl-compatible endpoint has been verified to return the expected response shape:

```bash
curl -s http://localhost:8090/v1/scrape \
  -H 'content-type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}' | jq

# Output:
# {
#   "success": true,
#   "data": {
#     "markdown": "# Example Domain\n\n...",
#     "html": null,
#     "metadata": {
#       "title": "Example Domain",
#       "sourceURL": "https://example.com",
#       "url": "https://example.com",
#       "statusCode": 200,
#       "contentType": "text/html",
#       "extractor": "trafilatura"
#     }
#   }
# }
```

## What this service does not provide

- API key validation (there is no API key — the service is locally trusted)
- `/v1/crawl` (multi-page crawling)
- `/v1/map` (site mapping)
- Batch endpoints
- Browser actions (click, type, scroll)
- Screenshots

For these features, use a Firecrawl subscription or an alternative cloud provider.
