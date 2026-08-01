# API Reference

Base URL (default): `http://localhost:8090`

Interactive docs available at `/docs` (Swagger UI) and `/redoc`.

---

## POST /extract

Native extraction endpoint.

### Request

```json
{
  "url": "https://example.com/article",
  "formats": ["markdown", "text", "metadata"],
  "render_js": "never",
  "timeout_seconds": 20,
  "include_metadata": true,
  "include_links": false,
  "include_images": false,
  "max_content_chars": 200000
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `url` | string | **required** | URL to extract. `http://` and `https://` only. |
| `formats` | array | `["markdown","text","metadata"]` | Output formats: `markdown`, `text`, `html`, `metadata`. |
| `render_js` | enum | `"never"` | `never` \| `auto` \| `always`. `auto`/`always` require browser profile. |
| `timeout_seconds` | int | `20` | Per-request timeout. Min 1, max configured cap (default 60). |
| `include_metadata` | bool | `true` | Include metadata object in response. |
| `include_links` | bool | `false` | Include extracted links in response. |
| `include_images` | bool | `false` | Include extracted image URLs in response. |
| `max_content_chars` | int | `200000` | Truncate extracted content to this many characters. |

### Response (200)

```json
{
  "success": true,
  "url": "https://example.com/article",
  "final_url": "https://example.com/article",
  "title": "Article Title",
  "description": "Article description.",
  "markdown": "# Article Title\n\nContent...",
  "text": "Article Title\n\nContent...",
  "html": null,
  "metadata": {
    "title": "Article Title",
    "author": "Author Name",
    "date": "2024-01-01",
    "site_name": "Example",
    "language": "en",
    "content_type": "text/html",
    "status_code": 200,
    "extractor": "trafilatura",
    "elapsed_ms": 423
  },
  "links": [],
  "images": [],
  "warnings": []
}
```

Fields not requested in `formats` are `null`.

### Error response (400/429/500)

```json
{
  "success": false,
  "error": {
    "code": "BLOCKED_PRIVATE_ADDRESS",
    "message": "URL resolves to a blocked/private address (127.0.0.1)."
  }
}
```

### Error codes

| Code | HTTP | Meaning |
|------|------|---------|
| `INVALID_URL` | 400 | Malformed, disallowed scheme, or credential-bearing URL. |
| `BLOCKED_PRIVATE_ADDRESS` | 400 | URL resolves to a private/reserved IP. |
| `FETCH_TIMEOUT` | 400 | Request timed out. |
| `FETCH_ERROR` | 400 | Network error during fetch. |
| `BODY_TOO_LARGE` | 400 | Response body exceeds size limit. |
| `UNSUPPORTED_CONTENT_TYPE` | 400 | Content type cannot be extracted (e.g., video/mp4). |
| `EXTRACTION_FAILED` | 400 | Extraction returned no usable content. |
| `RATE_LIMITED` | 429 | Client has exceeded the rate limit. |
| `INTERNAL_ERROR` | 500 | Unexpected server error. |

---

## POST /v1/scrape

Firecrawl-compatible extraction endpoint (minimal subset).

### Request

```json
{
  "url": "https://example.com",
  "formats": ["markdown", "html"],
  "onlyMainContent": true,
  "timeout": 20000
}
```

Also accepts snake_case variants:

```json
{
  "url": "https://example.com",
  "formats": ["markdown"],
  "only_main_content": true,
  "timeout": 20000,
  "wait_for": 0
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `url` | string | **required** | URL to scrape. |
| `formats` | array | `["markdown"]` | `markdown`, `html`, `text`. Other formats are silently ignored. |
| `onlyMainContent` / `only_main_content` | bool | `true` | Accepted but all extractions already target main content. |
| `timeout` | int | `20000` | Timeout in **milliseconds** (converted to seconds internally). |
| `waitFor` / `wait_for` | int | `0` | Accepted for compatibility; JS wait is only active in browser mode. |

### Response (200)

```json
{
  "success": true,
  "data": {
    "markdown": "# Page Title\n\nContent...",
    "html": null,
    "metadata": {
      "title": "Page Title",
      "description": "Page description.",
      "sourceURL": "https://example.com",
      "url": "https://example.com",
      "statusCode": 200,
      "contentType": "text/html",
      "extractor": "trafilatura"
    }
  }
}
```

### Unsupported Firecrawl fields

The following Firecrawl API fields are **not supported** and will be ignored or return an error:

- `actions` (browser interaction sequences)
- `extract` (structured data extraction with JSON schema)
- `screenshot`
- `mobile`, `location`, `skipTlsVerification`, `proxy`
- `includeTags`, `excludeTags`
- `changeTrackingOptions`
- `rawHtml` format

This is a **minimal compatibility layer**, not a full Firecrawl replacement. See [limitations.md](limitations.md).

---

## GET /healthz

Liveness probe. Returns 200 when the server process is running.

```json
{"success": true, "status": "ok", "version": "0.1.0"}
```

---

## GET /readyz

Readiness probe. Returns 200 when the server is ready to accept requests.

```json
{"success": true, "status": "ok", "version": "0.1.0"}
```

---

## GET /v1/health

Firecrawl-compatible health endpoint.

```json
{"success": true, "status": "ok", "version": "0.1.0"}
```

---

## Limits

| Limit | Default | Env variable |
|-------|---------|--------------|
| Rate limit | 60 req/min per IP | `LOCAL_EXTRACT_RATE_LIMIT_PER_MINUTE` |
| Max response body | 15 MB | `LOCAL_EXTRACT_MAX_BODY_MB` |
| Max PDF | 20 MB | `LOCAL_EXTRACT_MAX_PDF_MB` |
| Timeout | 20 s | `LOCAL_EXTRACT_TIMEOUT_SECONDS` |
| Hard timeout cap | 60 s | `LOCAL_EXTRACT_MAX_TIMEOUT_SECONDS` |
| Max redirects | 5 | `LOCAL_EXTRACT_MAX_REDIRECTS` |
| Max extracted chars | 200,000 | `LOCAL_EXTRACT_MAX_CONTENT_CHARS` |
