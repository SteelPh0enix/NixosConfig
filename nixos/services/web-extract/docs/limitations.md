# Limitations

This document states clearly what hermes-local-web-extract does and does not do. Read it before deploying.

## What this is

A **single-URL extraction service** for use by local agents and automation tools that need to fetch and extract the readable content of a web page or PDF, without a paid API dependency.

## What this is not

### Not a hosted SaaS

This service is designed to run on your own machine or private infrastructure. It is not a cloud service with guarantees of availability, scalability, or uptime.

### Not a complete Firecrawl replacement

The `/v1/scrape` endpoint implements a **practical subset** of the Firecrawl API sufficient for common scrape/extract use cases. The following Firecrawl features are **not implemented**:

- `/v1/crawl` — multi-page crawling
- `/v1/map` — site mapping
- `/v1/batch/scrape` — batch URL processing
- `actions` — browser interaction sequences (click, type, scroll)
- `extract` structured data extraction with schemas
- `screenshot` — page screenshots
- Webhooks
- Authentication tokens / API key validation (this service has none by default)
- Full `formats` support: `rawHtml`, `links`, `screenshot` formats are not returned
- `includeTags` / `excludeTags` CSS selectors

Use the native `/extract` endpoint for all features this service provides.

### Not guaranteed on CAPTCHA or bot-protected pages

Pages protected by Cloudflare, hCaptcha, reCAPTCHA, or other bot-detection systems may return challenge pages instead of content. This service does not attempt to bypass these protections.

### Not designed for mass crawling

This is a single-URL extraction tool. There is no crawling, sitemap discovery, link following, or batch processing. Attempting to use it as a mass crawler by calling it in tight loops is contrary to its design, may violate website terms, and is not supported.

### Not a search engine

This service extracts content from URLs you provide. It does not search for pages, discover URLs, or index content.

### JavaScript-heavy pages may require browser mode

Pages that render their content using JavaScript (single-page applications, React/Vue/Angular apps) may return little or no content with the default static extractor. Enable browser mode (`LOCAL_EXTRACT_BROWSER_ENABLED=true`) and use the browser Docker profile for these cases. Browser mode is optional, heavier, and not part of the base installation.

### Extraction quality varies

The extractors (trafilatura, BeautifulSoup, markdownify) produce best-effort output. Quality depends on how well-structured the target page is. Some pages will produce excellent markdown; others will produce noise. The `warnings` field in responses reports when extraction quality was low or a fallback was used.

### Scanned PDFs are not supported

PDF extraction relies on embedded text. Scanned or image-based PDFs will return empty or near-empty text. OCR is not included.

## Legal and compliance

**Users are solely responsible for:**

- Complying with the terms of service of every website they extract from.
- Respecting copyright. Extracted content may be protected by copyright law.
- Complying with applicable laws in their jurisdiction (CFAA, GDPR, copyright directives, etc.).
- Respecting robots.txt. By default this service does not enforce robots.txt. Set `LOCAL_EXTRACT_RESPECT_ROBOTS_TXT=false` (default) acknowledges this is a single-URL user-directed operation, not a crawler.

This project and its maintainers make no representations about the legality of extracting any particular website's content. When in doubt, do not extract.
