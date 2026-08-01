# Troubleshooting

## Service won't start

**Check Docker logs:**
```bash
docker compose logs hermes-local-web-extract
```

**Check .env exists:**
```bash
ls -la .env
# If missing:
cp .env.example .env
```

**Port conflict:**
If port 8090 is in use, change `LOCAL_EXTRACT_PORT` in `.env` and restart.

---

## GET /healthz returns connection refused

The service is not running. Start it:
```bash
docker compose up -d
# or
uvicorn hermes_local_web_extract.main:app --host 0.0.0.0 --port 8090
```

---

## POST /extract returns BLOCKED_PRIVATE_ADDRESS

You are trying to extract a URL on a private/local network. This is blocked by default.

If you are on a trusted internal network and need this:
```bash
# In .env:
LOCAL_EXTRACT_ALLOW_PRIVATE_NETWORKS=true
```
Restart the service. Understand the SSRF risk before enabling this.

---

## Extraction returns empty markdown / poor quality

1. Check `warnings` in the response — the extractor will say which fallback was used.
2. The page may require JavaScript rendering. Try `"render_js": "auto"` with browser mode enabled.
3. The page may be behind Cloudflare or another WAF. This service does not bypass bot protection.
4. The page content may genuinely be too short (e.g., a login page or redirect).

---

## PDF extraction returns empty text

The PDF is likely scanned/image-based. OCR is not included. This is a known limitation.

---

## Rate limit 429 errors

You are exceeding `LOCAL_EXTRACT_RATE_LIMIT_PER_MINUTE` (default 60). Increase it in `.env`:
```bash
LOCAL_EXTRACT_RATE_LIMIT_PER_MINUTE=300
```

---

## Timeout errors

1. Increase `LOCAL_EXTRACT_TIMEOUT_SECONDS` (up to `LOCAL_EXTRACT_MAX_TIMEOUT_SECONDS`).
2. Check if the target website is slow or unreachable.
3. With browser mode enabled, some pages take longer to render. Increase timeout accordingly.

---

## Docker read-only filesystem errors

The container runs with `read_only: true` by default. Ensure `/tmp` is mounted as tmpfs (it is in the provided `docker-compose.yml`). If an extractor writes to disk unexpectedly, check the tmpfs size (`/tmp:size=64m`).

---

## Browser mode not working

1. Ensure `LOCAL_EXTRACT_BROWSER_ENABLED=true` in `.env`.
2. Use the browser Compose profile: `docker compose -f docker-compose.yml -f examples/docker-compose.browser.yml up -d`.
3. The browser image must be built with `crawl4ai` and Playwright installed.
4. Check logs for Playwright/Chromium errors.

---

## Firecrawl-compatible endpoint returns unexpected shape

This service implements a **subset** of the Firecrawl API. Fields your client expects that are not supported will be absent or null. Check [docs/limitations.md](limitations.md) for the list of unsupported fields.

---

## Tests fail with network errors

All tests use `respx` mocking and must not require internet. If you see real network errors in tests, check that `respx.mock` is properly applied (the `@respx.mock` decorator must wrap the test function).
