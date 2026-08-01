"""Core extraction pipeline: fetch → detect → extract → normalise → respond."""

import logging

from hermes_local_web_extract.cache import cache_get, cache_set
from hermes_local_web_extract.config import Settings
from hermes_local_web_extract.errors import (
    UnsupportedContentTypeError,
)
from hermes_local_web_extract.extractors.base import ExtractionResult
from hermes_local_web_extract.extractors.html_fallback import FallbackExtractor
from hermes_local_web_extract.extractors.html_readability import ReadabilityExtractor
from hermes_local_web_extract.extractors.html_trafilatura import TrafilaturaExtractor
from hermes_local_web_extract.extractors.pdf_extractor import PDFExtractor
from hermes_local_web_extract.fetcher import FetchResult, fetch
from hermes_local_web_extract.logging_config import safe_url
from hermes_local_web_extract.models import (
    ExtractMetadata,
    ExtractRequest,
    ExtractResponse,
    RenderJs,
)
from hermes_local_web_extract.normalizers import clean_markdown, clean_text
from hermes_local_web_extract.utils.text import is_content_poor

logger = logging.getLogger(__name__)

_HTML_TYPES = {
    "text/html",
    "application/xhtml+xml",
    "application/xml",
    "text/xml",
}
_PDF_TYPE = "application/pdf"
_TEXT_TYPE = "text/plain"


def _is_html(ct: str) -> bool:
    base = ct.split(";")[0].strip().lower()
    return base in _HTML_TYPES or base.startswith("text/html")


def _is_pdf(ct: str, url: str) -> bool:
    base = ct.split(";")[0].strip().lower()
    if base == _PDF_TYPE:
        return True
    return url.lower().endswith(".pdf")


def _is_text(ct: str) -> bool:
    base = ct.split(";")[0].strip().lower()
    return base == _TEXT_TYPE


async def run_extraction(request: ExtractRequest, settings: Settings) -> ExtractResponse:
    """
    Full extraction pipeline for a single URL.

    1. Check cache.
    2. Validate URL and fetch with SSRF protection.
    3. Detect content type.
    4. Extract via appropriate pipeline.
    5. Normalise output.
    6. Cache on success.
    7. Return structured response.
    """
    cache_key_opts = {
        "formats": sorted(f.value for f in request.formats),
        "render_js": request.render_js.value,
        "max_content_chars": request.max_content_chars,
    }
    cached = cache_get(request.url, cache_key_opts)
    if cached is not None:
        return cached

    log_url = safe_url(request.url, settings.log_full_urls)
    logger.info("Extracting %s", log_url)

    # Fetch
    fetch_result: FetchResult = await fetch(
        request.url,
        settings,
        timeout_override=min(request.timeout_seconds, settings.max_timeout_seconds),
    )

    ct = fetch_result.content_type
    warnings: list[str] = []

    # Route to extractor
    extraction: ExtractionResult

    if _is_pdf(ct, fetch_result.final_url):
        if len(fetch_result.content) > settings.max_pdf_bytes:
            from hermes_local_web_extract.errors import BodyTooLargeError

            raise BodyTooLargeError(f"PDF exceeds {settings.max_pdf_mb} MB limit.")
        extraction = PDFExtractor().extract(fetch_result.content, fetch_result.final_url, ct)

    elif _is_html(ct):
        extraction = await _extract_html_async(fetch_result, request, settings, warnings)

    elif _is_text(ct):
        text = fetch_result.content.decode("utf-8", errors="replace")
        extraction = ExtractionResult(
            text=text,
            markdown=text,
            extractor_name="plain-text",
        )

    else:
        raise UnsupportedContentTypeError(ct)

    warnings.extend(extraction.warnings)

    # Normalise
    formats = {f.value for f in request.formats}
    max_chars = min(request.max_content_chars, settings.max_content_chars)

    final_text: str | None = None
    final_markdown: str | None = None
    final_html: str | None = None

    if "text" in formats and extraction.text:
        t, w = clean_text(extraction.text, max_chars)
        final_text = t
        warnings.extend(w)

    if "markdown" in formats:
        md_src = extraction.markdown or extraction.text or ""
        md, w = clean_markdown(md_src, max_chars)
        final_markdown = md
        warnings.extend(w)

    if "html" in formats:
        final_html = fetch_result.content.decode("utf-8", errors="replace")[:max_chars]

    metadata = ExtractMetadata(
        title=extraction.title,
        author=extraction.author,
        date=extraction.date,
        site_name=extraction.site_name,
        language=extraction.language,
        content_type=ct,
        status_code=fetch_result.status_code,
        extractor=extraction.extractor_name,
        elapsed_ms=fetch_result.elapsed_ms,
    )

    response = ExtractResponse(
        success=True,
        url=request.url,
        final_url=fetch_result.final_url,
        title=extraction.title,
        description=extraction.description,
        markdown=final_markdown,
        text=final_text,
        html=final_html,
        metadata=metadata if "metadata" in formats or request.include_metadata else None,
        links=[] if not request.include_links else extraction.links,
        images=[] if not request.include_images else extraction.images,
        warnings=warnings,
    )

    cache_set(request.url, cache_key_opts, response)
    logger.info(
        "Extracted %s status=%d extractor=%s elapsed_ms=%d",
        log_url,
        fetch_result.status_code,
        extraction.extractor_name,
        fetch_result.elapsed_ms,
    )
    return response


async def _extract_html_async(
    fetch_result: FetchResult,
    request: ExtractRequest,
    settings: Settings,
    warnings: list[str],
) -> ExtractionResult:
    """
    Async HTML extraction pipeline: trafilatura → readability → fallback → browser.

    Must be async so that the optional Crawl4AI browser path can be properly awaited
    rather than fire-and-forget via asyncio.create_task.
    """
    content = fetch_result.content
    url = fetch_result.final_url
    ct = fetch_result.content_type

    # Try trafilatura first
    trafilatura_result = TrafilaturaExtractor().extract(content, url, ct)
    if not is_content_poor(trafilatura_result.text):
        return trafilatura_result

    warnings.append("trafilatura returned poor result; trying readability extractor.")

    # Fall back to readability
    readability_result = ReadabilityExtractor().extract(content, url, ct)
    if not is_content_poor(readability_result.text):
        return readability_result

    warnings.append("Readability extractor returned poor result; trying last-resort fallback.")

    # Browser fallback: properly awaited now that this function is async
    if request.render_js in (RenderJs.auto, RenderJs.always) and settings.browser_enabled:
        from hermes_local_web_extract.extractors.crawl4ai_extractor import Crawl4AIExtractor

        browser_result = await Crawl4AIExtractor().extract_async(
            url, timeout_seconds=min(request.timeout_seconds, settings.max_timeout_seconds)
        )
        if not is_content_poor(browser_result.text):
            return browser_result
        warnings.extend(browser_result.warnings)

    if request.render_js in (RenderJs.auto, RenderJs.always) and not settings.browser_enabled:
        warnings.append(
            "render_js requested but LOCAL_EXTRACT_BROWSER_ENABLED=false. "
            "Set LOCAL_EXTRACT_BROWSER_ENABLED=true and use the browser Docker profile."
        )

    return FallbackExtractor().extract(content, url, ct)
