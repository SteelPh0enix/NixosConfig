"""Optional browser-based extractor via Crawl4AI.

Crawl4AI is NOT a required dependency. This module is only active when:
  1. crawl4ai is installed (pip install 'hermes-local-web-extract[browser]')
  2. LOCAL_EXTRACT_BROWSER_ENABLED=true

If either condition is not met, extraction falls back to static extractors
and a warning is added to the response.
"""

from __future__ import annotations

import logging

from hermes_local_web_extract.extractors.base import ExtractionResult

logger = logging.getLogger(__name__)


class Crawl4AIExtractor:
    """Browser-rendered extractor using Crawl4AI."""

    def _is_available(self) -> bool:
        try:
            import crawl4ai  # noqa: F401

            return True
        except ImportError:
            return False

    async def extract_async(self, url: str, timeout_seconds: int = 20) -> ExtractionResult:
        result = ExtractionResult(extractor_name="crawl4ai")

        if not self._is_available():
            result.warnings.append(
                "crawl4ai is not installed. Install with: "
                "pip install 'hermes-local-web-extract[browser]'. "
                "Falling back to static extraction."
            )
            return result

        try:
            from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig

            browser_config = BrowserConfig(headless=True, verbose=False)
            run_config = CrawlerRunConfig(
                page_timeout=timeout_seconds * 1000,
                wait_until="networkidle",
            )

            async with AsyncWebCrawler(config=browser_config) as crawler:
                crawl_result = await crawler.arun(url=url, config=run_config)

            if crawl_result.success:
                result.markdown = crawl_result.markdown or crawl_result.fit_markdown
                result.text = crawl_result.text
                result.html = crawl_result.html
                result.title = crawl_result.metadata.get("title") if crawl_result.metadata else None
            else:
                result.warnings.append(
                    f"crawl4ai browser extraction failed: {crawl_result.error_message}"
                )
        except Exception as exc:
            logger.warning("crawl4ai extraction error: %s", exc)
            result.warnings.append(f"crawl4ai extraction error: {exc}. Falling back.")

        return result
