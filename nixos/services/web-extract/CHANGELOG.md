# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.2] - 2026-06-11

### Fixed
- Extraction returned garbled binary content: the fetcher advertised `Accept-Encoding: gzip, br`
  (Brotli) but `brotli` was not installed, causing servers to send Brotli-compressed responses
  that httpx could not decode. Removed the manual `Accept-Encoding` override so httpx only
  advertises encodings it can decompress, and added `brotli>=1.1.0` as a dependency.
- Health endpoints reported version `0.1.0`: `__init__.py` and `pyproject.toml` were never
  updated past the initial release.

## [0.2.1] - 2026-06-11

### Fixed
- Container failed to start with `ModuleNotFoundError: No module named 'hermes_local_web_extract'`:
  the Dockerfile copied `src/` into the image but never installed the package, so uvicorn
  could not import it. The builder stage now runs `pip install --no-deps .` after installing
  dependencies.

## [0.2.0] - 2026-06-11

### Security
- Fixed relative and protocol-relative redirect SSRF bypass: `Location: /path` headers are
  now resolved against the current URL via `urljoin` before SSRF validation.
- Fixed zero DNS result bypass: an empty `getaddrinfo` response no longer silently skips
  SSRF checks; raises `InvalidURLError` instead.
- Removed URL from `FetchTimeoutError` messages to prevent token leakage via intermediate
  redirect URLs appearing in error responses.
- Converted Dockerfile to a multi-stage build: gcc and build headers are present only in
  the builder stage and are not shipped in the runtime image.

### Fixed
- Browser extraction path (`pipeline.py`): `asyncio.create_task()` in a sync helper was
  fire-and-forget and never awaited. Made `_extract_html` a proper `async def` and awaited
  the Crawl4AI call.
- `html_trafilatura.py`: `result.sitename` set a dynamic attribute that was never read by
  the pipeline. Fixed to `result.site_name`.
- `firecrawl_compat.py`: Python `and`/`or` operator precedence silently discarded
  `result.warnings`. Replaced with explicit list building.
- `pyproject.toml`: wrong setuptools build backend (`setuptools.backends.legacy:build` →
  `setuptools.build_meta`).
- Stale repo URLs in `pyproject.toml` and user-agent string: updated from
  `hermes-local-web-extract` to `web_extract`.
- `README.md`, `docs/installation.md`: `cd hermes-local-web-extract` failed because
  `git clone` creates a `web_extract` directory.

### Tests
- Added `tests/test_redirect_security.py` (9 tests): `resolve_redirect()` unit tests;
  API-level SSRF-via-redirect blocked for private IP, loopback, and cloud metadata
  endpoint; relative redirect to public URL allowed; too-many-redirects → `FETCH_ERROR`.
- Added `tests/test_edge_cases.py` (6 tests): zero DNS results, timeout message does not
  leak URL, `text/plain` extraction, 404/503 status codes surfaced in metadata, unsupported
  Firecrawl formats silently ignored.
- Total: 71 tests (up from 56), all offline.

## [0.1.0] - 2024-01-01

### Added
- Initial release.
- `POST /extract` native extraction endpoint.
- `POST /v1/scrape` Firecrawl-compatible extraction endpoint (minimal subset).
- `GET /healthz`, `GET /readyz`, `GET /v1/health` health endpoints.
- SSRF protection: blocks private, loopback, link-local, and cloud metadata addresses.
- Layered HTML extraction pipeline: trafilatura → readability → fallback.
- PDF extraction using pypdf.
- Plain-text content type support.
- Optional browser-rendered extraction via Crawl4AI (requires browser profile).
- In-memory sliding-window rate limiter.
- Optional in-memory TTL cache.
- Docker and docker-compose support.
- GitHub Actions for CI and Docker publish to GHCR.
- Structured logging with domain-only URL masking by default.
- Full pytest test suite (56 tests, no external network).
