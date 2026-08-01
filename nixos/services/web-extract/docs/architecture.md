# Architecture

## Request flow

```
Caller
  │
  ▼
FastAPI app (main.py)
  │
  ├── Rate limiter middleware (rate_limit.py)
  │     └── Sliding-window per client IP
  │
  ├── Request ID + timing middleware
  │
  ▼
Router (native.py or firecrawl_compat.py)
  │
  ├── Input validation (Pydantic v2 models)
  │
  ▼
Extraction pipeline (pipeline.py)
  │
  ├── 1. Cache lookup (cache.py)
  │         └── TTL cache keyed on (url + options hash)
  │
  ├── 2. Security gate (security.py)
  │         ├── URL scheme validation (http/https only)
  │         ├── Credential rejection
  │         ├── Hostname resolution
  │         └── IP range blocking (SSRF protection)
  │
  ├── 3. Fetch (fetcher.py)
  │         ├── httpx.AsyncClient
  │         ├── Manual redirect following with per-redirect SSRF check
  │         ├── Streaming body with size enforcement
  │         └── Returns FetchResult (content, content_type, status, elapsed_ms)
  │
  ├── 4. Content type routing
  │         ├── PDF → PDFExtractor (pypdf)
  │         ├── HTML → HTML extractor pipeline (see below)
  │         └── text/plain → pass-through
  │
  ├── 5. Normalisation (normalizers.py)
  │         ├── Control character removal
  │         ├── Unicode NFC normalisation
  │         ├── Whitespace collapse
  │         ├── Length enforcement and truncation warning
  │         └── Code block preservation (markdown)
  │
  ├── 6. Cache set (on success)
  │
  └── 7. Response assembly (ExtractResponse / FirecrawlScrapeResponse)
```

## HTML extractor pipeline

The HTML pipeline is layered. Each extractor is tried in order; if the result is too short to be useful (< 50 chars), the next extractor is tried.

```
HTML bytes
  │
  ▼
TrafilaturaExtractor (primary)
  │ if poor result
  ▼
ReadabilityExtractor (BeautifulSoup + markdownify)
  │ if poor result
  ▼
FallbackExtractor (last resort: strip noise + markdownify body)
  │
  └── if render_js=auto/always and browser enabled:
      └── Crawl4AIExtractor (async, optional)
```

### Extractor quality check

`is_content_poor(text, min_chars=50)` — if extracted text is shorter than 50 characters, the extractor is considered to have failed and the pipeline advances to the next.

## Optional browser layer

When `LOCAL_EXTRACT_BROWSER_ENABLED=true` and `crawl4ai` is installed, `Crawl4AIExtractor` wraps a headless Chromium session via Playwright. This is async and runs after the static extractors. It is only triggered when `render_js=auto` or `render_js=always`.

The browser layer is not part of the base installation. Use the browser Docker profile (`examples/docker-compose.browser.yml`) to enable it.

## Firecrawl compatibility layer

`routers/firecrawl_compat.py` maps Firecrawl request fields to native `ExtractRequest` fields, delegates to the same `run_extraction` pipeline, and maps the response to the Firecrawl `{success, data}` shape. The compatibility layer is thin — it is a translation adapter, not a separate extraction path.

## Configuration

`config.py` uses Pydantic Settings (`pydantic-settings`) to read environment variables with the `LOCAL_EXTRACT_` prefix. The `Settings` singleton is loaded once at startup and injected via FastAPI dependency injection.

## Caching

`cache.py` wraps `cachetools.TTLCache`. The cache key is a SHA-256 hash of the normalised URL and relevant request options. Cache is disabled by default. When enabled, only successful responses are cached.

## Logging

`logging_config.py` configures structured console logging. URLs are masked to domain-only by default (`LOCAL_EXTRACT_LOG_FULL_URLS=false`). Stack traces are logged server-side but never exposed in API responses.

## Future roadmap

The following are potential future additions, not planned for 0.1:

- Robots.txt enforcement (currently stubbed, default off).
- Optional API key authentication for shared deployments.
- `diskcache` backend for persistent caching across restarts.
- Link extraction (currently returns empty list; infrastructure is in place).
- Image URL extraction.
- Structured data extraction (JSON-LD, microdata).
- Batch URL processing endpoint.
- Contribution of a `local_extract` backend to the Hermes Agent project.
