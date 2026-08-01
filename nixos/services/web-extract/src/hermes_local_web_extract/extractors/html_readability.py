"""Secondary HTML extractor using BeautifulSoup + markdownify."""

import logging
import re

from bs4 import BeautifulSoup, Tag
from markdownify import markdownify

from hermes_local_web_extract.extractors.base import ExtractionResult

logger = logging.getLogger(__name__)

_NOISE_TAGS = [
    "script",
    "style",
    "noscript",
    "iframe",
    "nav",
    "header",
    "footer",
    "aside",
    "form",
    "button",
    "input",
    "select",
    "textarea",
    "svg",
    "figure",
    "figcaption",
    "advertisement",
    "ad",
]


class ReadabilityExtractor:
    """
    BeautifulSoup-based extractor that strips noise tags and preferentially
    extracts article/main content before falling back to body.
    """

    def extract(self, content: bytes, url: str, content_type: str) -> ExtractionResult:
        result = ExtractionResult(extractor_name="readability")

        try:
            soup = BeautifulSoup(content, "lxml")
        except Exception:
            try:
                soup = BeautifulSoup(content, "html.parser")
            except Exception as exc:
                result.warnings.append(f"HTML parse error: {exc}")
                return result

        # Extract metadata from head
        result.title = self._extract_title(soup)
        result.description = self._extract_description(soup)
        result.author = self._extract_meta(soup, ["author", "twitter:creator"])
        result.date = self._extract_meta(soup, ["article:published_time", "date", "pubdate"])
        result.site_name = self._extract_meta(soup, ["og:site_name"])

        # Remove noise
        for tag_name in _NOISE_TAGS:
            for tag in soup.find_all(tag_name):
                tag.decompose()

        # Prefer article/main over body
        content_node = (
            soup.find("article")
            or soup.find("main")
            or soup.find(id=re.compile(r"content|main|article", re.I))
            or soup.find(class_=re.compile(r"content|main|article|post", re.I))
            or soup.find("body")
        )

        if not content_node:
            result.warnings.append("Could not find content node in HTML.")
            return result

        try:
            markdown_text = markdownify(str(content_node), heading_style="ATX", strip=["a"])
            result.markdown = _clean_markdown(markdown_text)
            result.text = content_node.get_text(separator="\n", strip=True)
        except Exception as exc:
            result.warnings.append(f"Markdownify conversion error: {exc}")
            result.text = content_node.get_text(separator="\n", strip=True)

        return result

    def _extract_title(self, soup: BeautifulSoup) -> str | None:
        og = soup.find("meta", property="og:title")
        if og and isinstance(og, Tag):
            v = og.get("content")
            if v:
                return str(v).strip()
        title_tag = soup.find("title")
        if title_tag:
            return title_tag.get_text(strip=True)
        h1 = soup.find("h1")
        if h1:
            return h1.get_text(strip=True)
        return None

    def _extract_description(self, soup: BeautifulSoup) -> str | None:
        for prop in ["og:description", "description", "twitter:description"]:
            tag = soup.find("meta", property=prop) or soup.find("meta", attrs={"name": prop})
            if tag and isinstance(tag, Tag):
                v = tag.get("content")
                if v:
                    return str(v).strip()
        return None

    def _extract_meta(self, soup: BeautifulSoup, names: list[str]) -> str | None:
        for name in names:
            tag = soup.find("meta", property=name) or soup.find("meta", attrs={"name": name})
            if tag and isinstance(tag, Tag):
                v = tag.get("content")
                if v:
                    return str(v).strip()
        return None


def _clean_markdown(text: str) -> str:
    # Collapse 3+ blank lines to 2
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()
