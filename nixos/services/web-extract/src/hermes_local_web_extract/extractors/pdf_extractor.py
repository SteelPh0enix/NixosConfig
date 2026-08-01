"""PDF text extractor using pypdf.

pypdf was chosen over pymupdf because:
- Pure-Python, no native binary dependency — works in minimal Docker images.
- Apache-2.0 licensed, compatible with this project.
- Adequate for extracting text from standard PDFs.
- pymupdf (MuPDF) uses AGPL, which imposes copyleft constraints.

For scanned/image PDFs that require OCR, this extractor will return minimal
or empty text. That is a known limitation documented in docs/limitations.md.
"""

import io
import logging

from hermes_local_web_extract.extractors.base import ExtractionResult

logger = logging.getLogger(__name__)

_MAX_PAGES = 200


class PDFExtractor:
    def extract(self, content: bytes, url: str, content_type: str) -> ExtractionResult:
        result = ExtractionResult(extractor_name="pypdf")

        try:
            from pypdf import PdfReader
        except ImportError:
            result.warnings.append("pypdf not installed; PDF extraction unavailable.")
            return result

        try:
            reader = PdfReader(io.BytesIO(content))
        except Exception as exc:
            result.warnings.append(f"Could not open PDF: {exc}")
            return result

        pages = reader.pages
        if len(pages) > _MAX_PAGES:
            result.warnings.append(
                f"PDF has {len(pages)} pages; only extracting first {_MAX_PAGES}."
            )
            pages = pages[:_MAX_PAGES]

        parts: list[str] = []
        for i, page in enumerate(pages):
            try:
                text = page.extract_text() or ""
                parts.append(text)
            except Exception as exc:
                logger.debug("Page %d extraction error: %s", i, exc)
                parts.append("")

        full_text = "\n\n".join(p for p in parts if p.strip())

        if not full_text.strip():
            result.warnings.append(
                "PDF appears to contain no extractable text (may be scanned/image-based)."
            )

        result.text = full_text

        # Build a simple markdown representation
        md_lines: list[str] = []
        try:
            meta = reader.metadata
            if meta and meta.title:
                md_lines.append(f"# {meta.title}\n")
                result.title = str(meta.title)
            if meta and meta.author:
                result.author = str(meta.author)
        except Exception as exc:
            logger.debug("PDF metadata extraction error: %s", exc)

        md_lines.append(full_text)
        result.markdown = "\n".join(md_lines)
        return result
