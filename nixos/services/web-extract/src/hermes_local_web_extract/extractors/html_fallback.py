"""Last-resort fallback HTML extractor."""

import logging
import re

from bs4 import BeautifulSoup
from markdownify import markdownify

from hermes_local_web_extract.extractors.base import ExtractionResult

logger = logging.getLogger(__name__)


class FallbackExtractor:
    """Strip everything except the body text and convert to markdown."""

    def extract(self, content: bytes, url: str, content_type: str) -> ExtractionResult:
        result = ExtractionResult(extractor_name="fallback")

        try:
            soup = BeautifulSoup(content, "html.parser")
        except Exception as exc:
            result.warnings.append(f"HTML parse error: {exc}")
            return result

        for tag in soup(["script", "style", "noscript", "iframe", "svg"]):
            tag.decompose()

        body = soup.find("body") or soup
        try:
            raw_md = markdownify(str(body), heading_style="ATX")
            result.markdown = re.sub(r"\n{3,}", "\n\n", raw_md).strip()
        except Exception as exc:
            result.warnings.append(f"markdownify error: {exc}")

        result.text = body.get_text(separator="\n", strip=True)
        result.warnings.append("Content extracted using last-resort fallback; quality may be low.")
        return result
