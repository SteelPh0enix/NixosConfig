# Configuration Reference

All configuration is via environment variables with the `LOCAL_EXTRACT_` prefix. Copy `.env.example` to `.env` and edit as needed.

## Server

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL_EXTRACT_HOST` | `0.0.0.0` | Bind address. |
| `LOCAL_EXTRACT_PORT` | `8090` | Listen port. |

## Logging

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL_EXTRACT_LOG_LEVEL` | `INFO` | One of: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`. |
| `LOCAL_EXTRACT_LOG_FULL_URLS` | `false` | Log full URLs instead of domain-only. **Only enable for debugging** — URLs may contain tokens. |

## Security

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL_EXTRACT_ALLOW_PRIVATE_NETWORKS` | `false` | Allow fetching from private/RFC 1918/loopback addresses. **Only enable on isolated, trusted networks.** |
| `LOCAL_EXTRACT_TRUST_PROXY_HEADERS` | `false` | Use `X-Forwarded-For` for rate limiting client IP. Only enable if you control the proxy. |

## Fetch limits

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL_EXTRACT_MAX_BODY_MB` | `15` | Maximum response body size in megabytes. |
| `LOCAL_EXTRACT_MAX_PDF_MB` | `20` | Maximum PDF file size in megabytes. |
| `LOCAL_EXTRACT_TIMEOUT_SECONDS` | `20` | Default per-request timeout. |
| `LOCAL_EXTRACT_MAX_TIMEOUT_SECONDS` | `60` | Hard cap on timeout, even if caller requests more. |
| `LOCAL_EXTRACT_MAX_REDIRECTS` | `5` | Maximum redirects to follow per request. |
| `LOCAL_EXTRACT_MAX_CONTENT_CHARS` | `200000` | Maximum extracted text characters to return. |

## Rate limiting and concurrency

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL_EXTRACT_RATE_LIMIT_PER_MINUTE` | `60` | Requests per minute per client IP. |
| `LOCAL_EXTRACT_CONCURRENCY` | `8` | Max concurrent extractions (informational; enforced by uvicorn worker count). |

## Cache

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL_EXTRACT_CACHE_ENABLED` | `false` | Enable in-memory TTL cache. |
| `LOCAL_EXTRACT_CACHE_TTL_SECONDS` | `3600` | Cache entry lifetime in seconds. |
| `LOCAL_EXTRACT_CACHE_BACKEND` | `memory` | Cache backend. Only `memory` is supported in the base install. |

**Privacy note:** When caching is enabled, extracted content is stored in memory for the TTL duration. Do not enable caching if extracted content is sensitive.

## Browser (optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL_EXTRACT_BROWSER_ENABLED` | `false` | Enable Crawl4AI browser rendering. Requires the browser Docker profile and `crawl4ai` installed. |

## Robots.txt

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL_EXTRACT_RESPECT_ROBOTS_TXT` | `false` | Best-effort robots.txt checking before fetching. See [limitations.md](limitations.md). |
